#define _GNU_SOURCE
#include "screen_context_linux_pipewire.h"

#ifdef __linux__ // Guard for Linux-specific code

#include "../../../include/miniav_buffer.h" // For MiniAVBuffer
#include "../../../include/miniav_types.h" // Ensure this is included for all types
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h"  // For miniav_get_time_us
#include "../../common/miniav_utils.h" // For miniav_calloc, miniav_free, etc.

#include <pipewire/pipewire.h>
#include <spa/buffer/meta.h> // For SPA_META_Header
#include <spa/debug/types.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/format-utils.h> // For spa_format_parse
#include <spa/param/props.h>        // For SPA_PROP_ требуют and SPA_PROPS_flags
#include <spa/param/video/format-utils.h>
#include <spa/param/video/type-info.h> // For spa_type_video_format
#include <spa/pod/builder.h>
#include <spa/utils/defs.h>   // For SPA_FRACTION_INIT
#include <spa/utils/result.h> // For spa_strerror

#include <errno.h>
#include <fcntl.h>    // For O_CLOEXEC, F_DUPFD_CLOEXEC
#include <gio/gio.h>  // For D-Bus (GDBus)
#include <glib.h>     // For GVariant, GError, etc.
#include <inttypes.h> // For PRIu64
#include <string.h>   // For memset, strcmp
#include <sys/mman.h> // For shm, if using DMABUF or similar
#include <unistd.h>   // For pipe, read, write, close, getpid

// Portal D-Bus definitions
#define XDP_BUS_NAME "org.freedesktop.portal.Desktop"
#define XDP_OBJECT_PATH "/org/freedesktop/portal/desktop"
#define XDP_IFACE_SCREENCAST "org.freedesktop.portal.ScreenCast"
#define XDP_IFACE_REQUEST "org.freedesktop.portal.Request"
#define XDP_IFACE_SESSION "org.freedesktop.portal.Session"

// --- Helper to convert formats (Simplified) ---
static enum spa_video_format
miniav_video_format_to_spa(MiniAVPixelFormat pixel_fmt) {
  switch (pixel_fmt) {
  case MINIAV_PIXEL_FORMAT_BGRA32:
    return SPA_VIDEO_FORMAT_BGRA;
  case MINIAV_PIXEL_FORMAT_RGBA32:
    return SPA_VIDEO_FORMAT_RGBA;
  case MINIAV_PIXEL_FORMAT_I420:
    return SPA_VIDEO_FORMAT_I420;
  // Add more mappings
  default:
    return SPA_VIDEO_FORMAT_UNKNOWN;
  }
}

// Remove the conflicting definition of spa_video_format_to_miniav that returns
// MiniAVVideoInfo

static MiniAVPixelFormat // Corrected return type
spa_video_format_to_miniav(enum spa_video_format spa_fmt) {
  switch (spa_fmt) {
  case SPA_VIDEO_FORMAT_BGRA:
    return MINIAV_PIXEL_FORMAT_BGRA32; // Corrected enum
  case SPA_VIDEO_FORMAT_RGBA:
    return MINIAV_PIXEL_FORMAT_RGBA32; // Corrected enum
  case SPA_VIDEO_FORMAT_I420:
    return MINIAV_PIXEL_FORMAT_I420; // Corrected enum
  // Add more mappings
  default:
    return MINIAV_PIXEL_FORMAT_UNKNOWN; // Corrected enum
  }
}

static enum spa_audio_format
miniav_audio_format_to_spa_audio(MiniAVAudioFormat fmt) {
  switch (fmt) {
  case MINIAV_AUDIO_FORMAT_S16:
    return SPA_AUDIO_FORMAT_S16_LE; // Assuming Little Endian
  case MINIAV_AUDIO_FORMAT_S32:
    return SPA_AUDIO_FORMAT_S32_LE;
  case MINIAV_AUDIO_FORMAT_F32:
    return SPA_AUDIO_FORMAT_F32_LE;
  default:
    return SPA_AUDIO_FORMAT_UNKNOWN;
  }
}

// This function was missing from the previous compiler output but was in your
// prior code.
static MiniAVAudioFormat
spa_audio_format_to_miniav_audio(enum spa_audio_format spa_fmt) {
  switch (spa_fmt) {
  case SPA_AUDIO_FORMAT_S16_LE:
  case SPA_AUDIO_FORMAT_S16_BE: // Consider endianness if needed
    return MINIAV_AUDIO_FORMAT_S16;
  case SPA_AUDIO_FORMAT_S32_LE:
  case SPA_AUDIO_FORMAT_S32_BE:
    return MINIAV_AUDIO_FORMAT_S32;
  case SPA_AUDIO_FORMAT_F32_LE:
  case SPA_AUDIO_FORMAT_F32_BE:
    return MINIAV_AUDIO_FORMAT_F32;
  // Add more mappings
  default:
    return MINIAV_AUDIO_FORMAT_UNKNOWN;
  }
}

static uint32_t get_miniav_pixel_format_planes(MiniAVPixelFormat pixel_fmt) {
  switch (pixel_fmt) {
  case MINIAV_PIXEL_FORMAT_I420:
    // case MINIAV_PIXEL_FORMAT_YV12: // If you support it
    return 3;
  case MINIAV_PIXEL_FORMAT_NV12:
  case MINIAV_PIXEL_FORMAT_NV21:
    return 2;
  case MINIAV_PIXEL_FORMAT_YUY2:
  case MINIAV_PIXEL_FORMAT_UYVY:
  case MINIAV_PIXEL_FORMAT_RGB24:
  case MINIAV_PIXEL_FORMAT_BGR24:
  case MINIAV_PIXEL_FORMAT_RGBA32:
  case MINIAV_PIXEL_FORMAT_BGRA32:
  case MINIAV_PIXEL_FORMAT_ARGB32:
  case MINIAV_PIXEL_FORMAT_ABGR32:
  case MINIAV_PIXEL_FORMAT_MJPEG: // MJPEG is single buffer/plane in this
                                  // context
    return 1;
  case MINIAV_PIXEL_FORMAT_UNKNOWN:
  default:
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Unknown pixel format %d, assuming 0 planes.",
               pixel_fmt);
    return 0;
  }
}

// --- Forward Declarations for Static Functions ---
static void *pw_screen_loop_thread_func(void *arg);

// PipeWire Core Events
static void on_pw_core_info(void *data, const struct pw_core_info *info);
static void on_pw_core_done(void *data, uint32_t id, int seq);
static void on_pw_core_error(void *data, uint32_t id, int seq, int res,
                             const char *message);

// PipeWire Stream Events (Video)
static void on_video_stream_state_changed(void *data, enum pw_stream_state old,
                                          enum pw_stream_state new_state,
                                          const char *error);
static void on_video_stream_param_changed(void *data, uint32_t id,
                                          const struct spa_pod *param);
static void on_video_stream_process(void *data);
static void on_video_stream_add_buffer(void *data, struct pw_buffer *buffer);
static void on_video_stream_remove_buffer(void *data, struct pw_buffer *buffer);

// PipeWire Stream Events (Audio) - if separate audio stream
static void on_audio_stream_state_changed(void *data, enum pw_stream_state old,
                                          enum pw_stream_state new_state,
                                          const char *error);
static void on_audio_stream_param_changed(void *data, uint32_t id,
                                          const struct spa_pod *param);
static void on_audio_stream_process(void *data);

// --- Forward Declarations for D-Bus callbacks and setup ---
static void
pw_screen_setup_pipewire_streams(PipeWireScreenPlatformContext *pctx);
static void on_portal_create_session_dbus_response(GObject *source_object,
                                                   GAsyncResult *res,
                                                   gpointer user_data);
static void
on_portal_create_session_response(PipeWireScreenPlatformContext *pctx,
                                  GVariant *results);
static void on_portal_request_response(GObject *source_object,
                                       GAsyncResult *res, gpointer user_data);
static void on_portal_request_signal_response(
    GDBusConnection *connection, const gchar *sender_name,
    const gchar *object_path, const gchar *interface_name,
    const gchar *signal_name, GVariant *parameters, gpointer user_data);
static void
on_portal_select_sources_response(PipeWireScreenPlatformContext *pctx,
                                  GVariant *results);
static void on_portal_start_response(PipeWireScreenPlatformContext *pctx,
                                     GVariant *results);
static void on_portal_session_closed(GDBusConnection *connection,
                                     const gchar *sender_name,
                                     const gchar *object_path,
                                     const gchar *interface_name,
                                     const gchar *signal_name,
                                     GVariant *parameters, gpointer user_data);

// Helper to generate a unique token
static char *generate_token(const char *prefix) {
  // GLib provides g_random_int() which is good enough for a handle token.
  return g_strdup_printf("%s_%d_%u", prefix, getpid(), g_random_int());
}

// --- Ops Implementation ---

