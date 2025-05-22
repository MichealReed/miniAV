#define _GNU_SOURCE
#include "camera_context_linux_pipewire.h"
#include "../../../include/miniav_buffer.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"

#include <pipewire/pipewire.h>
#include <spa/debug/types.h>
#include <spa/param/props.h>
#include <spa/param/video/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/pod/parser.h>

#include <fcntl.h>   // For O_CLOEXEC with pipe
#include <pthread.h> // For threading the main loop
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h> // For usleep (optional, for shutdown)

// Max number of formats we'll try to report for a device
#define PW_MAX_REPORTED_FORMATS 128
// Max number of devices we'll report
#define PW_MAX_REPORTED_DEVICES 32

typedef struct PipeWireDeviceTempInfo {
  MiniAVDeviceInfo info;
  bool is_video_source;
  // Add other temp fields if needed during enumeration
} PipeWireDeviceTempInfo;

typedef struct PipeWireEnumData {
  struct pw_main_loop *loop;
  MiniAVDeviceInfo *devices_list;
  uint32_t *devices_count;
  uint32_t allocated_devices;
  MiniAVResultCode result;
  int pending_sync; // Counter for pending sync events
} PipeWireEnumData;

typedef struct PipeWireFormatEnumData {
  struct pw_main_loop *loop;
  MiniAVVideoInfo *formats_list;
  uint32_t *formats_count;
  uint32_t allocated_formats;
  MiniAVResultCode result;
  int pending_sync;
  uint32_t node_id;
  struct pw_core *core;
  struct pw_node *node_proxy;
} PipeWireFormatEnumData;

typedef struct PipeWirePlatformContext {
  MiniAVCameraContext *parent_ctx;

  struct pw_main_loop *loop;
  struct pw_context *context;
  struct pw_core *core;
  struct pw_registry *registry;
  struct spa_hook registry_listener;

  struct pw_stream *stream;
  struct spa_hook stream_listener;

  pthread_t loop_thread;
  bool loop_running;
  int wakeup_pipe[2]; // Pipe to wake up the loop for shutdown

  // Configuration
  uint32_t target_node_id;
  MiniAVVideoInfo configured_video_format;
  bool is_configured;
  bool is_streaming;

  // Temporary data for enumeration/format fetching
  PipeWireDeviceTempInfo temp_devices[PW_MAX_REPORTED_DEVICES];
  uint32_t num_temp_devices;

  uint32_t num_temp_formats;

  int pending_sync_ops; // For sync operations during init/enum

} PipeWirePlatformContext;

typedef struct PipeWireFrameReleasePayload {
  MiniAVOutputPreference type;
  union {
    struct { // For CPU
      void *cpu_ptr;
      size_t cpu_size;
      int src_dmabuf_fd; // Not owned, for debug
    } cpu;
    struct {             // For GPU
      int dup_dmabuf_fd; // Must be closed
    } gpu;
  };
} PipeWireFrameReleasePayload;

// Forward declarations for static functions

static MiniAVResultCode pw_init_platform(MiniAVCameraContext *ctx);
static MiniAVResultCode pw_destroy_platform(MiniAVCameraContext *ctx);
static MiniAVResultCode pw_enumerate_devices(MiniAVDeviceInfo **devices_out,
                                             uint32_t *count_out);
static MiniAVResultCode pw_get_supported_formats(const char *device_id_str,
                                                 MiniAVVideoInfo **formats_out,
                                                 uint32_t *count_out);
static MiniAVResultCode pw_configure(MiniAVCameraContext *ctx,
                                     const char *device_id,
                                     const MiniAVVideoInfo *format);
static MiniAVResultCode pw_start_capture(MiniAVCameraContext *ctx);
static MiniAVResultCode pw_get_buffer(MiniAVCameraContext *ctx,
                                      MiniAVBuffer *buffer,
                                      uint32_t timeout_ms);
static MiniAVResultCode pw_release_buffer(MiniAVCameraContext *ctx,
                                          void *buffer);
static MiniAVResultCode
pw_stop_capture(MiniAVCameraContext *ctx); // <--- ADD THIS FORWARD DECLARATION

// --- Helper Functions ---

static MiniAVPixelFormat
spa_video_format_to_miniav(uint32_t spa_format,
                           const struct spa_pod *format_pod) {
  switch (spa_format) {
  case SPA_VIDEO_FORMAT_RGB:
    return MINIAV_PIXEL_FORMAT_RGB24;
  case SPA_VIDEO_FORMAT_BGR:
    return MINIAV_PIXEL_FORMAT_BGR24;
  case SPA_VIDEO_FORMAT_RGBA:
    return MINIAV_PIXEL_FORMAT_RGBA32;
  case SPA_VIDEO_FORMAT_BGRA:
    return MINIAV_PIXEL_FORMAT_BGRA32;
  case SPA_VIDEO_FORMAT_ARGB:
    return MINIAV_PIXEL_FORMAT_ARGB32;
  case SPA_VIDEO_FORMAT_ABGR:
    return MINIAV_PIXEL_FORMAT_ABGR32;
  case SPA_VIDEO_FORMAT_YUY2:
    return MINIAV_PIXEL_FORMAT_YUY2;
  case SPA_VIDEO_FORMAT_UYVY:
    return MINIAV_PIXEL_FORMAT_UYVY;
  case SPA_VIDEO_FORMAT_I420:
    return MINIAV_PIXEL_FORMAT_I420;
  case SPA_VIDEO_FORMAT_NV12:
    return MINIAV_PIXEL_FORMAT_NV12;
    // No direct SPA_VIDEO_FORMAT_MJPG in spa-0.2/raw.h
    // case SPA_VIDEO_FORMAT_MJPG:      return MINIAV_PIXEL_FORMAT_MJPEG;

  case SPA_VIDEO_FORMAT_ENCODED:
    if (format_pod) {
      struct spa_pod_prop *prop;
      struct spa_pod_object *obj = (struct spa_pod_object *)format_pod;
      SPA_POD_OBJECT_FOREACH(obj, prop) {
        if (prop->key == SPA_FORMAT_mediaSubtype) {
          // The value of SPA_FORMAT_mediaSubtype is expected to be an Id pod
          if (spa_pod_is_id(&prop->value)) {
            uint32_t subtype_id;
            if (spa_pod_get_id(&prop->value, &subtype_id) == 0) {
              const char *subtype_name =
                  spa_debug_type_find_name(spa_type_media_subtype, subtype_id);
              if (subtype_name) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                           "PW: Media subtype ID %u is '%s'", subtype_id,
                           subtype_name);
                if (strcmp(subtype_name, "jpeg") == 0 ||
                    strcmp(subtype_name, "mjpeg") == 0) {
                  return MINIAV_PIXEL_FORMAT_MJPEG;
                }
                // Add other encoded subtypes if needed by comparing
                // subtype_name
              } else {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                           "PW: Media subtype ID %u not found in debug types.",
                           subtype_id);
              }
            }
          } else if (spa_pod_is_string(&prop->value)) {
            // Less common for mediaSubtype, but handle if it's a direct string
            const char *subtype_name_str = NULL;
            if (spa_pod_get_string(&prop->value, &subtype_name_str) == 0 &&
                subtype_name_str) {
              miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                         "PW: Media subtype string is '%s'", subtype_name_str);
              if (strcmp(subtype_name_str, "jpeg") == 0 ||
                  strcmp(subtype_name_str, "mjpeg") == 0) {
                return MINIAV_PIXEL_FORMAT_MJPEG;
              }
            }
          }
          break;
        }
      }
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: SPA_VIDEO_FORMAT_ENCODED found, but subtype not MJPEG or "
               "not identifiable from pod.");
    return MINIAV_PIXEL_FORMAT_UNKNOWN; // Or a generic encoded type if you have
                                        // one

  default:
    return MINIAV_PIXEL_FORMAT_UNKNOWN;
  }
}

