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
#define PW_MAX_REPORTED_FORMATS 32
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
  uint32_t node_id;     // Node ID to get formats for
  struct pw_core *core; // Core, needed to get node info
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

  MiniAVVideoInfo temp_formats[PW_MAX_REPORTED_FORMATS];
  uint32_t num_temp_formats;

  int pending_sync_ops; // For sync operations during init/enum

} PipeWirePlatformContext;

// Forward declarations for static functions

static MiniAVResultCode pw_init_platform(MiniAVCameraContext *ctx);
static MiniAVResultCode pw_destroy_platform(MiniAVCameraContext *ctx);
static MiniAVResultCode pw_enumerate_devices(MiniAVDeviceInfo **devices_out,
                                             uint32_t *count_out);
static MiniAVResultCode
pw_get_supported_formats(const char *device_id_str,
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
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: Unknown SPA video format enum: %u (%s)", spa_format,
               spa_debug_type_find_name(spa_type_video_format, spa_format));
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

static void parse_spa_format(const struct spa_pod *format_pod,
                             MiniAVVideoInfo *info,
                             PipeWirePlatformContext *pw_ctx) {
  // First, try to parse as spa_video_info_raw for common properties like size
  // and framerate
  struct spa_video_info_raw raw_info = {0};
  if (spa_format_video_raw_parse(format_pod, &raw_info) >= 0) {
    info->pixel_format = spa_video_format_to_miniav(
        raw_info.format, format_pod); // Pass the full pod for subtype check
    info->width = raw_info.size.width;
    info->height = raw_info.size.height;
    info->frame_rate_numerator = raw_info.framerate.num;
    info->frame_rate_denominator = raw_info.framerate.denom;
    info->output_preference = MINIAV_OUTPUT_PREFERENCE_CPU; // Default
  } else {
    // If raw_parse fails, it might be a purely encoded format pod that doesn't
    // fit spa_video_info_raw structure well. This part would need more specific
    // parsing based on how PipeWire structures purely encoded format pods. For
    // now, we assume that even for encoded formats, some basic raw_info (like
    // size/framerate) might be present or that the primary format enum is what
    // we check.
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW: Failed to parse SPA video format as raw. Format might be "
               "purely encoded or malformed.");
    // Attempt to get format type directly from the pod if possible (simplified)
    if (spa_pod_is_object_type(format_pod, SPA_TYPE_OBJECT_Format)) {
      uint32_t main_format_enum = SPA_VIDEO_FORMAT_UNKNOWN;
      struct spa_pod_prop *prop;
      struct spa_pod_object *obj = (struct spa_pod_object *)format_pod;

      SPA_POD_OBJECT_FOREACH(obj, prop) {
        if (prop->key ==
            SPA_FORMAT_VIDEO_format) { // This is the enum spa_video_format
          spa_pod_get_id(&prop->value,
                         &main_format_enum); // Pass address of prop->value
          break;
        }
      }
      info->pixel_format =
          spa_video_format_to_miniav(main_format_enum, format_pod);
      // Width, height, framerate might need to be extracted from other
      // properties if spa_video_info_raw_parse failed. This is common for
      // encoded types. For example, SPA_FORMAT_VIDEO_size,
      // SPA_FORMAT_VIDEO_framerate
      SPA_POD_OBJECT_FOREACH(obj, prop) {
        if (prop->key == SPA_FORMAT_VIDEO_size) {
          spa_pod_get_rectangle(&prop->value, // Pass address of prop->value
                                &raw_info.size);
          info->width = raw_info.size.width;
          info->height = raw_info.size.height;
        } else if (prop->key == SPA_FORMAT_VIDEO_framerate) {
          if (spa_pod_is_fraction(&prop->value)) { // Check the type
            if (spa_pod_get_fraction(&prop->value, &raw_info.framerate) ==
                0) { // Pass address of prop->value
              info->frame_rate_numerator = raw_info.framerate.num;
              info->frame_rate_denominator =
                  raw_info.framerate.denom; // Corrected this previously
            } else {
              miniav_log(
                  MINIAV_LOG_LEVEL_WARN,
                  "PW: Failed to parse SPA_FORMAT_VIDEO_framerate pod value.");
            }
          } else {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "PW: SPA_FORMAT_VIDEO_framerate pod value is not of "
                       "SPA_TYPE_Fraction.");
          }
        }
      }
      info->output_preference = MINIAV_OUTPUT_PREFERENCE_CPU; // Default
    } else {
      info->pixel_format = MINIAV_PIXEL_FORMAT_UNKNOWN;
    }
  }

  // If pixel_format is still unknown or if it's a generic ENCODED type without
  // MJPEG subtype identified yet, and you expect MJPEG, this is where you might
  // log a more specific warning or error.
  if (info->pixel_format == MINIAV_PIXEL_FORMAT_UNKNOWN) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW: Could not determine MiniAV pixel format from SPA pod.");
  }
}