static MiniAVResultCode
pw_screen_init_platform(struct MiniAVScreenContext *ctx) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Initializing platform context.");
  GError *error = NULL;

  pctx->cancellable = g_cancellable_new();

  pctx->dbus_conn =
      g_bus_get_sync(G_BUS_TYPE_SESSION, pctx->cancellable, &error);
  if (error) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Failed to connect to D-Bus: %s", error->message);
    g_error_free(error);
    g_object_unref(pctx->cancellable);
    pctx->cancellable = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Connected to D-Bus session bus.");

  pctx->loop = pw_main_loop_new(NULL);
  if (!pctx->loop) {
    g_object_unref(pctx->dbus_conn);
    g_object_unref(pctx->cancellable);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  pctx->context = pw_context_new(pw_main_loop_get_loop(pctx->loop), NULL, 0);
  if (!pctx->context) {
    pw_main_loop_destroy(pctx->loop);
    g_object_unref(pctx->dbus_conn);
    g_object_unref(pctx->cancellable);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  pctx->core = pw_context_connect(pctx->context, NULL, 0);
  if (!pctx->core) {
    pw_context_destroy(pctx->context);
    pw_main_loop_destroy(pctx->loop);
    g_object_unref(pctx->dbus_conn);
    g_object_unref(pctx->cancellable);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  static const struct pw_core_events core_events = {
      PW_VERSION_CORE_EVENTS,
      .info = on_pw_core_info,
      .done = on_pw_core_done,
      .error = on_pw_core_error,
  };
  pw_core_add_listener(pctx->core, &pctx->core_listener, &core_events, pctx);

  // Initialize DMABUF FD array
  for (int i = 0; i < PW_SCREEN_MAX_BUFFERS; ++i) {
    pctx->video_dmabuf_fds[i] = -1;
  }

  if (pipe2(pctx->wakeup_pipe, O_CLOEXEC | O_NONBLOCK) == -1) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Failed to create wakeup pipe: %s", strerror(errno));
    pw_core_disconnect(pctx->core);
    pw_context_destroy(pctx->context);
    pw_main_loop_destroy(pctx->loop);
    g_object_unref(pctx->dbus_conn);
    g_object_unref(pctx->cancellable);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  pctx->video_node_id = PW_ID_ANY;
  pctx->audio_node_id = PW_ID_ANY;
  pctx->core_connected = false;
  pctx->portal_session_handle_str = NULL;
  pctx->portal_request_handle_str = NULL;
  pctx->app_callback_pending = NULL;
  pctx->app_callback_user_data_pending = NULL;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Platform context initialized. "
                                     "Waiting for core connection...");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_destroy_platform(struct MiniAVScreenContext *ctx) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  if (!pctx)
    return MINIAV_SUCCESS;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Destroying platform context.");

  if (pctx->cancellable) {
    g_cancellable_cancel(pctx->cancellable); // Cancel any pending D-Bus calls
    g_object_unref(pctx->cancellable);
    pctx->cancellable = NULL;
  }

  // Ensure capture is stopped (also handles loop thread join)
  // Call a simplified stop if not already done by MiniAV_Screen_StopCapture
  if (pctx->video_stream)
    pw_stream_set_active(pctx->video_stream, false);
  if (pctx->audio_stream)
    pw_stream_set_active(pctx->audio_stream, false);

  if (pctx->loop_running && pctx->wakeup_pipe[1] != -1) {
    char buf = 'q';
    ssize_t written = write(pctx->wakeup_pipe[1], &buf, 1);
    if (written == -1 && errno != EAGAIN) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Failed to write to wakeup pipe in destroy: %s",
                 strerror(errno));
    }
  }
  if (pctx->loop_thread) {
    pthread_join(pctx->loop_thread, NULL);
    pctx->loop_thread = 0;
  }
  pctx->loop_running = false;

  // Close portal session if active
  if (pctx->portal_session_handle_str && pctx->dbus_conn) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Closing portal session: %s",
               pctx->portal_session_handle_str);
    GError *error = NULL;
    // Use a new cancellable for this synchronous call or NULL
    GCancellable *close_cancellable = g_cancellable_new();
    g_dbus_connection_call_sync(
        pctx->dbus_conn, XDP_BUS_NAME,
        pctx->portal_session_handle_str, // Session object path
        XDP_IFACE_SESSION, "Close",
        NULL, // parameters
        NULL, // reply_type
        G_DBUS_CALL_FLAGS_NONE,
        5000, // timeout 5s
        close_cancellable, &error);
    if (error) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Failed to close portal session %s: %s",
                 pctx->portal_session_handle_str, error->message);
      g_error_free(error);
    }
    g_object_unref(close_cancellable);
    g_free(pctx->portal_session_handle_str);
    pctx->portal_session_handle_str = NULL;
  }
  g_free(pctx->portal_request_handle_str);
  pctx->portal_request_handle_str = NULL;

  if (pctx->video_stream) {
    pw_stream_destroy(pctx->video_stream);
    pctx->video_stream = NULL;
  }
  if (pctx->audio_stream) {
    pw_stream_destroy(pctx->audio_stream);
    pctx->audio_stream = NULL;
  }

  if (pctx->core) {
    pw_core_disconnect(pctx->core);
    pctx->core = NULL;
  }
  if (pctx->context) {
    pw_context_destroy(pctx->context);
    pctx->context = NULL;
  }
  if (pctx->loop) {
    pw_main_loop_destroy(pctx->loop);
    pctx->loop = NULL;
  }

  if (pctx->wakeup_pipe[0] != -1)
    close(pctx->wakeup_pipe[0]);
  if (pctx->wakeup_pipe[1] != -1)
    close(pctx->wakeup_pipe[1]);
  pctx->wakeup_pipe[0] = pctx->wakeup_pipe[1] = -1;

  for (int i = 0; i < PW_SCREEN_MAX_BUFFERS; ++i) {
    if (pctx->video_dmabuf_fds[i] != -1) {
      // Original FDs are owned by PipeWire, not closed here.
      // Duplicated FDs are closed by release_buffer.
      pctx->video_dmabuf_fds[i] = -1;
    }
  }

  if (pctx->dbus_conn) {
    g_object_unref(pctx->dbus_conn);
    pctx->dbus_conn = NULL;
  }

  miniav_free(pctx);
  ctx->platform_ctx = NULL;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_enumerate_displays(MiniAVDeviceInfo **displays_out,
                             uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: EnumerateDisplays called.");
  // This still requires portal interaction (e.g. using a temporary session
  // with SelectSources and parsing the results without actually starting).
  // For now, returning a placeholder.
  *displays_out =
      (MiniAVDeviceInfo *)miniav_calloc(1, sizeof(MiniAVDeviceInfo));
  if (!*displays_out)
    return MINIAV_ERROR_OUT_OF_MEMORY;

  strncpy((*displays_out)[0].device_id, "portal_display", // Generic ID
          MINIAV_DEVICE_ID_MAX_LEN - 1);
  strncpy((*displays_out)[0].name, "Screen (select via Portal)",
          MINIAV_DEVICE_NAME_MAX_LEN - 1);
  (*displays_out)[0].is_default = true;
  *count_out = 1;

  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "PW Screen: EnumerateDisplays is simplified. Full enumeration "
             "requires portal interaction.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_enumerate_windows(MiniAVDeviceInfo **windows_out,
                            uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: EnumerateWindows called.");
  // Similar to displays, portal interaction is key.
  *windows_out = (MiniAVDeviceInfo *)miniav_calloc(1, sizeof(MiniAVDeviceInfo));
  if (!*windows_out)
    return MINIAV_ERROR_OUT_OF_MEMORY;

  strncpy((*windows_out)[0].device_id, "portal_window", // Generic ID
          MINIAV_DEVICE_ID_MAX_LEN - 1);
  strncpy((*windows_out)[0].name, "Window/Application (select via Portal)",
          MINIAV_DEVICE_NAME_MAX_LEN - 1);
  *count_out = 1;

  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "PW Screen: EnumerateWindows is simplified. Full enumeration "
             "requires portal interaction.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_configure_display(struct MiniAVScreenContext *ctx,
                            const char *display_id,
                            const MiniAVVideoInfo *video_format) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: ConfigureDisplay for ID: %s",
             display_id ? display_id : "any_portal_selected");

  // display_id is not directly used with portal's SelectSources dialog,
  // but could be used if we had a way to pre-select.
  // For now, target_id_str is mostly for logging or internal state.
  if (display_id) {
    strncpy(pctx->target_id_str, display_id, sizeof(pctx->target_id_str) - 1);
  } else {
    strncpy(pctx->target_id_str, "portal_selected_display",
            sizeof(pctx->target_id_str) - 1);
  }
  pctx->requested_video_format = *video_format;
  pctx->capture_type = MINIAV_CAPTURE_TYPE_DISPLAY;
  pctx->audio_requested_by_user = ctx->capture_audio_requested;
  if (ctx->capture_audio_requested) {
    pctx->requested_audio_format = ctx->configured_audio_format;
  }

  ctx->is_configured = true;
  ctx->configured_video_format = *video_format;
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_configure_window(struct MiniAVScreenContext *ctx,
                           const char *window_id,
                           const MiniAVVideoInfo *format) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: ConfigureWindow for ID: %s",
             window_id ? window_id : "any_portal_selected");

  if (window_id) {
    strncpy(pctx->target_id_str, window_id, sizeof(pctx->target_id_str) - 1);
  } else {
    strncpy(pctx->target_id_str, "portal_selected_window",
            sizeof(pctx->target_id_str) - 1);
  }
  pctx->requested_video_format = *format;
  pctx->capture_type = MINIAV_CAPTURE_TYPE_WINDOW;
  pctx->audio_requested_by_user = ctx->capture_audio_requested;
  if (ctx->capture_audio_requested) {
    pctx->requested_audio_format = ctx->configured_audio_format;
  }

  ctx->is_configured = true;
  ctx->configured_video_format = *format;
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_configure_region(struct MiniAVScreenContext *ctx,
                           const char *target_id, int x, int y, int width,
                           int height, const MiniAVVideoInfo *format) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: ConfigureRegion for ID: %s, Rect: %d,%d %dx%d",
             target_id ? target_id : "any_portal_selected", x, y, width,
             height);

  if (target_id) {
    strncpy(pctx->target_id_str, target_id, sizeof(pctx->target_id_str) - 1);
  } else {
    strncpy(pctx->target_id_str, "portal_selected_region_base",
            sizeof(pctx->target_id_str) - 1);
  }
  pctx->requested_video_format = *format;
  pctx->capture_type =
      MINIAV_CAPTURE_TYPE_REGION; // Portal might not support region directly;
                                  // client-side crop may be needed.
  pctx->audio_requested_by_user = ctx->capture_audio_requested;
  if (ctx->capture_audio_requested) {
    pctx->requested_audio_format = ctx->configured_audio_format;
  }
  pctx->region_x = x;
  pctx->region_y = y;
  pctx->region_width = width;
  pctx->region_height = height;

  miniav_log(MINIAV_LOG_LEVEL_WARN, "PW Screen: Region capture support depends "
                                    "on portal/source capabilities. "
                                    "Client-side cropping might be necessary.");

  ctx->is_configured = true;
  ctx->configured_video_format = *format;
  return MINIAV_SUCCESS;
}

