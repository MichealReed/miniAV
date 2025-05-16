#include <string.h> // For memset, strcmp, strncpy
#include "../../include/miniav_buffer.h" // For MiniAVNativeBufferInternalPayload
#include "../../include/miniav_capture.h"
#include "../../include/miniav_types.h"
#include "../common/miniav_logging.h"
#include "../common/miniav_utils.h" // For miniav_calloc, miniav_free, miniav_strlcpy
#include "camera_context.h"


// Platform-specific includes and extern declarations for backend table
#if defined(_WIN32)
// camera_context_win_mf.h should declare g_camera_ops_win_mf and miniav_camera_context_platform_init_windows_mf
#include "windows/camera_context_win_mf.h"
#elif defined(__APPLE__)
// #include "macos/camera_context_macos_avf.h"
// extern const CameraContextInternalOps g_camera_ops_macos_avf;
// extern MiniAVResultCode miniav_camera_context_platform_init_macos_avf(MiniAVCameraContext* ctx);
#elif defined(__linux__)
// #include "linux/camera_context_linux_v4l2.h"
// extern const CameraContextInternalOps g_camera_ops_linux_v4l2;
// extern MiniAVResultCode miniav_camera_context_platform_init_linux_v4l2(MiniAVCameraContext* ctx);
#endif

// --- Backend Table ---
// Order matters here for default preference.
static const MiniAVCameraBackend g_camera_backends[] = {
#if defined(_WIN32)
    {"MediaFoundation", &g_camera_ops_win_mf, miniav_camera_context_platform_init_windows_mf},
#endif
#if defined(__APPLE__)
    // {"AVFoundation", &g_camera_ops_macos_avf, miniav_camera_context_platform_init_macos_avf},
#endif
#if defined(__linux__)
    // {"V4L2", &g_camera_ops_linux_v4l2, miniav_camera_context_platform_init_linux_v4l2},
#endif
    {NULL, NULL, NULL} // Sentinel
};

MiniAVResultCode MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo **devices,
                                                uint32_t *count) {
  if (!devices || !count) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *devices = NULL;
  *count = 0;

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;
  for (const MiniAVCameraBackend *backend_entry = g_camera_backends;
       backend_entry->name != NULL; ++backend_entry) {
    if (backend_entry->ops && backend_entry->ops->enumerate_devices) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Attempting EnumerateDevices with camera backend: %s",
                 backend_entry->name);
      res = backend_entry->ops->enumerate_devices(devices, count);
      if (res == MINIAV_SUCCESS) {
        miniav_log(MINIAV_LOG_LEVEL_INFO,
                   "EnumerateDevices successful with camera backend: %s",
                   backend_entry->name);
        return MINIAV_SUCCESS;
      }
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "EnumerateDevices with camera backend %s failed or found no devices (code: %d). Trying next.",
                 backend_entry->name, res);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Camera backend %s does not support enumerate_devices.",
                 backend_entry->name);
    }
  }

  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_EnumerateDevices: No suitable backend found or all failed.");
  return res;
}

MiniAVResultCode MiniAV_Camera_GetSupportedFormats(
    const char *device_id, MiniAVVideoFormatInfo **formats, uint32_t *count) {
  if (!device_id || !formats || !count) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *formats = NULL;
  *count = 0;

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;
  for (const MiniAVCameraBackend *backend_entry = g_camera_backends;
       backend_entry->name != NULL; ++backend_entry) {
    if (backend_entry->ops && backend_entry->ops->get_supported_formats) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Attempting GetSupportedFormats with camera backend: %s for device: %s",
                 backend_entry->name, device_id);
      res = backend_entry->ops->get_supported_formats(device_id, formats, count);
      if (res == MINIAV_SUCCESS) {
        miniav_log(MINIAV_LOG_LEVEL_INFO,
                   "GetSupportedFormats successful with camera backend: %s for device: %s",
                   backend_entry->name, device_id);
        return MINIAV_SUCCESS;
      }
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "GetSupportedFormats with camera backend %s failed for device %s (code: %d). Trying next.",
                 backend_entry->name, device_id, res);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Camera backend %s does not support get_supported_formats.",
                 backend_entry->name);
    }
  }
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_GetSupportedFormats: No suitable backend found or all failed for device: %s",
             device_id);
  return res;
}