// --- Stream Callbacks ---
static void on_stream_process(void *userdata) {
  PipeWirePlatformContext *pw_ctx = (PipeWirePlatformContext *)userdata;
  struct pw_buffer *pw_buf;
  MiniAVBuffer *miniav_buf = NULL;

  if (!pw_ctx || !pw_ctx->parent_ctx || !pw_ctx->parent_ctx->app_callback) {
    return;
  }

  pw_buf = pw_stream_dequeue_buffer(pw_ctx->stream);
  if (!pw_buf) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "PW: No buffer dequeued from stream.");
    return;
  }

  miniav_buf = (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
  if (!miniav_buf) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW: Failed to allocate MiniAVBuffer.");
    // Re-queue buffer if we can't process it
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }

  miniav_buf->type = MINIAV_BUFFER_TYPE_VIDEO;
  miniav_buf->timestamp_us =
      pw_buf
          ->time; // pw_buf->time is usually in nanoseconds, convert if needed
                  // Or use pw_buf->time / 1000 if it's nsec.
                  // PipeWire's time might be relative or absolute based on
                  // stream. For simplicity, directly assigning. Check PW docs.

  struct spa_buffer *spa_buf = pw_buf->buffer;
  struct spa_data *d =
      &spa_buf->datas[0]; // Assuming single plane for simplicity first

  miniav_buf->data.video.info.width = pw_ctx->configured_video_format.width;
  miniav_buf->data.video.info.height = pw_ctx->configured_video_format.height;
  miniav_buf->data.video.info.pixel_format = pw_ctx->configured_video_format.pixel_format;

  // TODO: Handle multi-planar formats (NV12, I420) correctly by inspecting
  // spa_buf->n_datas and spa_video_info for plane strides and offsets. For now,
  // a simplified single-plane copy:
  if (d->data && d->chunk && d->chunk->size > 0) {
    miniav_buf->data_size_bytes = d->chunk->size;
    miniav_buf->data.video.planes[0] = miniav_malloc(d->chunk->size);
    if (miniav_buf->data.video.planes[0]) {
      memcpy(miniav_buf->data.video.planes[0], d->data, d->chunk->size);
      miniav_buf->data.video.stride_bytes[0] = d->chunk->stride;
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW: Failed to allocate memory for frame data.");
      miniav_free(miniav_buf);
      pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
      return;
    }
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW: Received buffer with no data or zero size.");
    miniav_free(miniav_buf);
    pw_stream_queue_buffer(pw_ctx->stream, pw_buf);
    return;
  }

  miniav_buf->content_type =
      MINIAV_BUFFER_CONTENT_TYPE_CPU; // Assuming CPU buffer for now
  miniav_buf->user_data = pw_ctx->parent_ctx->app_callback_user_data;

  // Create internal payload if needed for miniav_buffer_release
  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
  if (payload) {
    payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA; // Generic
    payload->context_owner = pw_ctx->parent_ctx;
    payload->native_resource_ptr =
        NULL; // Not directly passing pw_buffer, as we copy
    payload->parent_miniav_buffer_ptr = miniav_buf;
    miniav_buf->internal_handle = payload;
  }

  pw_ctx->parent_ctx->app_callback(miniav_buf,
                                   pw_ctx->parent_ctx->app_callback_user_data);

  // Since we copied the data, we can immediately release the MiniAVBuffer's
  // data if the app_callback doesn't take ownership or if miniav_buffer_release
  // is called by user. For now, assume miniav_buffer_release will handle
  // freeing miniav_buf->data.video.planes[0] and miniav_buf itself.

  pw_stream_queue_buffer(pw_ctx->stream, pw_buf); // Return buffer to PipeWire
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
      uint32_t spa_format =
          miniav_pixel_format_to_spa(pw_ctx->configured_video_format.pixel_format);

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
  // configured_video_format and potentially update pw_ctx->configured_video_format if the
  // device chose a compatible alternative. For now, we assume the device
  // accepted our request or something close.

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
        // TODO: Determine if it's the default device. PipeWire doesn't have a
        // direct "isDefault" flag like miniaudio. This might require heuristics
        // or checking specific properties. For now, mark none as default.
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