static void on_portal_start_response(PipeWireScreenPlatformContext *pctx,
                                     GVariant *results) {
  if (!results) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Portal Start method failed (no results variant).");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    return;
  }

  GVariant *streams_array_variant = NULL;

  // The 'results' GVariant is a dictionary. We need to find the 'streams' key.
  // Corrected g_variant_lookup format string
  if (!g_variant_lookup(results, "streams",
                        "a(ua{sv})", // Removed '@' which is for maybe types
                        &streams_array_variant)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: 'streams' key (type a(ua{sv})) not found in portal "
               "Start response dict.");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    if (streams_array_variant)
      g_variant_unref(streams_array_variant);
    return;
  }

  if (!streams_array_variant) { // Should not happen if lookup succeeded, but
                                // defensive
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: 'streams' variant is NULL after lookup in portal "
               "Start response.");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    return;
  }

  GVariantIter stream_iter;
  guint32 stream_node_id_temp;
  GVariant *stream_props_dict_variant;

  g_variant_iter_init(&stream_iter, streams_array_variant);
  bool video_node_found = false;
  // bool audio_node_found = false; // If expecting separate audio stream

  // Iterate through the streams array
  while (g_variant_iter_next(&stream_iter, "(u@a{sv})", &stream_node_id_temp,
                             &stream_props_dict_variant)) {
    // For simplicity, assume the first stream is video.
    // A robust implementation would check properties in
    // stream_props_dict_variant (e.g., for a "purpose" or "type" key).
    if (!video_node_found) {
      pctx->video_node_id = stream_node_id_temp;
      miniav_log(MINIAV_LOG_LEVEL_INFO,
                 "PW Screen: Portal provided video stream node ID: %u",
                 pctx->video_node_id);
      video_node_found = true;
    }
    // Example: Check for audio stream if portal provides it separately
    // const char* purpose = NULL;
    // if (g_variant_lookup(stream_props_dict_variant, "purpose", "s",
    // &purpose)) {
    //    if (strcmp(purpose, "audio") == 0 && !audio_node_found) {
    //        pctx->audio_node_id = stream_node_id_temp;
    //        audio_node_found = true;
    //        miniav_log(MINIAV_LOG_LEVEL_INFO, "PW Screen: Portal provided
    //        audio stream node ID: %u", pctx->audio_node_id);
    //    }
    //    g_free((void*)purpose);
    // }
    g_variant_unref(
        stream_props_dict_variant); // Unref the dict for this stream entry
  }
  g_variant_unref(streams_array_variant); // Unref the main streams array

  if (!video_node_found) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: No video stream node ID found in portal response.");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    return;
  }

  if (pctx->audio_requested_by_user &&
      pctx->video_node_id != PW_ID_ANY /*&& !audio_node_found*/) {
    // If portal doesn't explicitly give a separate audio stream,
    // it might be muxed with video or available from the same node.
    // Or, a common pattern is to use a specific well-known node for desktop
    // audio (e.g. @DEFAULT_AUDIO_SINK@.monitor). For now, we'll try to connect
    // to the video node for audio if requested and no separate audio node was
    // found. This is a simplification and might not always work.
    // pctx->audio_node_id = pctx->video_node_id; // Simplification
    miniav_log(
        MINIAV_LOG_LEVEL_WARN,
        "PW Screen: Audio requested. Portal did not explicitly provide a "
        "separate audio stream node. "
        "Audio capture from a specific node is not yet fully implemented here. "
        "Attempting to use a placeholder or relying on PipeWire to pick a "
        "default if audio_node_id remains PW_ID_ANY.");
    // If you know the portal provides audio on the *same* node as video:
    // pctx->audio_node_id = pctx->video_node_id;
    // Or if you need to find a generic desktop audio source:
    // pctx->audio_node_id = find_desktop_audio_node_id(pctx->core); //
    // Hypothetical function For now, if audio_node_id is still PW_ID_ANY,
    // PipeWire might pick a default if stream is connected to PW_ID_ANY.
    // However, screen capture portals usually provide specific nodes.
    // Let's assume for now the portal *should* have provided an audio node if
    // audio was part of the selection. If not, we might have to skip audio or
    // use a fallback. For this example, we'll proceed and let audio stream
    // connection fail if audio_node_id is not valid.
  }

  pw_screen_setup_pipewire_streams(pctx);
}

static void
on_portal_select_sources_response(PipeWireScreenPlatformContext *pctx,
                                  GVariant *results_dict) {
  // results_dict from SelectSources is typically empty on success,
  // the success itself means the user made a selection.
  // If results_dict is NULL here, it means the Response signal indicated
  // failure/cancellation.
  if (!results_dict) {
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "PW Screen: Portal SelectSources failed or was cancelled (no "
               "results dict from signal).");
    // pctx->last_error should have been set by
    // on_portal_request_signal_response
    return;
  }
  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "PW Screen: Portal SelectSources successful (user made a selection).");

  g_free(pctx->portal_request_handle_str);
  pctx->portal_request_handle_str = generate_token("miniav_start_req");

  GVariantBuilder options_builder;
  g_variant_builder_init(&options_builder, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options_builder, "{sv}", "handle_token",
                        g_variant_new_string(pctx->portal_request_handle_str));
  GVariant *start_options = g_variant_builder_end(&options_builder);

  const char *parent_window_handle =
      ""; // Typically empty for Wayland, or "x11:..."

  g_dbus_connection_call(
      pctx->dbus_conn, XDP_BUS_NAME,
      pctx->portal_session_handle_str, // Session object path
      XDP_IFACE_SESSION, "Start",
      g_variant_new("(sa{sv})", parent_window_handle, start_options),
      G_VARIANT_TYPE("(o)"), // Expected reply: (handle request_handle)
      G_DBUS_CALL_FLAGS_NONE,
      -1, // Default timeout
      pctx->cancellable, (GAsyncReadyCallback)on_portal_request_response, pctx);
}

static void
on_portal_create_session_response(PipeWireScreenPlatformContext *pctx,
                                  GVariant *results_variant) {
  // results_variant is the direct reply from CreateSession, type (o)
  if (!results_variant) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "PW Screen: Portal CreateSession method failed (no results variant).");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    return;
  }

  g_variant_get(results_variant, "(o)", &pctx->portal_session_handle_str);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Portal session created: %s",
             pctx->portal_session_handle_str);

  g_dbus_connection_signal_subscribe(
      pctx->dbus_conn, XDP_BUS_NAME, XDP_IFACE_SESSION, "SessionClosed",
      pctx->portal_session_handle_str,
      NULL, // arg0 filter
      G_DBUS_SIGNAL_FLAGS_NONE, (GDBusSignalCallback)on_portal_session_closed,
      pctx, NULL);

  g_free(pctx->portal_request_handle_str);
  pctx->portal_request_handle_str = generate_token("miniav_select_req");

  GVariantBuilder options_builder;
  g_variant_builder_init(&options_builder, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options_builder, "{sv}", "handle_token",
                        g_variant_new_string(pctx->portal_request_handle_str));
  g_variant_builder_add(&options_builder, "{sv}", "multiple",
                        g_variant_new_boolean(FALSE));

  uint32_t source_types = 0; // 1=monitor, 2=window
  if (pctx->capture_type == MINIAV_CAPTURE_TYPE_DISPLAY)
    source_types = (1 << 0);
  else if (pctx->capture_type == MINIAV_CAPTURE_TYPE_WINDOW)
    source_types = (1 << 1);
  else if (pctx->capture_type == MINIAV_CAPTURE_TYPE_REGION)
    source_types = (1 << 0) | (1 << 1); // Region might be based on either
  else
    source_types = (1 << 0) | (1 << 1); // Default to both if unspecified

  g_variant_builder_add(&options_builder, "{sv}", "types",
                        g_variant_new_uint32(source_types));
  // Optionally add "persist_mode" if needed.

  GVariant *select_options = g_variant_builder_end(&options_builder);

  g_dbus_connection_call(
      pctx->dbus_conn, XDP_BUS_NAME,
      XDP_OBJECT_PATH, // Portal main object
      XDP_IFACE_SCREENCAST, "SelectSources",
      g_variant_new("(oa{sv})", pctx->portal_session_handle_str,
                    select_options),
      G_VARIANT_TYPE("(o)"), // Expected reply: (handle request_handle)
      G_DBUS_CALL_FLAGS_NONE, -1, pctx->cancellable,
      (GAsyncReadyCallback)on_portal_request_response, pctx);
}

static void on_portal_request_response(GObject *source_object,
                                       GAsyncResult *res, gpointer user_data) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)user_data;
  GError *error = NULL;
  GVariant *result_variant = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source_object), res, &error);

  if (error) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: D-Bus request call failed: %s", error->message);
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    g_error_free(error);
    if (result_variant)
      g_variant_unref(result_variant);
    return;
  }

  char *request_handle_path_temp;
  g_variant_get(result_variant, "(o)", &request_handle_path_temp);
  g_variant_unref(result_variant); // Unref the variant from call_finish

  char *request_handle_path =
      g_strdup(request_handle_path_temp); // Dup for signal subscription
  // request_handle_path_temp is now invalid as result_variant is unreffed.

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: D-Bus request initiated, handle: %s. Waiting for "
             "Response signal.",
             request_handle_path);

  g_dbus_connection_signal_subscribe(
      pctx->dbus_conn, XDP_BUS_NAME, XDP_IFACE_REQUEST, "Response",
      request_handle_path, // Object path of the request
      NULL,                // arg0 filter

      (GDBusSignalFlags)(G_DBUS_SIGNAL_FLAGS_NO_MATCH_RULE), // Potentially add
                                                             // G_DBUS_SIGNAL_FLAGS_ONE_SHOT
                                                             // if GLib is new
                                                             // enough and it
                                                             // works
      (GDBusSignalCallback)on_portal_request_signal_response,
      pctx,  // Pass pctx as user_data
      NULL); // No GDestroyNotify needed for pctx if it lives long enough
  g_free(request_handle_path);
}