static uint32_t miniav_pixel_format_to_spa(MiniAVPixelFormat miniav_format) {
  switch (miniav_format) {
  case MINIAV_PIXEL_FORMAT_RGB24:
    return SPA_VIDEO_FORMAT_RGB;
  case MINIAV_PIXEL_FORMAT_BGR24:
    return SPA_VIDEO_FORMAT_BGR;
  case MINIAV_PIXEL_FORMAT_RGBA32:
    return SPA_VIDEO_FORMAT_RGBA;
  case MINIAV_PIXEL_FORMAT_BGRA32:
    return SPA_VIDEO_FORMAT_BGRA;
  case MINIAV_PIXEL_FORMAT_ARGB32:
    return SPA_VIDEO_FORMAT_ARGB;
  case MINIAV_PIXEL_FORMAT_ABGR32:
    return SPA_VIDEO_FORMAT_ABGR;
  case MINIAV_PIXEL_FORMAT_YUY2:
    return SPA_VIDEO_FORMAT_YUY2;
  case MINIAV_PIXEL_FORMAT_UYVY:
    return SPA_VIDEO_FORMAT_UYVY;
  case MINIAV_PIXEL_FORMAT_I420:
    return SPA_VIDEO_FORMAT_I420;
  case MINIAV_PIXEL_FORMAT_NV12:
    return SPA_VIDEO_FORMAT_NV12;
  case MINIAV_PIXEL_FORMAT_MJPEG:
    return SPA_VIDEO_FORMAT_ENCODED; // MJPEG will be SPA_VIDEO_FORMAT_ENCODED
                                     // The specific subtype "jpeg" or "mjpeg"
                                     // needs to be set in the
                                     // SPA_FORMAT_mediaSubtype property when
                                     // building the params for
                                     // pw_stream_update_params.
  default:
    return SPA_VIDEO_FORMAT_UNKNOWN;
  }
}

const char *miniav_pixel_format_to_string_short(MiniAVPixelFormat format) {
  switch (format) {
  case MINIAV_PIXEL_FORMAT_UNKNOWN:
    return "UNKN";
  case MINIAV_PIXEL_FORMAT_I420:
    return "I420";
  case MINIAV_PIXEL_FORMAT_NV12:
    return "NV12";
  case MINIAV_PIXEL_FORMAT_NV21:
    return "NV21";
  case MINIAV_PIXEL_FORMAT_YUY2:
    return "YUY2";
  case MINIAV_PIXEL_FORMAT_UYVY:
    return "UYVY";
  case MINIAV_PIXEL_FORMAT_RGB24:
    return "RGB24";
  case MINIAV_PIXEL_FORMAT_BGR24:
    return "BGR24";
  case MINIAV_PIXEL_FORMAT_RGBA32:
    return "RGBA32";
  case MINIAV_PIXEL_FORMAT_BGRA32:
    return "BGRA32";
  case MINIAV_PIXEL_FORMAT_ARGB32:
    return "ARGB32";
  case MINIAV_PIXEL_FORMAT_ABGR32:
    return "ABGR32";
  case MINIAV_PIXEL_FORMAT_MJPEG:
    return "MJPG";
  // Add all other formats your MiniAVPixelFormat enum supports
  default:
    return "INV"; // Invalid/Unknown
  }
}