static void process_node_params_for_formats(PipeWireFormatEnumData *format_data,
                                            const struct pw_node_info *info) {
  if (!info)
    return;

  for (uint32_t i = 0; i < info->n_params; i++) {
    if (info->params[i].id == SPA_PARAM_EnumFormat) {
      // This is simplified. We need to fetch the actual param values.
      // This requires using pw_node_enum_params and then parsing the pods.
      // For now, this is a placeholder for the complex logic.
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW: Node has SPA_PARAM_EnumFormat. Need to fetch and parse.");

      // Example of how one might start fetching (very simplified):
      // This part is highly complex due to async nature and pod parsing.
      // A real implementation would involve pw_node_enum_params,
      // handling the result (which is another event), and then parsing the
      // pods.

      // For now, let's add some common hardcoded formats as a placeholder
      // until proper SPA_PARAM_EnumFormat parsing is implemented.
      if (*format_data->formats_count < format_data->allocated_formats) {
        format_data->formats_list[*format_data->formats_count] =
            (MiniAVVideoInfo){.width = 640,
                                    .height = 480,
                                    .pixel_format = MINIAV_PIXEL_FORMAT_YUY2,
                                    .frame_rate_numerator = 30,
                                    .frame_rate_denominator = 1,
                                    .output_preference =
                                        MINIAV_OUTPUT_PREFERENCE_CPU};
        (*format_data->formats_count)++;
      }
      if (*format_data->formats_count < format_data->allocated_formats) {
        format_data->formats_list[*format_data->formats_count] =
            (MiniAVVideoInfo){.width = 1280,
                                    .height = 720,
                                    .pixel_format = MINIAV_PIXEL_FORMAT_MJPEG,
                                    .frame_rate_numerator = 30,
                                    .frame_rate_denominator = 1,
                                    .output_preference =
                                        MINIAV_OUTPUT_PREFERENCE_CPU};
        (*format_data->formats_count)++;
      }
    }
  }
}

static void
on_node_info(void *data,
             const struct pw_node_info *info) { // Changed to pw_node_info
  PipeWireFormatEnumData *format_data = (PipeWireFormatEnumData *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW: Received node info for format enumeration (node %u).",
             format_data->node_id);

  // Access the spa_node_info if needed: const struct spa_node_info *spa_info =
  // info ? info->info : NULL; However, pw_node_info itself contains the
  // n_params and params array directly.
  if (info) { // Check if info is not NULL
    process_node_params_for_formats(format_data, info); // Pass pw_node_info
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW: on_node_info called with NULL info.");
  }

  format_data->result = MINIAV_SUCCESS;
  if (format_data->loop) {
    pw_main_loop_quit(format_data->loop);
  }
}

static const struct pw_node_events node_info_events = {
    PW_VERSION_NODE_EVENTS, .info = on_node_info,
    // .param = on_node_param, // You would add this for pw_node_enum_params
};

static MiniAVResultCode
pw_get_supported_formats(const char *device_id_str,
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

  // The on_node_info callback will populate formats and quit the loop.
  // A more robust implementation would use pw_node_enum_params.
  // For SPA_PARAM_EnumFormat, you'd call pw_node_enum_params.
  // The result comes via pw_node_event_param.
  // This is a placeholder for that complex logic.
  // For now, on_node_info will add some dummy formats and quit.
  // To trigger on_node_info, the proxy needs to sync.
  // pw_proxy_sync() or similar might be needed, or it might be triggered by
  // binding. Let's assume binding + loop run is enough for on_node_info to be
  // called once. If not, a sync mechanism after binding node_proxy would be
  // needed.

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW: Running loop for node info (node %u).", node_id);
  pw_main_loop_run(loop); // Runs until on_node_info calls quit

  if (format_data.result == MINIAV_SUCCESS) {
    if (*count_out > 0) {
      *formats_out = format_data.formats_list;
      MiniAVVideoInfo *final_list = miniav_realloc(
          *formats_out, (*count_out) * sizeof(MiniAVVideoInfo));
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

  // Connect stream
  if (pw_stream_connect(
          pw_ctx->stream,
          PW_DIRECTION_INPUT,     // We are a sink for camera data
          pw_ctx->target_node_id, // Target camera node
          PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, // Flags
          NULL, 0) < 0) { // No specific params to pass at connect time
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

static MiniAVResultCode
pw_release_buffer(MiniAVCameraContext *ctx,
                  void *native_buffer_payload_resource_ptr) {
  // If MiniAVBuffer copied data from pw_buffer, then the original pw_buffer
  // was already returned to PipeWire via pw_stream_queue_buffer in
  // on_stream_process. This function would then be responsible for freeing
  // the MiniAV-side payload struct and any data *copied* into the
  // MiniAVBuffer, which is typically handled by miniav_buffer_release itself.
  // If native_buffer_payload_resource_ptr was, for example, the
  // MiniAVNativeBufferInternalPayload, we'd free that here.
  MINIAV_UNUSED(ctx);

  if (native_buffer_payload_resource_ptr) {
    // Assuming native_buffer_payload_resource_ptr is the
    // MiniAVNativeBufferInternalPayload* that was stored in
    // MiniAVBuffer->internal_handle. The actual MiniAVBuffer and its copied
    // data planes are freed by the caller of this (which is
    // miniav_buffer_release). This function's job is to release any *native*
    // resource tied to the payload, but in our current copy-based approach,
    // there isn't one directly held by the payload. So, we just free the
    // payload struct itself.
    MiniAVNativeBufferInternalPayload *payload =
        (MiniAVNativeBufferInternalPayload *)native_buffer_payload_resource_ptr;
    // miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW: Releasing internal payload
    // %p.", payload);
    miniav_free(payload);
  }
  return MINIAV_SUCCESS;
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