static void on_portal_request_signal_response(
    GDBusConnection *connection, const gchar *sender_name,
    const gchar *object_path, // Path of the Request object
    const gchar *interface_name, const gchar *signal_name,
    GVariant *parameters, // (uint response_code, dict results)
    gpointer user_data) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)user_data;

  guint subscription_id = (guint)(uintptr_t)g_object_get_data(
      G_OBJECT(connection),
      object_path); // This is tricky, need to store subscription ID
  if (subscription_id > 0) {
    g_dbus_connection_signal_unsubscribe(connection, subscription_id);
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Received Response signal for request object %s",
             object_path);

  guint response_code;
  GVariant *results_dict = NULL; // Must be initialized
  g_variant_get(parameters, "(u@a{sv})", &response_code,
                &results_dict); // results_dict is new ref

  if (response_code != 0) { // 0 = success, 1 = user cancelled, 2 = error
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Portal request %s failed/cancelled with code %u.",
               object_path, response_code);
    pctx->last_error = (response_code == 1)
                           ? MINIAV_ERROR_USER_CANCELLED // Use defined error
                           : MINIAV_ERROR_PORTAL_FAILED;
    if (results_dict)
      g_variant_unref(results_dict);
    // Potentially trigger cleanup or notify application
    return;
  }

  // Determine which step this response corresponds to
  if (g_str_has_prefix(pctx->portal_request_handle_str, "miniav_select_req")) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Processing SelectSources response via signal.");
    on_portal_select_sources_response(pctx, results_dict); // Pass the dict
  } else if (g_str_has_prefix(pctx->portal_request_handle_str,
                              "miniav_start_req")) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Processing Start response via signal.");
    on_portal_start_response(pctx, results_dict); // Pass the dict
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Unknown portal request response for token %s",
               pctx->portal_request_handle_str);
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
  }

  if (results_dict)
    g_variant_unref(results_dict);
}

static void
on_portal_session_closed(GDBusConnection *connection, const gchar *sender_name,
                         const gchar *object_path, // Session object path
                         const gchar *interface_name, const gchar *signal_name,
                         GVariant *parameters, // (uint reason)
                         gpointer user_data) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)user_data;
  guint reason;
  g_variant_get(parameters, "(u)", &reason);
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW Screen: Portal session %s closed, reason: %u", object_path,
             reason);

  if (pctx->portal_session_handle_str &&
      strcmp(pctx->portal_session_handle_str, object_path) == 0) {
    g_free(pctx->portal_session_handle_str);
    pctx->portal_session_handle_str = NULL;
    if (pctx->parent_ctx->is_running) {
      miniav_log(MINIAV_LOG_LEVEL_WARN, "PW Screen: Active capture session "
                                        "closed by portal. Stopping capture.");
      pctx->last_error = MINIAV_ERROR_PORTAL_CLOSED;
      // Trigger a stop locally. The app might also call stop_capture.
      if (pctx->video_stream)
        pw_stream_set_active(pctx->video_stream, false);
      if (pctx->audio_stream)
        pw_stream_set_active(pctx->audio_stream, false);
      if (pctx->loop_running && pctx->wakeup_pipe[1] != -1) {
        write(pctx->wakeup_pipe[1], "q", 1);
      }
      pctx->parent_ctx->is_running = false;
    }
  }
}

static void on_portal_create_session_dbus_response(GObject *source_object,
                                                   GAsyncResult *res,
                                                   gpointer user_data) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)user_data;
  GError *error = NULL;
  GVariant *result_variant = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source_object), res, &error);

  if (error) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Portal CreateSession D-Bus call failed: %s",
               error->message);
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    g_error_free(error);
    if (result_variant)
      g_variant_unref(result_variant);
    return;
  }
  on_portal_create_session_response(pctx, result_variant);
  g_variant_unref(result_variant);
}

static MiniAVResultCode pw_screen_start_capture(struct MiniAVScreenContext *ctx,
                                                MiniAVBufferCallback callback,
                                                void *user_data) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  if (!ctx->is_configured)
    return MINIAV_ERROR_NOT_INITIALIZED;
  // loop_running check is tricky here due to async portal.
  // is_running on parent_ctx might be a better check if portal is already
  // active.
  if (pctx->parent_ctx->is_running || pctx->loop_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Start capture called but seems already running or "
               "portal active.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Starting capture via xdg-desktop-portal...");

  pctx->app_callback_pending = callback;
  pctx->app_callback_user_data_pending = user_data;
  pctx->last_error = MINIAV_SUCCESS;

  if (!pctx->dbus_conn) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: D-Bus connection not available for portal.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  if (g_cancellable_is_cancelled(pctx->cancellable)) {
    g_object_unref(pctx->cancellable);
    pctx->cancellable = g_cancellable_new();
  }

  g_free(pctx->portal_request_handle_str);
  pctx->portal_request_handle_str =
      generate_token("miniav_session_req_token"); // For CreateSession options
  char *session_token = generate_token(
      "miniav_session_handle_token"); // For CreateSession options

  GVariantBuilder options_builder;
  g_variant_builder_init(&options_builder, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options_builder, "{sv}", "handle_token",
                        g_variant_new_string(pctx->portal_request_handle_str));
  g_variant_builder_add(&options_builder, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token));
  GVariant *create_session_options = g_variant_builder_end(&options_builder);
  g_free(session_token);

  g_dbus_connection_call(
      pctx->dbus_conn, XDP_BUS_NAME, XDP_OBJECT_PATH, XDP_IFACE_SCREENCAST,
      "CreateSession", g_variant_new("(a{sv})", create_session_options),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, pctx->cancellable,
      (GAsyncReadyCallback)on_portal_create_session_dbus_response, pctx);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: CreateSession call initiated with token %s.",
             pctx->portal_request_handle_str);
  return MINIAV_SUCCESS;
}

static void
pw_screen_setup_pipewire_streams(PipeWireScreenPlatformContext *pctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Portal interaction successful, proceeding to setup "
             "PipeWire streams.");

  pctx->parent_ctx->app_callback = pctx->app_callback_pending;
  pctx->parent_ctx->app_callback_user_data =
      pctx->app_callback_user_data_pending;
  pctx->app_callback_pending = NULL;
  pctx->app_callback_user_data_pending = NULL;

  if (pctx->video_node_id == PW_ID_ANY) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: No valid video_node_id from portal. Cannot start "
               "PipeWire streams.");
    pctx->last_error = MINIAV_ERROR_PORTAL_FAILED;
    if (pctx->parent_ctx->app_callback) {
      // TODO: Consider how to signal this specific error to the app if needed
    }
    return;
  }

  // --- Create Video Stream ---
  if (pctx->video_node_id != PW_ID_ANY) {
    pctx->video_stream = pw_stream_new(
        pctx->core, "miniav-screen-video",
        pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                          "Capture", PW_KEY_MEDIA_ROLE, "Screen", NULL));
    if (!pctx->video_stream) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW Screen: Failed to create video stream.");
      pctx->last_error = MINIAV_ERROR_SYSTEM_CALL_FAILED;
      goto error_cleanup_pw_setup;
    }

    static const struct pw_stream_events video_stream_events = {
        PW_VERSION_STREAM_EVENTS,
        .state_changed = on_video_stream_state_changed,
        .param_changed = on_video_stream_param_changed,
        .process = on_video_stream_process,
        .add_buffer = on_video_stream_add_buffer,
        .remove_buffer = on_video_stream_remove_buffer,
    };
    pw_stream_add_listener(pctx->video_stream, &pctx->video_stream_listener,
                           &video_stream_events, pctx);

    uint8_t video_params_buffer[2048];
    struct spa_pod_builder b =
        SPA_POD_BUILDER_INIT(video_params_buffer, sizeof(video_params_buffer));
    const struct spa_pod *params[2];
    uint32_t n_params = 0;

    enum spa_video_format spa_fmt_req =
        miniav_video_format_to_spa(pctx->requested_video_format.pixel_format);
    if (spa_fmt_req == SPA_VIDEO_FORMAT_UNKNOWN)
      spa_fmt_req = SPA_VIDEO_FORMAT_BGRA;

    params[n_params++] = spa_format_video_raw_build(
        &b, SPA_PARAM_EnumFormat,
        &SPA_VIDEO_INFO_RAW_INIT(
                .format = spa_fmt_req,
                .size = SPA_RECTANGLE(pctx->requested_video_format.width,
                                      pctx->requested_video_format.height),
                .framerate = SPA_FRACTION(
                    pctx->requested_video_format.frame_rate_numerator,
                    pctx->requested_video_format.frame_rate_denominator)));

    uint32_t buffer_types =
        (1 << SPA_DATA_DmaBuf) | (1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr);
    params[n_params++] = spa_pod_builder_add_object(
        &b, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
        SPA_PARAM_BUFFERS_buffers,
        SPA_POD_CHOICE_RANGE_Int(PW_SCREEN_MAX_BUFFERS, 1,
                                 PW_SCREEN_MAX_BUFFERS),
        SPA_PARAM_BUFFERS_blocks, SPA_POD_Int(1), SPA_PARAM_BUFFERS_dataType,
        SPA_POD_CHOICE_FLAGS_Int(buffer_types));

    if (pw_stream_connect(
            pctx->video_stream, PW_DIRECTION_INPUT, pctx->video_node_id,
            PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS |
                PW_STREAM_FLAG_RT_PROCESS,
            params, n_params) != 0) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "PW Screen: Failed to connect video stream to node %u: %s",
          pctx->video_node_id,
          spa_strerror(
              errno)); // errno might not be set by pw, use pw_context_errno
      pctx->last_error = MINIAV_ERROR_STREAM_FAILED;
      goto error_cleanup_pw_setup;
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Video stream connecting to node %u...",
               pctx->video_node_id);
  } else {
    // This case should be caught earlier by video_node_id == PW_ID_ANY check
  }

  // --- Create Audio Stream ---
  if (pctx->audio_requested_by_user && pctx->audio_node_id != PW_ID_ANY) {
    pctx->audio_stream = pw_stream_new(
        pctx->core, "miniav-screen-audio",
        pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY,
                          "Capture", PW_KEY_MEDIA_ROLE, "ScreenAudio", NULL));
    if (!pctx->audio_stream) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW Screen: Failed to create audio stream.");
      pctx->last_error = MINIAV_ERROR_SYSTEM_CALL_FAILED;
      goto error_cleanup_pw_setup; // Cleanup video stream if it was created
    }

    static const struct pw_stream_events audio_stream_events = {
        PW_VERSION_STREAM_EVENTS,
        .state_changed = on_audio_stream_state_changed,
        .param_changed = on_audio_stream_param_changed,
        .process = on_audio_stream_process,
    };
    pw_stream_add_listener(pctx->audio_stream, &pctx->audio_stream_listener,
                           &audio_stream_events, pctx);

    uint8_t audio_params_buffer[1024];
    struct spa_pod_builder audio_b =
        SPA_POD_BUILDER_INIT(audio_params_buffer, sizeof(audio_params_buffer));
    const struct spa_pod *audio_params[1];
    enum spa_audio_format spa_audio_fmt_req =
        miniav_audio_format_to_spa_audio(pctx->requested_audio_format.format);
    if (spa_audio_fmt_req == SPA_AUDIO_FORMAT_UNKNOWN)
      spa_audio_fmt_req = SPA_AUDIO_FORMAT_F32_LE;

    audio_params[0] = spa_format_audio_raw_build(
        &audio_b, SPA_PARAM_EnumFormat,
        &SPA_AUDIO_INFO_RAW_INIT(.format = spa_audio_fmt_req,
                                 .channels =
                                     pctx->requested_audio_format.channels,
                                 .rate =
                                     pctx->requested_audio_format.sample_rate));

    if (pw_stream_connect(pctx->audio_stream, PW_DIRECTION_INPUT,
                          pctx->audio_node_id, // Use the audio_node_id from
                                               // portal if available
                          PW_STREAM_FLAG_AUTOCONNECT |
                              PW_STREAM_FLAG_MAP_BUFFERS |
                              PW_STREAM_FLAG_RT_PROCESS,
                          audio_params, 1) != 0) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW Screen: Failed to connect audio stream to node %u: %s",
                 pctx->audio_node_id, spa_strerror(errno));
      pctx->last_error = MINIAV_ERROR_STREAM_FAILED;
      goto error_cleanup_pw_setup;
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Audio stream connecting to node %u...",
               pctx->audio_node_id);
  } else if (pctx->audio_requested_by_user) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Audio requested, but no valid audio_node_id from "
               "portal. Audio capture skipped.");
  }

  // --- Start PipeWire Loop Thread ---
  if (pthread_create(&pctx->loop_thread, NULL, pw_screen_loop_thread_func,
                     pctx->parent_ctx) != 0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Failed to create PipeWire loop thread.");
    pctx->last_error = MINIAV_ERROR_SYSTEM_CALL_FAILED;
    goto error_cleanup_pw_setup;
  }

  miniav_log(
      MINIAV_LOG_LEVEL_INFO,
      "PW Screen: PipeWire streams configured and loop thread starting.");
  // pctx->parent_ctx->is_running will be set by stream state changes.
  return;