static void
parse_spa_format(const struct spa_pod *format_pod, MiniAVVideoInfo *info,
                 PipeWirePlatformContext *pw_ctx) { // pw_ctx can be NULL
  struct spa_video_info_raw raw_info = {0};
  // MINIAV_UNUSED(pw_ctx); // If pw_ctx is truly unused in this function.
  // Currently it is.

  if (spa_format_video_raw_parse(format_pod, &raw_info) >= 0) {
    info->pixel_format = spa_video_format_to_miniav(
        raw_info.format, format_pod); // Pass format_pod for MJPEG subtype check
    info->width = raw_info.size.width;
    info->height = raw_info.size.height;
    info->frame_rate_numerator = raw_info.framerate.num;
    info->frame_rate_denominator = raw_info.framerate.denom;

    // It's good practice to ensure framerate denominator is not zero if num is
    // non-zero
    if (info->frame_rate_numerator != 0 && info->frame_rate_denominator == 0) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW: Parsed format with numerator %u but denominator 0. "
                 "Setting denominator to 1.",
                 info->frame_rate_numerator);
      info->frame_rate_denominator = 1; // Avoid division by zero later
    }

  } else {
    if (spa_pod_is_choice(format_pod)) { // This case should ideally be handled
                                         // by parse_spa_format_choices
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW: parse_spa_format called with a CHOICE/ANY type pod. This "
                 "should be handled by parse_spa_format_choices.");
    } else {
      // spa_format_video_raw_parse failed, and it wasn't a choice.
      // This could be SPA_VIDEO_FORMAT_ENCODED without enough info for
      // raw_parse, or other non-raw types. spa_video_format_to_miniav might
      // still be able to identify MJPEG from SPA_VIDEO_FORMAT_ENCODED.
      struct spa_video_info_dsp dsp_info = {0}; // Declare the struct
      uint32_t spa_fmt_id = SPA_VIDEO_FORMAT_UNKNOWN;

      if (spa_format_video_dsp_parse(format_pod, &dsp_info) >=
          0) {                        // Pass address of struct
        spa_fmt_id = dsp_info.format; // Extract the format
      } else {
        // Fallback if dsp_parse also fails, though less likely to give a format
        // ID
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "PW: spa_format_video_dsp_parse also failed for non-raw format.");
      }

      info->pixel_format = spa_video_format_to_miniav(spa_fmt_id, format_pod);
      if (info->pixel_format == MINIAV_PIXEL_FORMAT_MJPEG) {
        // For MJPEG, W/H/FPS might not be in spa_video_info_raw or
        // spa_video_info_dsp. They might be in other properties of the
        // format_pod. This part needs more complex parsing if MJPEG streams
        // don't provide W/H/FPS via these parse functions. For now, we rely on
        // spa_format_video_raw_parse or accept that W/H might be 0 for some
        // encoded. The check for width/height == 0 in the caller will filter
        // these out if they are unusable.
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "PW: Identified MJPEG from non-raw/dsp parse. W/H/FPS might "
                   "be missing from this path.");
      } else if (spa_fmt_id != SPA_VIDEO_FORMAT_UNKNOWN) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "PW: Could not parse as spa_video_info_raw, but got format "
                   "%u from dsp_parse.",
                   spa_fmt_id);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "PW: Could not parse as spa_video_info_raw and not "
                   "identifiable as MJPEG or from dsp_parse. Format unknown.");
      }
    }
    if (info->pixel_format ==
        MINIAV_PIXEL_FORMAT_UNKNOWN) { // Ensure it's set if all parsing fails
      info->pixel_format = MINIAV_PIXEL_FORMAT_UNKNOWN;
    }
  }
}
// --- Stream Callbacks ---
static void on_stream_process(void *userdata) {
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)userdata;
  struct pw_buffer *pw_buf;
  if (!pw_ctx || !pw_ctx->parent_ctx || !pw_ctx->parent_ctx->app_callback)
    return;

  pw_buf = pw_stream_dequeue_buffer(pw_ctx->stream);
  if (!pw_buf)
    return;

  struct spa_buffer *spa_buf = pw_buf->buffer;
  struct spa_data *d = &spa_buf->datas[0];

  // Log the buffer type
  const char *type_str = "UNKNOWN";
  switch (d->type) {
  case SPA_DATA_DmaBuf:
    type_str = "DmaBuf";
    break;
  case SPA_DATA_MemFd:
    type_str = "MemFd";
    break;
  case SPA_DATA_MemPtr:
    type_str = "MemPtr";
    break;
  }
  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Received buffer type: %s (type=%d)",
             type_str, d->type);

  MiniAVBuffer *miniav_buf =
      (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
  if (!miniav_buf) {
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }

  miniav_buf->type = MINIAV_BUFFER_TYPE_VIDEO;
  miniav_buf->timestamp_us = pw_buf->time; // TODO: convert if needed
  miniav_buf->data.video.info = pw_ctx->configured_video_format;
  miniav_buf->user_data = pw_ctx->parent_ctx->app_callback_user_data;

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
  if (!payload) {
    miniav_free(miniav_buf);
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }
  payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA;
  payload->context_owner = pw_ctx->parent_ctx;
  payload->parent_miniav_buffer_ptr = miniav_buf;

  PipeWireFrameReleasePayload *frame_payload =
      (PipeWireFrameReleasePayload *)miniav_calloc(
          1, sizeof(PipeWireFrameReleasePayload));
  if (!frame_payload) {
    miniav_free(payload);
    miniav_free(miniav_buf);
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }

  bool ok = false;
  if (d->type == SPA_DATA_DmaBuf && d->fd >= 0) {
    int dup_fd = fcntl(d->fd, F_DUPFD_CLOEXEC, 0);
    if (dup_fd != -1) {
      miniav_buf->content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_DMABUF_FD;
      miniav_buf->data.video.native_gpu_dmabuf_fd = dup_fd;
      miniav_buf->data_size_bytes = d->maxsize;
      frame_payload->type = MINIAV_OUTPUT_PREFERENCE_GPU;
      frame_payload->gpu.dup_dmabuf_fd = dup_fd;
      payload->native_resource_ptr = frame_payload;
      ok = true;
    }
  } else if ((d->type == SPA_DATA_MemFd || d->type == SPA_DATA_MemPtr) &&
             d->data && d->chunk && d->chunk->size > 0) {
    void *cpu_ptr = miniav_malloc(d->chunk->size);
    if (cpu_ptr) {
      memcpy(cpu_ptr, d->data, d->chunk->size);
      miniav_buf->data.video.planes[0] = cpu_ptr;
      miniav_buf->data.video.stride_bytes[0] = d->chunk->stride;
      miniav_buf->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
      miniav_buf->data_size_bytes = d->chunk->size;
      frame_payload->type = MINIAV_OUTPUT_PREFERENCE_CPU;
      frame_payload->cpu.cpu_ptr = cpu_ptr;
      frame_payload->cpu.cpu_size = d->chunk->size;
      frame_payload->cpu.src_dmabuf_fd =
          (d->type == SPA_DATA_MemFd) ? d->fd : -1;
      payload->native_resource_ptr = frame_payload;
      ok = true;
    }
  }

  if (!ok) {
    miniav_free(frame_payload);
    miniav_free(payload);
    miniav_free(miniav_buf);
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }

  miniav_buf->internal_handle = payload;
  pw_ctx->parent_ctx->app_callback(miniav_buf,
                                   pw_ctx->parent_ctx->app_callback_user_data);

  pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
}