MiniAVResultCode MiniAV_Camera_GetDefaultFormat(
    const char *device_id, MiniAVVideoFormatInfo *format_out) {
  if (!device_id || !format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  memset(format_out, 0, sizeof(MiniAVVideoFormatInfo));

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;
  for (const MiniAVCameraBackend *backend_entry = g_camera_backends;
       backend_entry->name != NULL; ++backend_entry) {
    if (backend_entry->ops && backend_entry->ops->get_default_format) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Attempting GetDefaultFormat with camera backend: %s for device: %s",
                 backend_entry->name, device_id);
      res = backend_entry->ops->get_default_format(device_id, format_out);
      if (res == MINIAV_SUCCESS) {
        miniav_log(MINIAV_LOG_LEVEL_INFO,
                   "GetDefaultFormat successful with camera backend: %s for device: %s",
                   backend_entry->name, device_id);
        return MINIAV_SUCCESS;
      }
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "GetDefaultFormat with camera backend %s failed for device %s (code: %d). Trying next.",
                 backend_entry->name, device_id, res);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Camera backend %s does not support get_default_format.",
                 backend_entry->name);
    }
  }
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_GetDefaultFormat: No suitable backend found or all failed for device: %s",
             device_id);
  return res;
}


MiniAVResultCode
MiniAV_Camera_CreateContext(MiniAVCameraContextHandle *context_handle) {
  if (!context_handle) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *context_handle = NULL;

  MiniAVCameraContext *ctx =
      (MiniAVCameraContext *)miniav_calloc(1, sizeof(MiniAVCameraContext));
  if (!ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to allocate MiniAVCameraContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->base = miniav_context_base_create(NULL);
  if (!ctx->base) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to create base context for camera.");
    miniav_free(ctx);
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;
  const MiniAVCameraBackend *selected_backend_entry = NULL;

  for (const MiniAVCameraBackend *backend_entry = g_camera_backends;
       backend_entry->name != NULL; ++backend_entry) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "Attempting to initialize camera backend for context: %s",
               backend_entry->name);
    if (backend_entry->platform_init_for_selection) {
        res = backend_entry->platform_init_for_selection(ctx); // This should set ctx->ops
        if (res == MINIAV_SUCCESS) {
            selected_backend_entry = backend_entry;
            miniav_log(MINIAV_LOG_LEVEL_INFO,
                        "Successfully selected camera backend for context: %s",
                        selected_backend_entry->name);
            break;
        } else {
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                        "Camera backend %s platform_init_for_selection failed for context with code %d. Trying next.",
                        backend_entry->name, res);
            if (ctx->platform_ctx) { // Basic cleanup if platform_init_for_selection allocated
                miniav_free(ctx->platform_ctx);
                ctx->platform_ctx = NULL;
            }
            ctx->ops = NULL;
        }
    } else {
        miniav_log(MINIAV_LOG_LEVEL_WARN, "Camera backend %s has no platform_init_for_selection function.", backend_entry->name);
        res = MINIAV_ERROR_NOT_IMPLEMENTED;
    }
  }

  if (res != MINIAV_SUCCESS || !selected_backend_entry) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "No suitable camera backend found or all failed to initialize for context.");
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    return (res == MINIAV_SUCCESS) ? MINIAV_ERROR_NOT_SUPPORTED : res;
  }

  if (!ctx->ops || !ctx->ops->init_platform) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Platform ops or ops->init_platform not set by selected camera backend '%s'.",
               selected_backend_entry->name);
    if(ctx->platform_ctx) miniav_free(ctx->platform_ctx);
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  res = ctx->ops->init_platform(ctx);
  if (res != MINIAV_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "ctx->ops->init_platform for camera backend '%s' failed with code %d.",
               selected_backend_entry->name, res);
    if (ctx->ops->destroy_platform) {
      ctx->ops->destroy_platform(ctx);
    } else {
      miniav_free(ctx->platform_ctx);
    }
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    return res;
  }

  *context_handle = (MiniAVCameraContextHandle)ctx;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera context created successfully with backend: %s", selected_backend_entry->name);
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context_handle) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx) {
    return MINIAV_ERROR_INVALID_ARG;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "Destroying camera context...");
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Camera context is running. Attempting to stop capture...");
    MiniAV_Camera_StopCapture(context_handle);
  }

  if (ctx->ops && ctx->ops->destroy_platform) {
    ctx->ops->destroy_platform(ctx);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "destroy_platform op not available for camera. Freeing platform_ctx directly if it exists.");
    miniav_free(ctx->platform_ctx);
  }
  ctx->platform_ctx = NULL;


  if (ctx->base) {
    miniav_context_base_destroy(ctx->base);
  }
  miniav_free(ctx);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera context destroyed successfully.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Camera_Configure(MiniAVCameraContextHandle context_handle,
                        const char *device_id,
                        const MiniAVVideoFormatInfo *format) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx || !format ) { // device_id can be NULL for default, but format must exist
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->ops || !ctx->ops->configure) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Camera context or configure op not available.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Cannot configure camera while capture is running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }

  MiniAVResultCode res = ctx->ops->configure(ctx, device_id, format);
  if (res == MINIAV_SUCCESS) {
    ctx->is_configured = 1;
    ctx->configured_format = *format; // Cache the requested format
    if (device_id) {
        miniav_strlcpy(ctx->selected_device_id, device_id, sizeof(ctx->selected_device_id));
    } else {
        memset(ctx->selected_device_id, 0, sizeof(ctx->selected_device_id)); // Indicate default
    }
    float fps_approx = (format->frame_rate_denominator == 0)
                           ? 0.0f
                           : (float)format->frame_rate_numerator /
                                 format->frame_rate_denominator;
    miniav_log(
        MINIAV_LOG_LEVEL_INFO,
        "Camera configured: Device='%s', %ux%u @ %u/%u (%.2f) FPS, Format=%d",
        ctx->selected_device_id[0] ? ctx->selected_device_id : "Default", format->width, format->height,
        format->frame_rate_numerator, format->frame_rate_denominator,
        fps_approx, format->pixel_format);
  } else {
    ctx->is_configured = 0;
    memset(&ctx->configured_format, 0, sizeof(MiniAVVideoFormatInfo));
    memset(ctx->selected_device_id, 0, sizeof(ctx->selected_device_id));
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Camera configuration failed with code: %d", res);
  }
  return res;
}