error_cleanup_pw_setup:
  if (pctx->video_stream) {
    pw_stream_destroy(pctx->video_stream);
    pctx->video_stream = NULL;
  }
  if (pctx->audio_stream) {
    pw_stream_destroy(pctx->audio_stream);
    pctx->audio_stream = NULL;
  }
  // Notify app of failure if callback was set
  if (pctx->parent_ctx->app_callback) {
    // TODO: How to signal this error to app? Maybe a special buffer or error
    // callback? For now, the app will just not receive buffers.
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "PW Screen: Failed to setup PipeWire streams. Capture will not start.");
  }
  pctx->parent_ctx->is_running = false; // Ensure it's marked as not running
}

static MiniAVResultCode
pw_screen_stop_capture(struct MiniAVScreenContext *ctx) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Stopping capture.");

  // Cancel any ongoing D-Bus portal operations
  if (pctx->cancellable && !g_cancellable_is_cancelled(pctx->cancellable)) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Cancelling pending D-Bus operations.");
    g_cancellable_cancel(pctx->cancellable);
  }
  // Reset pending callback info
  pctx->app_callback_pending = NULL;
  pctx->app_callback_user_data_pending = NULL;

  if (!pctx->loop_running && !pctx->video_stream_active &&
      !pctx->audio_stream_active && !pctx->parent_ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: Capture not running or already stopped.");
    // Still ensure portal session is attempted to be closed if handle exists
    if (pctx->portal_session_handle_str && pctx->dbus_conn) {
      // Synchronous close attempt, similar to destroy_platform
      GError *error = NULL;
      GCancellable *close_cancellable =
          g_cancellable_new(); // Fresh cancellable for this sync call
      g_dbus_connection_call_sync(
          pctx->dbus_conn, XDP_BUS_NAME, pctx->portal_session_handle_str,
          XDP_IFACE_SESSION, "Close", NULL, NULL, G_DBUS_CALL_FLAGS_NONE, 1000,
          close_cancellable, &error); // Short timeout
      if (error) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW Screen: Failed to close portal session during stop (was "
                   "not running): %s",
                   error->message);
        g_error_free(error);
      }
      g_object_unref(close_cancellable);
      g_free(pctx->portal_session_handle_str);
      pctx->portal_session_handle_str = NULL;
    }
    return MINIAV_SUCCESS;
  }

  if (pctx->video_stream) {
    pw_stream_set_active(pctx->video_stream,
                         false); // Request stream to stop processing
    pw_stream_disconnect(pctx->video_stream);
  }
  if (pctx->audio_stream) {
    pw_stream_set_active(pctx->audio_stream, false);
    pw_stream_disconnect(pctx->audio_stream);
  }

  pctx->video_stream_active = false;
  pctx->audio_stream_active = false;

  if (pctx->loop_running && pctx->loop) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Signaling PipeWire loop to quit.");
    if (pctx->wakeup_pipe[1] != -1) {
      char buf = 'q'; // quit signal
      if (write(pctx->wakeup_pipe[1], &buf, 1) == -1 && errno != EAGAIN) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW Screen: Failed to write to wakeup pipe: %s",
                   strerror(errno));
      }
    } else {
      pw_main_loop_quit(pctx->loop); // Fallback if pipe not working
    }
  }

  if (pctx->loop_thread) { // Check if thread was actually created
    pthread_join(pctx->loop_thread, NULL);
    pctx->loop_thread = 0;
  }
  pctx->loop_running = false;

  // Now destroy streams fully
  if (pctx->video_stream) {
    pw_stream_destroy(pctx->video_stream);
    pctx->video_stream = NULL;
  }
  if (pctx->audio_stream) {
    pw_stream_destroy(pctx->audio_stream);
    pctx->audio_stream = NULL;
  }

  // Close portal session
  if (pctx->portal_session_handle_str && pctx->dbus_conn) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Closing portal session %s after capture stop.",
               pctx->portal_session_handle_str);
    GError *error = NULL;
    GCancellable *close_cancellable = g_cancellable_new();
    // This should ideally be an async call if stop_capture itself needs to be
    // non-blocking. For simplicity, using sync call here.
    g_dbus_connection_call_sync(
        pctx->dbus_conn, XDP_BUS_NAME, pctx->portal_session_handle_str,
        XDP_IFACE_SESSION, "Close", NULL, NULL, G_DBUS_CALL_FLAGS_NONE,
        5000, // 5s timeout
        close_cancellable, &error);
    if (error) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Failed to close portal session %s: %s",
                 pctx->portal_session_handle_str, error->message);
      g_error_free(error);
    }
    g_object_unref(close_cancellable);
    g_free(pctx->portal_session_handle_str);
    pctx->portal_session_handle_str = NULL;
  }

  ctx->is_running = false;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "PW Screen: Capture stopped.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_release_buffer(struct MiniAVScreenContext *ctx,
                         void *internal_handle_ptr) { // Renamed for clarity
  MINIAV_UNUSED(ctx);

  if (!internal_handle_ptr) {
    miniav_log(
        MINIAV_LOG_LEVEL_DEBUG,
        "PW Screen: release_buffer called with NULL internal_handle_ptr.");
    return MINIAV_SUCCESS;
  }

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)internal_handle_ptr;

  if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN) {
    intptr_t fd_ptr_val = (intptr_t)payload->native_resource_ptr;
    if (fd_ptr_val != -1 && fd_ptr_val != 0) {
      int fd_to_close = (int)fd_ptr_val;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW Screen: Releasing buffer, closing duplicated DMABUF FD: "
                 "%d from payload.",
                 fd_to_close);
      if (close(fd_to_close) == -1) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW Screen: Failed to close DMABUF FD %d: %s", fd_to_close,
                   strerror(errno));
        // Consider if this should return an error. For now, it doesn't.
      }
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW Screen: Releasing video buffer (payload resource was %p, "
                 "likely CPU or not a duplicated FD).",
                 payload->native_resource_ptr);
    }
  } else if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_AUDIO) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Releasing audio buffer (no specific native resource "
               "to free from payload).");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "PW Screen: release_buffer called for unknown handle_type %d.",
               payload->handle_type);
  }

  miniav_free(payload); // Free the payload struct itself
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_get_default_formats(const char *device_id,
                              MiniAVVideoInfo *video_format_out,
                              MiniAVAudioInfo *audio_format_out) {
  MINIAV_UNUSED(device_id);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: GetDefaultFormats for device: %s",
             device_id ? device_id : "Any (Portal)");

  if (video_format_out) {
    video_format_out->pixel_format =
        MINIAV_PIXEL_FORMAT_BGRA32; // Common, good quality
    video_format_out->width = 1920;
    video_format_out->height = 1080;
    video_format_out->frame_rate_numerator = 30;
    video_format_out->frame_rate_denominator = 1;
    video_format_out->output_preference =
        MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE;
    // num_planes, strides, dmabuf_plane_offsets are not part of
    // MiniAVVideoInfo
  }
  if (audio_format_out) {
    audio_format_out->format = MINIAV_AUDIO_FORMAT_F32;
    audio_format_out->sample_rate = 48000;
    audio_format_out->channels = 2;
  }
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "PW Screen: GetDefaultFormats provides common placeholders. "
             "Actual formats depend on source negotiation.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