static void on_stream_state_changed(void *userdata, enum pw_stream_state old,
                                    enum pw_stream_state state,
                                    const char *error) {
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)userdata;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Stream state changed from %s to %s.",
             pw_stream_state_as_string(old), pw_stream_state_as_string(state));

  if (error) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Stream error: %s", error);
    pw_ctx->is_streaming = false; // Stop on error
    if (pw_ctx->loop_running && pw_ctx->loop) {
      if (pw_ctx->wakeup_pipe[1] != -1)
        write(pw_ctx->wakeup_pipe[1], "q", 1); // Wake loop to exit
    }
    return;
  }

  switch (state) {
  case PW_STREAM_STATE_UNCONNECTED:
  case PW_STREAM_STATE_ERROR:
    pw_ctx->is_streaming = false;
    if (pw_ctx->loop_running && pw_ctx->loop) {
      if (pw_ctx->wakeup_pipe[1] != -1)
        write(pw_ctx->wakeup_pipe[1], "q", 1);
    }
    break;
  case PW_STREAM_STATE_CONNECTING:
    break;
  case PW_STREAM_STATE_PAUSED: // Should mean ready to receive/negotiate format
    pw_ctx->is_streaming = true; // Or a "ready" flag
    // Negotiate format
    {
      uint8_t buffer[1024];
      struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
      const struct spa_pod *params[1];
      uint32_t spa_format = miniav_pixel_format_to_spa(
          pw_ctx->configured_video_format.pixel_format);

      params[0] = spa_format_video_raw_build(
          &b, SPA_PARAM_EnumFormat,
          &SPA_VIDEO_INFO_RAW_INIT(
                  .format = spa_format,
                  .size = SPA_RECTANGLE(pw_ctx->configured_video_format.width,
                                        pw_ctx->configured_video_format.height),
                  .framerate = SPA_FRACTION(
                      pw_ctx->configured_video_format.frame_rate_numerator,
                      pw_ctx->configured_video_format.frame_rate_denominator)));

      if (pw_stream_update_params(pw_ctx->stream, params, 1) < 0) {
        miniav_log(
            MINIAV_LOG_LEVEL_ERROR,
            "PW: Failed to update stream params for format negotiation.");
      } else {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "PW: Requested stream format %s, %ux%u @ %u/%u.",
                   spa_debug_type_find_name(spa_type_video_format, spa_format),
                   pw_ctx->configured_video_format.width,
                   pw_ctx->configured_video_format.height,
                   pw_ctx->configured_video_format.frame_rate_numerator,
                   pw_ctx->configured_video_format.frame_rate_denominator);
      }
    }
    break;
  case PW_STREAM_STATE_STREAMING:
    miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Stream is now streaming.");
    pw_ctx->is_streaming = true;
    break;
  default:
    break;
  }
}

static void on_stream_param_changed(void *userdata, uint32_t id,
                                    const struct spa_pod *param) {
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)userdata;
  if (!param || id != SPA_PARAM_Format) {
    return;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Stream SPA_PARAM_Format changed.");

  MiniAVVideoInfo current_stream_format = {0};
  parse_spa_format(param, &current_stream_format, pw_ctx);

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW: Negotiated stream format: %s, %ux%u @ %u/%u.",
             miniav_pixel_format_to_string_short(
                 current_stream_format
                     .pixel_format), // Assuming you have such a helper
             current_stream_format.width, current_stream_format.height,
             current_stream_format.frame_rate_numerator,
             current_stream_format.frame_rate_denominator);

  // Here you might want to verify if current_stream_format matches
  // configured_video_format and potentially update
  // pw_ctx->configured_video_format if the device chose a compatible
  // alternative. For now, we assume the device accepted our request or
  // something close.

  // After format is set, we can connect the stream if it's not already
  // connecting to streaming
  if (pw_stream_get_state(pw_ctx->stream, NULL) == PW_STREAM_STATE_PAUSED) {
    if (pw_stream_set_active(pw_ctx->stream, true) < 0) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to set stream active.");
    }
  }
}

static const struct pw_stream_events stream_events = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = on_stream_state_changed,
    .param_changed = on_stream_param_changed,
    .process = on_stream_process,
};

// --- Registry Callbacks ---
static void registry_event_global(void *data, uint32_t id, uint32_t permissions,
                                  const char *type, uint32_t version,
                                  const struct spa_dict *props) {
  PipeWireEnumData *enum_data = (PipeWireEnumData *)data;

  if (strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
    const char *media_class = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    const char *node_name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    const char *node_description =
        spa_dict_lookup(props, PW_KEY_NODE_DESCRIPTION);
    const char *device_api = spa_dict_lookup(props, PW_KEY_DEVICE_API);

    if (media_class && strstr(media_class, "Video/Source")) {
      // It's a video source, potentially a camera
      if (enum_data->devices_list && enum_data->devices_count &&
          (*enum_data->devices_count < enum_data->allocated_devices)) {
        MiniAVDeviceInfo *dev_info =
            &enum_data
                 ->devices_list[*enum_data->devices_count]; // Corrected line
        memset(dev_info, 0, sizeof(MiniAVDeviceInfo));

        snprintf(dev_info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "%u", id);
        if (node_description) {
          miniav_strlcpy(dev_info->name, node_description,
                         MINIAV_DEVICE_NAME_MAX_LEN);
        } else if (node_name) {
          miniav_strlcpy(dev_info->name, node_name, MINIAV_DEVICE_NAME_MAX_LEN);
        } else {
          snprintf(dev_info->name, MINIAV_DEVICE_NAME_MAX_LEN,
                   "PipeWire Node %u", id);
        }
        dev_info->is_default = false;

        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "PW: Found Video/Source: ID=%s, Name='%s', MediaClass='%s', "
                   "API='%s'",
                   dev_info->device_id, dev_info->name, media_class,
                   device_api ? device_api : "N/A");

        (*enum_data->devices_count)++;
      }
    }
  }
}

static void registry_event_global_remove(void *data, uint32_t id) {
  // Handle device removal if necessary, e.g., update UI or internal lists.
  // For a one-shot enumeration, this might not be critical.
}

static const struct pw_registry_events registry_events = {
    PW_VERSION_REGISTRY_EVENTS,
    .global = registry_event_global,
    .global_remove = registry_event_global_remove,
};

// --- Core Callbacks for sync ---
static void on_core_sync_done_enum(void *data, uint32_t id,
                                   int seq) { // Added uint32_t id
  PipeWireEnumData *enum_data = (PipeWireEnumData *)data;
  MINIAV_UNUSED(id); // If id is not used
  if (enum_data->pending_sync == seq) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Core sync done for enumeration.");
    pw_main_loop_quit(enum_data->loop);
  }
}
static void on_core_sync_done_format(void *data, uint32_t id,
                                     int seq) { // Added uint32_t id
  PipeWireFormatEnumData *format_data = (PipeWireFormatEnumData *)data;
  MINIAV_UNUSED(id); // If id is not used
  if (format_data->pending_sync == seq) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: Core sync done for format enumeration.");
    pw_main_loop_quit(format_data->loop);
  }
}

static const struct pw_core_events core_sync_events = {
    PW_VERSION_CORE_EVENTS,
    .done = on_core_sync_done_enum, // Will be replaced for format enum
};

// --- Platform Ops Implementation ---