MiniAVResultCode MiniAV_Camera_GetConfiguredFormat(
    MiniAVCameraContextHandle context_handle,
    MiniAVVideoFormatInfo *format_out) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx || !format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  memset(format_out, 0, sizeof(MiniAVVideoFormatInfo));

  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Camera not configured. Format information may be incomplete or default.");
    // return MINIAV_ERROR_NOT_INITIALIZED; // Or allow returning the cached (possibly zeroed) format
  }

  if (ctx->ops && ctx->ops->get_configured_format) {
    return ctx->ops->get_configured_format(ctx, format_out);
  } else {
    // Fallback to the cached format if the op is missing
    miniav_log(MINIAV_LOG_LEVEL_WARN, "get_configured_format op not available. Using cached format if configured.");
    if (ctx->is_configured) {
        *format_out = ctx->configured_format;
        return MINIAV_SUCCESS;
    }
  }
  miniav_log(MINIAV_LOG_LEVEL_ERROR, "Cannot get configured format: context not configured or op missing.");
  return MINIAV_ERROR_NOT_INITIALIZED;
}


MiniAVResultCode
MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context_handle,
                           MiniAVBufferCallback callback, void *user_data) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx || !callback) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Camera must be configured before starting capture.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Camera capture is already running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  if (!ctx->ops || !ctx->ops->start_capture) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "start_capture op not available for camera.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  ctx->app_callback = callback;
  ctx->app_callback_user_data = user_data;

  MiniAVResultCode res = ctx->ops->start_capture(ctx);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = 1;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera capture started.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to start camera capture, code: %d", res);
    ctx->app_callback = NULL; // Clear on failure
    ctx->app_callback_user_data = NULL;
  }
  return res;
}

MiniAVResultCode
MiniAV_Camera_StopCapture(MiniAVCameraContextHandle context_handle) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Camera capture not running or already stopped.");
    return MINIAV_SUCCESS;
  }
  if (!ctx->ops || !ctx->ops->stop_capture) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "stop_capture op not available for camera.");
    // Still mark as not running if op is missing but we were asked to stop
    ctx->is_running = 0;
    ctx->app_callback = NULL;
    ctx->app_callback_user_data = NULL;
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "Stopping camera capture...");
  MiniAVResultCode res = ctx->ops->stop_capture(ctx);
  ctx->is_running = 0; // Update state regardless of backend result

  if (res == MINIAV_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera capture stopped successfully.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to stop camera capture, code: %d", res);
  }
  // Clear callback info after stopping
  ctx->app_callback = NULL;
  ctx->app_callback_user_data = NULL;
  return res;
}