pw_screen_get_configured_video_formats(struct MiniAVScreenContext *ctx,
                                       MiniAVVideoInfo *video_format_out,
                                       MiniAVAudioInfo *audio_format_out) {
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  if (!ctx->is_configured && !ctx->is_running)
    return MINIAV_ERROR_NOT_INITIALIZED;

  if (video_format_out) {
    if ((pctx->video_stream_active || ctx->is_running) &&
        pctx->current_video_format_details.spa_format.format !=
            SPA_VIDEO_FORMAT_UNKNOWN) {
      video_format_out->pixel_format = spa_video_format_to_miniav(
          pctx->current_video_format_details.spa_format.format);
      video_format_out->width =
          pctx->current_video_format_details.spa_format.size.width;
      video_format_out->height =
          pctx->current_video_format_details.spa_format.size.height;
      video_format_out->frame_rate_numerator =
          pctx->current_video_format_details.spa_format.framerate.num;
      video_format_out->frame_rate_denominator =
          pctx->current_video_format_details.spa_format.framerate.denom;
      video_format_out->output_preference =
          pctx->requested_video_format.output_preference;
    } else if (ctx->is_configured) {
      *video_format_out = pctx->requested_video_format;
    } else {
      memset(video_format_out, 0, sizeof(MiniAVVideoInfo));
      video_format_out->pixel_format = MINIAV_PIXEL_FORMAT_UNKNOWN;
    }
  }

  if (audio_format_out) {
    // Use parent_ctx->configured_video_format if available and negotiated
    // Or fallback to pctx->requested_audio_format
    if ((pctx->audio_stream_active ||
         (ctx->is_running && pctx->audio_requested_by_user)) &&
        pctx->current_audio_format.format != SPA_AUDIO_FORMAT_UNKNOWN) {
      // Assuming MiniAVScreenContext has 'configured_video_format'
      if (ctx->configured_video_format.pixel_format !=
          MINIAV_AUDIO_FORMAT_UNKNOWN) {
        *audio_format_out = ctx->configured_audio_format;
      } else { // Fallback to constructing from current_audio_format if parent
               // not updated yet
        audio_format_out->format =
            spa_audio_format_to_miniav_audio(pctx->current_audio_format.format);
        audio_format_out->channels = pctx->current_audio_format.channels;
        audio_format_out->sample_rate = pctx->current_audio_format.rate;
      }
    } else if (ctx->is_configured && pctx->audio_requested_by_user) {
      *audio_format_out = pctx->requested_audio_format;
    } else {
      memset(audio_format_out, 0, sizeof(MiniAVAudioInfo));
      audio_format_out->format = MINIAV_AUDIO_FORMAT_UNKNOWN;
    }
  }
  return MINIAV_SUCCESS;
}
// --- PipeWire Thread and Event Handlers ---

static void *pw_screen_loop_thread_func(void *arg) {
  struct MiniAVScreenContext *ctx = (struct MiniAVScreenContext *)arg;
  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: PipeWire loop thread started.");
  pctx->loop_running = true;
  ctx->is_running = true; // Mark as running now that loop is starting

  // struct pw_loop *loop_ptr = pw_main_loop_get_loop(pctx->loop);
  // struct spa_source *wakeup_source = NULL;

  // Wakeup pipe is primarily for pw_main_loop_quit from another thread.
  // The loop itself doesn't need to handle reads from it if pw_main_loop_quit
  // is used. if (pctx->wakeup_pipe[0] != -1) {
  //   wakeup_source = pw_loop_add_io(loop_ptr, pctx->wakeup_pipe[0], SPA_IO_IN,
  //   false, NULL, pctx);
  // }

  pw_main_loop_run(pctx->loop); // Blocks here

  // if (wakeup_source) {
  //   pw_loop_remove_source(loop_ptr, wakeup_source);
  // }

  // loop_running and is_running are set to false by stop_capture before join,
  // or in destroy.
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: PipeWire loop thread finished.");
  return NULL;
}

// --- Core Listener Callbacks ---
static void on_pw_core_info(void *data, const struct pw_core_info *info) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Core info: id=%u, cookie=%u, name='%s', version='%s'",
             info->id, info->cookie, info->name ? info->name : "(null)",
             info->props ? spa_dict_lookup(info->props, PW_KEY_CORE_VERSION)
                         : "N/A");
  pctx->core_connected = true; // Mark core as connected
}

static void on_pw_core_done(void *data, uint32_t id, int seq) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Core done: id=%u, seq=%d", id,
             seq);
  if (id == PW_ID_CORE && seq == pctx->core_sync_seq) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Core sync complete.");
    // Potentially signal that core is fully ready if waiting on sync
  }
}
static void on_pw_core_error(void *data, uint32_t id, int seq, int res,
                             const char *message) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(
      MINIAV_LOG_LEVEL_ERROR,
      "PW Screen: Core error: id=%u, source_id=%u, seq=%d, res=%d (%s): %s", id,
      PW_ID_CORE, seq, res, spa_strerror(res), message);
  pctx->last_error = MINIAV_ERROR_SYSTEM_CALL_FAILED;
  if (pctx->loop_running && pctx->loop) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Quitting main loop due to core error.");
    pw_main_loop_quit(pctx->loop);
  }
  pctx->parent_ctx->is_running = false;
}

// --- Video Stream Listener Callbacks ---
static void on_video_stream_state_changed(void *data, enum pw_stream_state old,
                                          enum pw_stream_state new_state,
                                          const char *error) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Video stream state changed from %s to %s.",
             pw_stream_state_as_string(old),
             pw_stream_state_as_string(new_state));

  switch (new_state) {
  case PW_STREAM_STATE_ERROR:
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW Screen: Video stream error: %s",
               error ? error : "Unknown");
    pctx->video_stream_active = false;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    pctx->last_error = MINIAV_ERROR_STREAM_FAILED;
    if (pctx->loop_running && pctx->wakeup_pipe[1] != -1)
      write(pctx->wakeup_pipe[1], "e", 1);
    break;
  case PW_STREAM_STATE_UNCONNECTED:
    pctx->video_stream_active = false;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    if (old == PW_STREAM_STATE_CONNECTING || old == PW_STREAM_STATE_PAUSED ||
        old == PW_STREAM_STATE_STREAMING) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Video stream became unconnected.");
      if (pctx->last_error == MINIAV_SUCCESS)
        pctx->last_error = MINIAV_ERROR_STREAM_FAILED;
    }
    break;
  case PW_STREAM_STATE_CONNECTING:
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "PW Screen: Video stream connecting...");
    break;
  case PW_STREAM_STATE_PAUSED:
    miniav_log(
        MINIAV_LOG_LEVEL_DEBUG,
        "PW Screen: Video stream paused (format negotiated, buffers ready).");
    if (pw_stream_set_active(pctx->video_stream, true) < 0) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "PW Screen: Failed to set video stream active from PAUSED state.");
      pctx->last_error = MINIAV_ERROR_STREAM_FAILED;
    }
    break;
  case PW_STREAM_STATE_STREAMING:
    pctx->video_stream_active = true;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "PW Screen: Video stream is now streaming.");
    pctx->last_error =
        MINIAV_SUCCESS; // Clear previous errors if streaming starts
    break;
  }
}

static void on_video_stream_param_changed(void *data, uint32_t id,
                                          const struct spa_pod *param) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  if (!param || id != SPA_PARAM_Format) {
    return;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Video stream SPA_PARAM_Format received.");

  enum spa_media_type parsed_media_type; // Local variable for media type
  enum spa_media_subtype
      parsed_media_subtype; // Local variable for media subtype

  // Get the general media type and subtype first
  if (spa_format_parse(param, &parsed_media_type, &parsed_media_subtype) < 0) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "PW Screen: Failed to parse media type/subtype for video format.");
    return;
  }

  // Check if it's raw video
  if (parsed_media_type != SPA_MEDIA_TYPE_video ||
      parsed_media_subtype != SPA_MEDIA_SUBTYPE_raw) {
    // Handle non-raw video (e.g., DSP format) or log as unexpected
    struct spa_video_info_dsp format_info_dsp = {0};
    if (spa_format_video_dsp_parse(param, &format_info_dsp) == 0) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Parsed as DSP video format "
                 "(unexpected for raw screen capture). Format: %u",
                 format_info_dsp.format);
      // Mark our internal raw format as unknown since we didn't get raw
      pctx->current_video_format_details.spa_format.format =
          SPA_VIDEO_FORMAT_UNKNOWN;
      pctx->current_video_format_details.derived_num_planes = 0;
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "PW Screen: Received non-raw video format (%s/%s) and failed to "
          "parse as DSP.",
          spa_debug_type_find_name(spa_type_media_type, parsed_media_type),
          spa_debug_type_find_name(spa_type_media_subtype,
                                   parsed_media_subtype));
      pctx->current_video_format_details.spa_format.format =
          SPA_VIDEO_FORMAT_UNKNOWN;
      pctx->current_video_format_details.derived_num_planes = 0;
      return;
    }
  } else {
    // It's raw video, parse the detailed parameters into our spa_video_info_raw
    // struct
    if (spa_format_video_raw_parse(
            param, &pctx->current_video_format_details.spa_format) < 0) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "PW Screen: Failed to parse spa_video_info_raw for raw video.");
      // Mark format as unknown if parsing failed
      pctx->current_video_format_details.spa_format.format =
          SPA_VIDEO_FORMAT_UNKNOWN;
      pctx->current_video_format_details.derived_num_planes = 0;
      return; // Critical error if we expected raw but couldn't parse details
    }
  }

  // Proceed only if we have a successfully parsed raw video format
  if (pctx->current_video_format_details.spa_format.format !=
      SPA_VIDEO_FORMAT_UNKNOWN) {
    pctx->current_video_format_details.negotiated_modifier =
        pctx->current_video_format_details.spa_format.modifier;

    // Derive number of planes based on the MiniAV pixel format
    MiniAVPixelFormat miniav_fmt = spa_video_format_to_miniav(
        pctx->current_video_format_details.spa_format.format);
    pctx->current_video_format_details.derived_num_planes =
        get_miniav_pixel_format_planes(miniav_fmt);

    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "PW Screen: Negotiated video format: %s (overall type: %s/%s), "
               "%ux%u @ %u/%u fps, "
               "derived_planes: %u, modifier: %" PRIu64,
               spa_debug_type_find_name( // Specific raw format
                   spa_type_video_format,
                   pctx->current_video_format_details.spa_format.format),
               spa_debug_type_find_name( // Overall media type
                   spa_type_media_type, parsed_media_type),
               spa_debug_type_find_name( // Overall media subtype
                   spa_type_media_subtype, parsed_media_subtype),
               pctx->current_video_format_details.spa_format.size.width,
               pctx->current_video_format_details.spa_format.size.height,
               pctx->current_video_format_details.spa_format.framerate.num,
               pctx->current_video_format_details.spa_format.framerate.denom,
               pctx->current_video_format_details.derived_num_planes,
               pctx->current_video_format_details.negotiated_modifier);

    // Update parent context's view of the format (MiniAVVideoInfo)
    pctx->parent_ctx->configured_video_format.pixel_format = miniav_fmt;
    pctx->parent_ctx->configured_video_format.width =
        pctx->current_video_format_details.spa_format.size.width;
    pctx->parent_ctx->configured_video_format.height =
        pctx->current_video_format_details.spa_format.size.height;
    pctx->parent_ctx->configured_video_format.frame_rate_numerator =
        pctx->current_video_format_details.spa_format.framerate.num;
    pctx->parent_ctx->configured_video_format.frame_rate_denominator =
        pctx->current_video_format_details.spa_format.framerate.denom;
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "PW Screen: Video format is unknown or "
                                      "not usable after param changed.");
    // Ensure parent context reflects this
    pctx->parent_ctx->configured_video_format.pixel_format =
        MINIAV_PIXEL_FORMAT_UNKNOWN;
    pctx->current_video_format_details.derived_num_planes = 0;
    // Optionally clear other fields in configured_video_format
  }
}