// Define the callback function for the wakeup pipe
static void on_wakeup_pipe_event(void *data, int fd, uint32_t mask) {
  PipeWirePlatformContext *ctx = (PipeWirePlatformContext *)data;
  char buf[1];
  ssize_t len = read(fd, buf, sizeof(buf)); // Store read result

  if (len > 0 && buf[0] == 'q') {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Wakeup pipe received quit signal.");
    pw_main_loop_quit(ctx->loop);
  } else if (len == -1 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
    // This case might not be strictly necessary if pw_loop only calls this when
    // readable, but good for robustness if the fd was independently set to
    // non-blocking.
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: Wakeup pipe read would block (EAGAIN/EWOULDBLOCK).");
  } else if (len == 0) {
    // EOF - pipe closed from the other end unexpectedly?
    miniav_log(MINIAV_LOG_LEVEL_WARN, "PW: Wakeup pipe read EOF.");
    // Optionally, quit the loop here too if this is an unrecoverable state
    // pw_main_loop_quit(ctx->loop);
  } else if (len < 0) {
    // Actual read error
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Wakeup pipe read error: %s. Quitting loop.",
               strerror(errno));
    pw_main_loop_quit(ctx->loop); // Quit on error to prevent busy loop
  }
  // If len > 0 but buf[0] != 'q', it's unexpected data, can be ignored or
  // logged.
}

static void *pipewire_loop_thread_func(void *arg) {
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)arg;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: PipeWire loop thread started.");
  pw_ctx->loop_running = true;

  // Add wakeup_pipe's read end to the loop's sources
  struct pw_loop *loop = pw_main_loop_get_loop(pw_ctx->loop);
  struct spa_source *wakeup_source = NULL; // Initialize to NULL

  if (pw_ctx->wakeup_pipe[0] != -1) { // Ensure pipe fd is valid
    wakeup_source =
        pw_loop_add_io(loop, pw_ctx->wakeup_pipe[0], SPA_IO_IN,
                       true,                 // close fd on destroy source
                       on_wakeup_pipe_event, // Use the static function here
                       pw_ctx);

    if (!wakeup_source) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW: Failed to add wakeup_pipe IO source to loop. Loop may "
                 "not exit cleanly.");
      // Decide if this is fatal. If the loop can't be signaled to quit, it
      // might hang. For now, we'll let it continue, but pw_stop_capture might
      // not work as expected.
    }
  } else {
    miniav_log(
        MINIAV_LOG_LEVEL_WARN,
        "PW: Wakeup pipe read end is invalid. Loop may not exit cleanly.");
  }

  pw_main_loop_run(pw_ctx->loop);

  if (wakeup_source) { // Only remove if successfully added
    pw_loop_remove_source(loop, wakeup_source); // Clean up wakeup source
  }
}

static MiniAVResultCode pw_init_platform(MiniAVCameraContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Initializing platform context.");
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)miniav_calloc(
      1, sizeof(PipeWirePlatformContext));
  if (!pw_ctx) {
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }
  ctx->platform_ctx = pw_ctx;
  pw_ctx->parent_ctx = ctx;
  pw_ctx->target_node_id = PW_ID_ANY; // Default
  pw_ctx->wakeup_pipe[0] = -1;
  pw_ctx->wakeup_pipe[1] = -1;

  if (pipe2(pw_ctx->wakeup_pipe, O_CLOEXEC | O_NONBLOCK) == -1) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to create wakeup pipe: %s",
               strerror(errno));
    miniav_free(pw_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  pw_init(NULL, NULL); // Initialize PipeWire library

  pw_ctx->loop = pw_main_loop_new(NULL);
  if (!pw_ctx->loop) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to create main loop.");
    goto error_cleanup;
  }

  pw_ctx->context =
      pw_context_new(pw_main_loop_get_loop(pw_ctx->loop), NULL, 0);
  if (!pw_ctx->context) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to create context.");
    goto error_cleanup;
  }

  pw_ctx->core = pw_context_connect(pw_ctx->context, NULL, 0);
  if (!pw_ctx->core) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to connect to PipeWire core/daemon.");
    goto error_cleanup;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW: Platform context initialized successfully.");
  return MINIAV_SUCCESS;

error_cleanup:
  if (pw_ctx->core)
    pw_core_disconnect(pw_ctx->core);
  if (pw_ctx->context)
    pw_context_destroy(pw_ctx->context);
  if (pw_ctx->loop)
    pw_main_loop_destroy(pw_ctx->loop);
  if (pw_ctx->wakeup_pipe[0] != -1)
    close(pw_ctx->wakeup_pipe[0]);
  if (pw_ctx->wakeup_pipe[1] != -1)
    close(pw_ctx->wakeup_pipe[1]);
  miniav_free(pw_ctx);
  ctx->platform_ctx = NULL;
  return MINIAV_ERROR_SYSTEM_CALL_FAILED;
}

static MiniAVResultCode pw_destroy_platform(MiniAVCameraContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Destroying platform context.");
  if (!ctx || !ctx->platform_ctx) {
    return MINIAV_SUCCESS; // Nothing to do
  }
  PipeWirePlatformContext *pw_ctx =
      (PipeWirePlatformContext *)ctx->platform_ctx;

  if (pw_ctx->is_streaming || pw_ctx->loop_running) {
    pw_stop_capture(ctx); // Attempt to stop if still running
  }

  if (pw_ctx->stream) {
    pw_stream_destroy(pw_ctx->stream);
    pw_ctx->stream = NULL;
  }
  if (pw_ctx->core) {
    pw_core_disconnect(pw_ctx->core);
    pw_ctx->core = NULL;
  }
  if (pw_ctx->context) {
    pw_context_destroy(pw_ctx->context);
    pw_ctx->context = NULL;
  }
  if (pw_ctx->loop) {
    pw_main_loop_destroy(pw_ctx->loop);
    pw_ctx->loop = NULL;
  }
  if (pw_ctx->wakeup_pipe[0] != -1)
    close(pw_ctx->wakeup_pipe[0]);
  if (pw_ctx->wakeup_pipe[1] != -1)
    close(pw_ctx->wakeup_pipe[1]);

  miniav_free(pw_ctx);
  ctx->platform_ctx = NULL;
  // pw_deinit(); // Consider if this should be here or if multiple contexts
  // can exist
  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode pw_enumerate_devices(MiniAVDeviceInfo **devices_out,
                                             uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Enumerating devices.");
  if (!devices_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *devices_out = NULL;
  *count_out = 0;

  MiniAVResultCode overall_res = MINIAV_SUCCESS;
  struct pw_main_loop *loop = NULL;
  struct pw_context *context = NULL;
  struct pw_core *core = NULL;
  struct pw_registry *registry = NULL;
  struct spa_hook registry_listener_local;
  struct spa_hook core_listener_local;

  pw_init(NULL,
          NULL); // Ensure library is initialized for this static-like call

  loop = pw_main_loop_new(NULL);
  context = pw_context_new(pw_main_loop_get_loop(loop), NULL, 0);
  core = pw_context_connect(context, NULL, 0);

  if (!loop || !context || !core) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to init PW core for enumeration.");
    overall_res = MINIAV_ERROR_SYSTEM_CALL_FAILED;
    goto enum_cleanup;
  }

  PipeWireEnumData enum_data = {0};
  enum_data.loop = loop;
  enum_data.devices_list = (MiniAVDeviceInfo *)miniav_calloc(
      PW_MAX_REPORTED_DEVICES, sizeof(MiniAVDeviceInfo));
  if (!enum_data.devices_list) {
    overall_res = MINIAV_ERROR_OUT_OF_MEMORY;
    goto enum_cleanup;
  }
  enum_data.allocated_devices = PW_MAX_REPORTED_DEVICES;
  enum_data.devices_count = count_out; // Point to the output param
  *enum_data.devices_count = 0;        // Initialize count
  enum_data.result = MINIAV_SUCCESS;

  registry = pw_core_get_registry(core, PW_VERSION_REGISTRY, 0);
  pw_registry_add_listener(registry, &registry_listener_local, &registry_events,
                           &enum_data);

  // Setup sync mechanism
  struct pw_core_events local_core_events = core_sync_events; // Copy base
  local_core_events.done = on_core_sync_done_enum; // Set specific done callback
  pw_core_add_listener(core, &core_listener_local, &local_core_events,
                       &enum_data);
  enum_data.pending_sync = pw_core_sync(core, PW_ID_CORE, 0);

  pw_main_loop_run(loop); // This will run until pw_main_loop_quit is called
                          // in on_core_sync_done_enum

  if (enum_data.result == MINIAV_SUCCESS) {
    if (*count_out > 0) {
      *devices_out = enum_data.devices_list; // Transfer ownership
                                             // Shrink to fit if desired:
      MiniAVDeviceInfo *final_list =
          miniav_realloc(*devices_out, (*count_out) * sizeof(MiniAVDeviceInfo));
      if (final_list)
        *devices_out = final_list;
      // else keep original larger allocation
    } else {
      miniav_free(enum_data.devices_list); // No devices found
      *devices_out = NULL;
    }
  } else {
    miniav_free(enum_data.devices_list);
    *devices_out = NULL;
    *count_out = 0;
    overall_res = enum_data.result;
  }

enum_cleanup:
  if (registry)
    pw_proxy_destroy((struct pw_proxy *)registry);
  if (core) {
    spa_hook_remove(&core_listener_local); // Remove before disconnect if added
    pw_core_disconnect(core);
  }
  if (context)
    pw_context_destroy(context);
  if (loop)
    pw_main_loop_destroy(loop);
  // pw_deinit(); // Consider static counter for pw_init/deinit calls

  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Enumerated %u devices.", *count_out);
  return overall_res;
}

static void parse_spa_format_choices(const struct spa_pod *format_pod,
                                     PipeWireFormatEnumData *format_data) {
  MiniAVVideoInfo info = {0};
  parse_spa_format(format_pod, &info,
                   NULL); // pw_ctx is NULL as it's not available/needed here.

  if (info.pixel_format != MINIAV_PIXEL_FORMAT_UNKNOWN) {
    if (info.width == 0 || info.height == 0) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW: Fallback format %s resulted in 0 width/height. Skipping.",
                 miniav_pixel_format_to_string_short(info.pixel_format));
    } else if (*format_data->formats_count < format_data->allocated_formats) {
      format_data->formats_list[*format_data->formats_count] = info;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Added format: %s, %ux%u @ %u/%u",
                 miniav_pixel_format_to_string_short(info.pixel_format),
                 info.width, info.height, info.frame_rate_numerator,
                 info.frame_rate_denominator);
      (*format_data->formats_count)++;
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "PW: Reached allocated format limit (%u) with fallback parser.",
          format_data->allocated_formats);
    }
  }
}

static void on_node_param(void *data, int seq, uint32_t id, uint32_t index,
                          uint32_t next, const struct spa_pod *param) {
  PipeWireFormatEnumData *format_data = (PipeWireFormatEnumData *)data;
  const char *id_name = spa_debug_type_find_name(spa_type_param, id);
  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "PW: on_node_param: seq=%d, id=%s (%u), index=%u, next=%u, param_ptr=%p",
      seq, id_name ? id_name : "UNKNOWN_ID", id, index, next, (void *)param);

  if (param && id == SPA_PARAM_EnumFormat) {
    parse_spa_format_choices(param, format_data);

    pw_main_loop_quit(format_data->loop);
  }
}

static void on_node_info(void *data, const struct pw_node_info *info) {
  PipeWireFormatEnumData *format_data = (PipeWireFormatEnumData *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW: Received node info for format enumeration (node %u).",
             format_data->node_id);

  if (info) {
    pw_node_enum_params(format_data->node_proxy, 1, SPA_PARAM_EnumFormat, 0,
                        UINT32_MAX, NULL);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW: on_node_info called with NULL info.");
    format_data->result = MINIAV_ERROR_DEVICE_NOT_FOUND;
    if (format_data->loop) {
      pw_main_loop_quit(format_data->loop);
    }
  }
}

static const struct pw_node_events node_info_events = {
    PW_VERSION_NODE_EVENTS,
    .info = on_node_info,
    .param = on_node_param,
};