static void on_video_stream_add_buffer(void *data, struct pw_buffer *buffer) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  struct spa_buffer *spa_buf = buffer->buffer;

  if (spa_buf->n_datas == 0)
    return;

  for (int i = 0; i < PW_SCREEN_MAX_BUFFERS; ++i) {
    if (pctx->video_pw_buffers[i] == NULL) {
      pctx->video_pw_buffers[i] = buffer; // Store PipeWire's buffer pointer
      if (spa_buf->datas[0].type == SPA_DATA_DmaBuf ||
          spa_buf->datas[0].type == SPA_DATA_MemFd) {
        pctx->video_dmabuf_fds[i] =
            spa_buf->datas[0].fd; // Store original FD (owned by PW)
        pctx->current_video_format_details.is_dmabuf = true;
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "PW Screen: Video add_buffer (idx %d): type %s, FD %ld, size %u", i,
            spa_debug_type_find_name(spa_type_data_type,
                                     spa_buf->datas[0].type),
            spa_buf->datas[0].fd, spa_buf->datas[0].maxsize);
      } else {
        pctx->current_video_format_details.is_dmabuf = false;
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "PW Screen: Video add_buffer (idx %d): type %s (CPU path), size %u",
            i,
            spa_debug_type_find_name(spa_type_data_type,
                                     spa_buf->datas[0].type),
            spa_buf->datas[0].maxsize);
      }
      break;
    }
  }
}

static void on_video_stream_remove_buffer(void *data,
                                          struct pw_buffer *buffer) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Video remove_buffer for pw_buffer %p", (void *)buffer);
  for (int i = 0; i < PW_SCREEN_MAX_BUFFERS; ++i) {
    if (pctx->video_pw_buffers[i] == buffer) {
      pctx->video_pw_buffers[i] = NULL;
      pctx->video_dmabuf_fds[i] = -1; // Clear stored original FD
      break;
    }
  }
}

static void on_video_stream_process(void *data) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  struct pw_buffer *pw_buf;
  MiniAVNativeBufferInternalPayload *payload_alloc = NULL;

  if (!pctx->parent_ctx->app_callback || !pctx->video_stream_active)
    return;

  while ((pw_buf = pw_stream_dequeue_buffer(pctx->video_stream))) {
    struct spa_buffer *spa_buf = pw_buf->buffer;
    struct spa_meta_header *h;
    payload_alloc = NULL; // Reset for each buffer

    if (spa_buf->n_datas < 1) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Video buffer has no data planes.");
      goto queue_and_continue_video;
    }

    MiniAVBuffer miniav_buffer = {0};
    miniav_buffer.type = MINIAV_BUFFER_TYPE_VIDEO;
    miniav_buffer.user_data = pctx->parent_ctx->app_callback_user_data;

    // pw_buf->time is uint64_t nsec. SPA_ID_INVALID is the correct invalid
    // marker.
    if ((h = spa_buffer_find_meta_data(spa_buf, SPA_META_Header, sizeof(*h))) &&
        h->pts != SPA_ID_INVALID) {
      miniav_buffer.timestamp_us = h->pts / 1000; // pts is usually nsec
    } else if (pw_buf->time != SPA_ID_INVALID) {
      miniav_buffer.timestamp_us = pw_buf->time / 1000; // Convert nsec to usec
    } else {
      miniav_buffer.timestamp_us = miniav_get_time_us();
    }

    // Populate MiniAVBuffer.data.video directly
    miniav_buffer.data.video.pixel_format = spa_video_format_to_miniav(
        pctx->current_video_format_details.spa_format.format);
    miniav_buffer.data.video.width =
        pctx->current_video_format_details.spa_format.size.width;
    miniav_buffer.data.video.height =
        pctx->current_video_format_details.spa_format.size.height;
    // Strides for MiniAVBuffer are set below for CPU path. For DMABUF, they are
    // implicit.

    if (pctx->current_video_format_details.is_dmabuf &&
        (spa_buf->datas[0].type == SPA_DATA_DmaBuf ||
         spa_buf->datas[0].type == SPA_DATA_MemFd)) {
      miniav_buffer.content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_DMABUF_FD;
      int original_fd = spa_buf->datas[0].fd;
      int dup_fd = fcntl(original_fd, F_DUPFD_CLOEXEC, 0);
      if (dup_fd == -1) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "PW Screen: Failed to dup DMABUF FD %d: %s. Skipping frame.",
                   original_fd, strerror(errno));
        goto queue_and_continue_video;
      }

      miniav_buffer.data.video.native_gpu_dmabuf_fd = dup_fd;
      // MiniAVBuffer does not have native_gpu_dmabuf_modifier

      payload_alloc = (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
      if (!payload_alloc) {
        miniav_log(
            MINIAV_LOG_LEVEL_ERROR,
            "PW Screen: Failed to allocate payload for DMABUF. Closing FD %d.",
            dup_fd);
        close(dup_fd);
        goto queue_and_continue_video;
      }
      payload_alloc->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
      payload_alloc->context_owner = pctx->parent_ctx;
      payload_alloc->native_resource_ptr = (void *)(intptr_t)dup_fd;
      miniav_buffer.internal_handle = payload_alloc;

      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "PW Screen: DMABUF frame: FD %d (orig %d), ts %" PRIu64
                 "us", // modifier not in MiniAVBuffer
                 dup_fd, original_fd, miniav_buffer.timestamp_us);

    } else if (spa_buf->datas[0].type == SPA_DATA_MemPtr) {
      miniav_buffer.content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;

      uint32_t num_miniav_planes =
          get_miniav_pixel_format_planes(miniav_buffer.data.video.pixel_format);

      if (num_miniav_planes == 0 && miniav_buffer.data.video.pixel_format !=
                                        MINIAV_PIXEL_FORMAT_UNKNOWN) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "PW Screen: CPU Video format %d resolved to 0 planes. Check "
                   "get_miniav_pixel_format_planes.",
                   miniav_buffer.data.video.pixel_format);
        goto queue_and_continue_video;
      }

      uint32_t total_size = 0;
      for (uint32_t i = 0;
           i < num_miniav_planes && i < MINIAV_VIDEO_FORMAT_MAX_PLANES; ++i) {
        if (i <
            spa_buf->n_datas) { // Check if PipeWire provides this plane data
          struct spa_data *d_plane = &spa_buf->datas[i];
          if (!(d_plane->data && d_plane->chunk && d_plane->chunk->size > 0)) {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "PW Screen: CPU Video buffer plane %u invalid.", i);
            if (i == 0)
              goto queue_and_continue_video; // First plane must be valid
            miniav_buffer.data.video.planes[i] = NULL;
            miniav_buffer.data.video.stride_bytes[i] = 0;
            continue;
          }
          miniav_buffer.data.video.planes[i] =
              (uint8_t *)d_plane->data + d_plane->chunk->offset;
          miniav_buffer.data.video.stride_bytes[i] = d_plane->chunk->stride;
          if (d_plane->chunk->stride == 0 &&
              miniav_buffer.data.video.pixel_format !=
                  MINIAV_PIXEL_FORMAT_MJPEG) {
            // For packed formats like BGRA, stride might be width * bpp if not
            // explicitly set. For MJPEG, stride is often 0 as it's a compressed
            // blob. This is a simplistic fallback, real stride calculation can
            // be complex.
            if (miniav_buffer.data.video.pixel_format ==
                    MINIAV_PIXEL_FORMAT_BGRA32 ||
                miniav_buffer.data.video.pixel_format ==
                    MINIAV_PIXEL_FORMAT_RGBA32 ||
                miniav_buffer.data.video.pixel_format ==
                    MINIAV_PIXEL_FORMAT_ARGB32 ||
                miniav_buffer.data.video.pixel_format ==
                    MINIAV_PIXEL_FORMAT_ABGR32) {
              miniav_buffer.data.video.stride_bytes[i] =
                  miniav_buffer.data.video.width * 4;
            } else if (miniav_buffer.data.video.pixel_format ==
                           MINIAV_PIXEL_FORMAT_RGB24 ||
                       miniav_buffer.data.video.pixel_format ==
                           MINIAV_PIXEL_FORMAT_BGR24) {
              miniav_buffer.data.video.stride_bytes[i] =
                  miniav_buffer.data.video.width * 3;
            } else {
              miniav_log(MINIAV_LOG_LEVEL_WARN,
                         "PW Screen: CPU Video buffer plane %u has stride 0 "
                         "from chunk for format %d. Data might be incorrect.",
                         i, miniav_buffer.data.video.pixel_format);
            }
          }
          total_size += d_plane->chunk->size; // Sum actual chunk sizes from PW
        } else {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "PW Screen: MiniAV expects plane %u but PipeWire only "
                     "provided %u data chunks.",
                     i, spa_buf->n_datas);
          miniav_buffer.data.video.planes[i] = NULL;
          miniav_buffer.data.video.stride_bytes[i] = 0;
        }
      }
      miniav_buffer.data_size_bytes = total_size;

      payload_alloc = (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
      if (!payload_alloc) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "PW Screen: Failed to allocate payload for CPU buffer.");
        goto queue_and_continue_video;
      }
      payload_alloc->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
      payload_alloc->context_owner = pctx->parent_ctx;
      payload_alloc->native_resource_ptr =
          NULL; // No specific FD to release for CPU
      miniav_buffer.internal_handle = payload_alloc;

      miniav_log(
          MINIAV_LOG_LEVEL_DEBUG,
          "PW Screen: CPU frame, plane0 ptr %p, total size %u, ts %" PRIu64
          "us",
          miniav_buffer.data.video.planes[0], total_size,
          miniav_buffer.timestamp_us);
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "PW Screen: Video buffer has unhandled data type: %s",
          spa_debug_type_find_name(spa_type_data_type, spa_buf->datas[0].type));
      goto queue_and_continue_video;
    }

    pctx->parent_ctx->app_callback(&miniav_buffer,
                                   pctx->parent_ctx->app_callback_user_data);
    payload_alloc = NULL; // Callback now owns the payload via internal_handle

  queue_and_continue_video:
    if (payload_alloc) { // If we allocated but didn't send to callback (e.g.
                         // goto)
      miniav_free(payload_alloc);
    }
    pw_stream_queue_buffer(pctx->video_stream, pw_buf);
    pctx->parent_ctx->configured_audio_format.sample_rate =
        pctx->current_audio_format.rate;
  }
}