static MiniAVResultCode pw_get_supported_formats(const char *device_id_str,
                                                 MiniAVVideoInfo **formats_out,
                                                 uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW: Getting supported formats for device ID %s.", device_id_str);
  if (!device_id_str || !formats_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *formats_out = NULL;
  *count_out = 0;

  uint32_t node_id = (uint32_t)atoi(device_id_str);
  if (node_id == 0 &&
      strcmp(device_id_str, "0") != 0) { // Basic check for valid uint
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Invalid device_id string for format enumeration: %s",
               device_id_str);
    return MINIAV_ERROR_INVALID_ARG;
  }

  MiniAVResultCode overall_res = MINIAV_SUCCESS;
  struct pw_main_loop *loop = NULL;
  struct pw_context *context = NULL;
  struct pw_core *core = NULL;
  struct pw_node *node_proxy = NULL;
  struct spa_hook node_listener_local;
  // struct spa_hook core_listener_local; // Not using core sync for this
  // simplified version

  pw_init(NULL, NULL);

  loop = pw_main_loop_new(NULL);
  context = pw_context_new(pw_main_loop_get_loop(loop), NULL, 0);
  core = pw_context_connect(context, NULL, 0);

  if (!loop || !context || !core) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to init PW core for format enumeration.");
    overall_res = MINIAV_ERROR_SYSTEM_CALL_FAILED;
    goto format_enum_cleanup;
  }

  PipeWireFormatEnumData format_data = {0};
  format_data.loop = loop;
  format_data.formats_list = (MiniAVVideoInfo *)miniav_calloc(
      PW_MAX_REPORTED_FORMATS, sizeof(MiniAVVideoInfo));
  if (!format_data.formats_list) {
    overall_res = MINIAV_ERROR_OUT_OF_MEMORY;
    goto format_enum_cleanup;
  }
  format_data.allocated_formats = PW_MAX_REPORTED_FORMATS;
  format_data.formats_count = count_out;
  *format_data.formats_count = 0;
  format_data.result = MINIAV_SUCCESS; // Default to success
  format_data.node_id = node_id;
  format_data.core = core;

  // Bind to the node to get its info
  node_proxy = (struct pw_node *)pw_registry_bind(
      pw_core_get_registry(core, PW_VERSION_REGISTRY, 0), node_id,
      PW_TYPE_INTERFACE_Node, PW_VERSION_NODE, 0);
  format_data.node_proxy = node_proxy;
  if (!node_proxy) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to bind to node %u for format enumeration.",
               node_id);
    overall_res = MINIAV_ERROR_DEVICE_NOT_FOUND; // Or system call failed
    miniav_free(format_data.formats_list);       // Free the list we allocated
    format_data.formats_list = NULL;
    goto format_enum_cleanup;
  }
  pw_node_add_listener(node_proxy, &node_listener_local, &node_info_events,
                       &format_data);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW: Running loop for node info (node %u).", node_id);
  pw_main_loop_run(loop);

  if (format_data.result == MINIAV_SUCCESS) {
    if (*count_out > 0) {
      *formats_out = format_data.formats_list;
      MiniAVVideoInfo *final_list =
          miniav_realloc(*formats_out, (*count_out) * sizeof(MiniAVVideoInfo));
      if (final_list)
        *formats_out = final_list;
    } else {
      miniav_free(format_data.formats_list);
      *formats_out = NULL;
    }
  } else {
    miniav_free(format_data.formats_list);
    *formats_out = NULL;
    *count_out = 0;
    overall_res = format_data.result;
  }

format_enum_cleanup:
  if (node_proxy) {
    spa_hook_remove(&node_listener_local);
    pw_proxy_destroy((struct pw_proxy *)node_proxy);
  }
  if (core)
    pw_core_disconnect(core);
  if (context)
    pw_context_destroy(context);
  if (loop)
    pw_main_loop_destroy(loop);

  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Found %u formats for device %s.",
             *count_out, device_id_str);
  return overall_res;
}

static MiniAVResultCode pw_configure(MiniAVCameraContext *ctx,
                                     const char *device_id_str,
                                     const MiniAVVideoInfo *format) {
  if (!ctx || !ctx->platform_ctx || !device_id_str || !format)
    return MINIAV_ERROR_INVALID_ARG;
  PipeWirePlatformContext *pw_ctx =
      (PipeWirePlatformContext *)ctx->platform_ctx;

  if (pw_ctx->is_streaming) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Cannot configure while streaming.");
    return MINIAV_ERROR_INVALID_OPERATION;
  }

  uint32_t node_id = (uint32_t)atoi(device_id_str);
  if (node_id == 0 && strcmp(device_id_str, "0") != 0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Invalid device_id string for configure: %s", device_id_str);
    return MINIAV_ERROR_INVALID_ARG;
  }

  pw_ctx->target_node_id = node_id;
  pw_ctx->configured_video_format = *format; // Store a copy
  pw_ctx->is_configured = true;

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW: Configured for device ID %u, Format: %s %ux%u @ %u/%u.",
             pw_ctx->target_node_id,
             miniav_pixel_format_to_string_short(format->pixel_format),
             format->width, format->height, format->frame_rate_numerator,
             format->frame_rate_denominator);

  return MINIAV_SUCCESS;
}

static MiniAVResultCode pw_start_capture(MiniAVCameraContext *ctx) {
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;
  PipeWirePlatformContext *pw_ctx =
      (PipeWirePlatformContext *)ctx->platform_ctx;

  if (!pw_ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Context not configured before start_capture.");
    return MINIAV_ERROR_NOT_CONFIGURED;
  }
  if (pw_ctx->is_streaming || pw_ctx->loop_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "PW: Already streaming or loop running.");
    return MINIAV_ERROR_INVALID_OPERATION; // Or SUCCESS if already running is
                                           // ok
  }

  pw_ctx->stream = pw_stream_new(
      pw_ctx->core, "miniav-camera-capture",
      pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                        "Capture", PW_KEY_MEDIA_ROLE, "Camera", NULL));
  if (!pw_ctx->stream) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to create stream.");
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  pw_stream_add_listener(pw_ctx->stream, &pw_ctx->stream_listener,
                         &stream_events, pw_ctx);

  // In pw_start_capture or stream setup
  MiniAVOutputPreference pref =
      pw_ctx->configured_video_format.output_preference;
  uint32_t buffer_types = 0;
  switch (pref) {
  case MINIAV_OUTPUT_PREFERENCE_GPU:
    buffer_types = (1 << SPA_DATA_DmaBuf);
    break;
  case MINIAV_OUTPUT_PREFERENCE_CPU:
    buffer_types = (1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr);
    break;
  default:
    buffer_types =
        (1 << SPA_DATA_DmaBuf) | (1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr);
    break;
  }

  uint8_t params_buffer[1024];
  struct spa_pod_builder b =
      SPA_POD_BUILDER_INIT(params_buffer, sizeof(params_buffer));
  const struct spa_pod *params[2];
  uint32_t n_params = 0;

  // Buffers param
  params[n_params++] = spa_pod_builder_add_object(
      &b, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
      SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 1, 32),
      SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(1), SPA_PARAM_BUFFERS_dataType,
      SPA_POD_CHOICE_FLAGS_Int(buffer_types));

  // Format param (allow any modifier)
  params[n_params++] = spa_pod_builder_add_object(
      &b, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat, SPA_FORMAT_mediaType,
      SPA_POD_Id(SPA_MEDIA_TYPE_video), SPA_FORMAT_mediaSubtype,
      SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw), SPA_FORMAT_VIDEO_format,
      SPA_POD_Id(miniav_pixel_format_to_spa(
          pw_ctx->configured_video_format.pixel_format)),
      SPA_FORMAT_VIDEO_modifier,
      SPA_POD_CHOICE_FLAGS_Long(0), // allow any modifier
      SPA_FORMAT_VIDEO_size,
      SPA_POD_Rectangle(&SPA_RECTANGLE(pw_ctx->configured_video_format.width,
                                       pw_ctx->configured_video_format.height)),
      SPA_FORMAT_VIDEO_framerate,
      SPA_POD_Fraction(&SPA_FRACTION(
          pw_ctx->configured_video_format.frame_rate_numerator,
          pw_ctx->configured_video_format.frame_rate_denominator)),
      0);

  // Connect stream
  if (pw_stream_connect(
          pw_ctx->stream, PW_DIRECTION_INPUT, pw_ctx->target_node_id,
          PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params,
          n_params) < 0) { // No specific params to pass at connect time
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to connect stream to node %u.",
               pw_ctx->target_node_id);
    pw_stream_destroy(pw_ctx->stream);
    pw_ctx->stream = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Start the loop thread
  if (pthread_create(&pw_ctx->loop_thread, NULL, pipewire_loop_thread_func,
                     pw_ctx) != 0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW: Failed to create PipeWire loop thread.");
    pw_stream_destroy(pw_ctx->stream); // Clean up stream
    pw_ctx->stream = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW: Capture started (stream connecting, loop thread running).");
  // is_streaming will be set true by the stream state callback when it
  // reaches PAUSED/STREAMING
  return MINIAV_SUCCESS;
}

MiniAVResultCode pw_stop_capture(MiniAVCameraContext *ctx) {
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;
  PipeWirePlatformContext *pw_ctx =
      (PipeWirePlatformContext *)ctx->platform_ctx;

  if (!pw_ctx->loop_running &&
      !pw_ctx->is_streaming) { // Check both as loop might run without stream
                               // being fully up
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: Capture not running or loop already stopped.");
    return MINIAV_SUCCESS;
  }
  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Stopping capture.");

  pw_ctx->is_streaming = false; // Signal callbacks to stop processing further

  if (pw_ctx->stream) {
    pw_stream_set_active(pw_ctx->stream, false);
    pw_stream_disconnect(pw_ctx->stream);
    // Destruction of stream should happen after loop thread joins, or here if
    // safe
  }

  if (pw_ctx->loop_running && pw_ctx->loop) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Signaling PipeWire loop to quit.");
    if (pw_ctx->wakeup_pipe[1] != -1) {
      if (write(pw_ctx->wakeup_pipe[1], "q", 1) == -1 && errno != EAGAIN) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW: Failed to write to wakeup pipe: %s", strerror(errno));
      }
    } else { // Fallback if pipe is not working
      pw_main_loop_quit(pw_ctx->loop);
    }
  }

  if (pw_ctx->loop_thread) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Joining PipeWire loop thread.");
    pthread_join(pw_ctx->loop_thread, NULL);
    pw_ctx->loop_thread = 0; // Mark as joined
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: PipeWire loop thread joined.");
  }

  // Clean up stream post-loop
  if (pw_ctx->stream) {
    spa_hook_remove(&pw_ctx->stream_listener);
    pw_stream_destroy(pw_ctx->stream);
    pw_ctx->stream = NULL;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW: Capture stopped.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode pw_release_buffer(MiniAVCameraContext *ctx,
                                          void *internal_handle_ptr) {
  MINIAV_UNUSED(ctx);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Camera: release_buffer called with internal_handle_ptr=%p",
             internal_handle_ptr);

  if (!internal_handle_ptr) {
    miniav_log(
        MINIAV_LOG_LEVEL_DEBUG,
        "PW Camera: release_buffer called with NULL internal_handle_ptr.");
    return MINIAV_SUCCESS;
  }

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)internal_handle_ptr;

  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "PW Camera: payload ptr=%p, handle_type=%d, native_resource_ptr=%p",
      payload, payload->handle_type, payload->native_resource_ptr);

  if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA) {
    PipeWireFrameReleasePayload *frame_payload =
        (PipeWireFrameReleasePayload *)payload->native_resource_ptr;
    if (frame_payload) {
      if (frame_payload->type == MINIAV_OUTPUT_PREFERENCE_CPU) {
        if (frame_payload->cpu.cpu_ptr) {
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "PW Camera: Freeing CPU buffer from DMABUF/MemFd copy.");
          miniav_free(frame_payload->cpu.cpu_ptr);
          frame_payload->cpu.cpu_ptr = NULL;
        }
        // src_dmabuf_fd is not owned, do not close
      } else if (frame_payload->type == MINIAV_OUTPUT_PREFERENCE_GPU) {
        if (frame_payload->gpu.dup_dmabuf_fd > 0) {
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "PW Camera: Closing duplicated DMABUF FD: %d",
                     frame_payload->gpu.dup_dmabuf_fd);
          if (close(frame_payload->gpu.dup_dmabuf_fd) == -1) {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "PW Camera: Failed to close DMABUF FD %d: %s",
                       frame_payload->gpu.dup_dmabuf_fd, strerror(errno));
          }
          frame_payload->gpu.dup_dmabuf_fd = -1;
        }
      } else {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW Camera: release_buffer: Unknown frame_payload type %d",
                   frame_payload->type);
      }
      miniav_free(frame_payload);
      payload->native_resource_ptr = NULL;
    }
    miniav_free(payload);
    return MINIAV_SUCCESS;
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Camera: release_buffer called for unknown handle_type %d.",
               payload->handle_type);
    miniav_free(payload);
    return MINIAV_SUCCESS;
  }
}

// --- Global Ops Struct ---
const CameraContextInternalOps g_camera_ops_pipewire = {
    .init_platform = pw_init_platform,
    .destroy_platform = pw_destroy_platform,
    .enumerate_devices = pw_enumerate_devices,
    .get_supported_formats = pw_get_supported_formats,
    .configure = pw_configure,
    .start_capture = pw_start_capture,
    .stop_capture = pw_stop_capture,
    .release_buffer = pw_release_buffer,
};

MiniAVResultCode
miniav_camera_context_platform_init_linux_pipewire(MiniAVCameraContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;
  ctx->ops = &g_camera_ops_pipewire;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Assigned Linux PipeWire camera ops.");
  return MINIAV_SUCCESS;
}