// --- Audio Stream Listener Callbacks ---
static void on_audio_stream_state_changed(void *data, enum pw_stream_state old,
                                          enum pw_stream_state new_state,
                                          const char *error) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Audio stream state changed from %s to %s.",
             pw_stream_state_as_string(old),
             pw_stream_state_as_string(new_state));
  switch (new_state) {
  case PW_STREAM_STATE_ERROR:
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "PW Screen: Audio stream error: %s",
               error ? error : "Unknown");
    pctx->audio_stream_active = false;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    // Don't necessarily quit main loop if video is fine
    break;
  case PW_STREAM_STATE_UNCONNECTED:
    pctx->audio_stream_active = false;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    if (old == PW_STREAM_STATE_CONNECTING || old == PW_STREAM_STATE_PAUSED ||
        old == PW_STREAM_STATE_STREAMING) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "PW Screen: Audio stream became unconnected.");
    }
    break;
  case PW_STREAM_STATE_CONNECTING:
    break;
  case PW_STREAM_STATE_PAUSED:
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Audio stream paused (format negotiated).");
    if (pw_stream_set_active(pctx->audio_stream, true) < 0) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW Screen: Failed to set audio stream active from PAUSED.");
    }
    break;
  case PW_STREAM_STATE_STREAMING:
    pctx->audio_stream_active = true;
    pctx->parent_ctx->is_running =
        pctx->video_stream_active || pctx->audio_stream_active;
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "PW Screen: Audio stream is now streaming.");
    break;
  }
}

static void on_audio_stream_param_changed(void *data, uint32_t id,
                                          const struct spa_pod *param) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  if (!param || id != SPA_PARAM_Format) {
    return;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "PW Screen: Audio stream SPA_PARAM_Format received.");

  if (spa_format_audio_raw_parse(param, &pctx->current_audio_format) < 0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Failed to parse audio SPA_PARAM_Format.");
    return;
  }
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "PW Screen: Negotiated audio format: %s, %u channels, %u Hz",
             spa_debug_type_find_name(spa_type_audio_format,
                                      pctx->current_audio_format.format),
             pctx->current_audio_format.channels,
             pctx->current_audio_format.rate);

  // Update parent context's DEDICATED audio format member
  // Assuming MiniAVScreenContext has 'configured_video_format' of type
  // MiniAVAudioInfo
  if (pctx->parent_ctx) {
    pctx->parent_ctx->configured_video_format.pixel_format =
        spa_audio_format_to_miniav_audio(pctx->current_audio_format.format);
    pctx->parent_ctx->configured_video_format = pctx->requested_video_format;
    pctx->parent_ctx->configured_audio_format.sample_rate =
        pctx->current_audio_format.rate;
  }
}

static void on_audio_stream_process(void *data) {
  PipeWireScreenPlatformContext *pctx = (PipeWireScreenPlatformContext *)data;
  struct pw_buffer *pw_buf;
  MiniAVNativeBufferInternalPayload *payload_alloc = NULL;

  if (!pctx->parent_ctx->app_callback || !pctx->audio_stream_active)
    return;

  while ((pw_buf = pw_stream_dequeue_buffer(pctx->audio_stream))) {
    struct spa_buffer *spa_buf = pw_buf->buffer;
    struct spa_meta_header *h;
    payload_alloc = NULL; // Reset for each buffer

    if (spa_buf->n_datas < 1 || !spa_buf->datas[0].data ||
        spa_buf->datas[0].chunk->size == 0) {
      goto queue_audio_and_continue;
    }

    MiniAVBuffer miniav_buffer = {0};
    miniav_buffer.type = MINIAV_BUFFER_TYPE_AUDIO;
    miniav_buffer.user_data = pctx->parent_ctx->app_callback_user_data;

    if ((h = spa_buffer_find_meta_data(spa_buf, SPA_META_Header, sizeof(*h))) &&
        h->pts != SPA_ID_INVALID) {
      miniav_buffer.timestamp_us = h->pts / 1000; // pts is usually nsec
    } else if (pw_buf->time !=
               SPA_ID_INVALID) { // pw_buf->time is uint64_t nsec
      miniav_buffer.timestamp_us = pw_buf->time / 1000; // Convert nsec to usec
    } else {
      miniav_buffer.timestamp_us = miniav_get_time_us();
    }

    miniav_buffer.content_type =
        MINIAV_BUFFER_CONTENT_TYPE_CPU; // Audio is always CPU for now

    // Use parent_ctx->configured_video_format
    if (pctx->parent_ctx) {
      miniav_buffer.data.audio.info = pctx->parent_ctx->configured_audio_format;
    } else { // Should not happen
      memset(&miniav_buffer.data.audio.info, 0, sizeof(MiniAVAudioInfo));
      miniav_buffer.data.audio.info.format = MINIAV_AUDIO_FORMAT_UNKNOWN;
    }

    miniav_buffer.data.audio.data =
        (uint8_t *)spa_buf->datas[0].data + spa_buf->datas[0].chunk->offset;
    miniav_buffer.data_size_bytes = spa_buf->datas[0].chunk->size;

    // Calculate frame_count
    uint32_t bytes_per_sample_times_channels = 0;
    uint32_t bytes_per_sample = 0;
    switch (miniav_buffer.data.audio.info.format) {
    case MINIAV_AUDIO_FORMAT_U8:
      bytes_per_sample = 1;
      break;
    case MINIAV_AUDIO_FORMAT_S16:
      bytes_per_sample = 2;
      break;
    case MINIAV_AUDIO_FORMAT_S32:
      bytes_per_sample = 4;
      break;
    case MINIAV_AUDIO_FORMAT_F32:
      bytes_per_sample = 4;
      break;
    default:
      break;
    }
    if (miniav_buffer.data.audio.info.channels > 0 && bytes_per_sample > 0) {
      bytes_per_sample_times_channels =
          miniav_buffer.data.audio.info.channels * bytes_per_sample;
      miniav_buffer.data.audio.frame_count =
          miniav_buffer.data_size_bytes / bytes_per_sample_times_channels;
    } else {
      miniav_buffer.data.audio.frame_count = 0;
    }

    payload_alloc = (MiniAVNativeBufferInternalPayload *)miniav_calloc(
        1, sizeof(MiniAVNativeBufferInternalPayload));
    if (!payload_alloc) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "PW Screen: Failed to allocate payload for audio buffer.");
      goto queue_audio_and_continue;
    }
    payload_alloc->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO;
    payload_alloc->context_owner = pctx->parent_ctx;
    payload_alloc->native_resource_ptr = NULL; // No specific FD for audio
    miniav_buffer.internal_handle = payload_alloc;

    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "PW Screen: Audio frame, size %u, frames %u, ts %" PRIu64 "us",
               miniav_buffer.data_size_bytes,
               miniav_buffer.data.audio.frame_count,
               miniav_buffer.timestamp_us);
    pctx->parent_ctx->app_callback(&miniav_buffer,
                                   pctx->parent_ctx->app_callback_user_data);
    payload_alloc = NULL; // Callback owns it now

  queue_audio_and_continue:
    if (payload_alloc) { // If we allocated but didn't send to callback
      miniav_free(payload_alloc);
    }
    pw_stream_queue_buffer(pctx->audio_stream, pw_buf);
  }
}

// --- Ops Structure Definition ---
const ScreenContextInternalOps g_screen_ops_linux_pipewire = {
    .init_platform = pw_screen_init_platform,
    .destroy_platform = pw_screen_destroy_platform,
    .enumerate_displays = pw_screen_enumerate_displays,
    .enumerate_windows = pw_screen_enumerate_windows,
    .configure_display = pw_screen_configure_display,
    .configure_window = pw_screen_configure_window,
    .configure_region = pw_screen_configure_region,
    .start_capture = pw_screen_start_capture,
    .stop_capture = pw_screen_stop_capture,
    .release_buffer = pw_screen_release_buffer,
    .get_default_formats = pw_screen_get_default_formats,
    .get_configured_video_formats = pw_screen_get_configured_video_formats,
};

// --- Platform Init Function (called by screen_api.c) ---
MiniAVResultCode
miniav_screen_context_platform_init_linux_pipewire(MiniAVScreenContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;

  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "PW Screen: Initializing PipeWire platform backend for screen context.");

  // Initialize PipeWire library. Should be called once per application.
  // If multiple contexts are created, this might be called multiple times.
  // pw_init is refcounted, so it's safe.
  pw_init(NULL, NULL);
  // g_type_init(); // Generally not needed for modern GLib unless using GObject
  // features directly.

  PipeWireScreenPlatformContext *pctx =
      (PipeWireScreenPlatformContext *)miniav_calloc(
          1, sizeof(PipeWireScreenPlatformContext));
  if (!pctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "PW Screen: Failed to allocate platform context.");
    // pw_deinit(); // If pw_init was the very first, consider deinit. But
    // usually not here.
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }
  pctx->parent_ctx = ctx;
  pctx->wakeup_pipe[0] = pctx->wakeup_pipe[1] = -1; // Initialize pipe FDs

  ctx->platform_ctx = pctx;
  ctx->ops = &g_screen_ops_linux_pipewire;

  return MINIAV_SUCCESS;
}
#endif
