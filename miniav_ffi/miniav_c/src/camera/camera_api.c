#include "../../include/miniav_buffer.h" // For MiniAVNativeBufferInternalPayload
#include "../../include/miniav_capture.h"
#include "../../include/miniav_types.h"
#include "../common/miniav_logging.h"
#include "../common/miniav_utils.h" // For miniav_calloc, miniav_free, miniav_strlcpy
#include "camera_context.h"

#include <string.h> // For memset, strcmp

// Platform-specific includes for static-like operations or initializers
#if defined(_WIN32)
#include "windows/camera_context_win_mf.h" // Declares ops_win_mf and miniav_camera_context_init_win_mf
#elif defined(__APPLE__)
// #include "macos/camera_context_macos_avf.h"
#elif defined(__linux__)
// #include "linux/camera_context_linux_v4l2.h"
#endif

MiniAVResultCode MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo **devices,
                                                uint32_t *count) {
  if (!devices || !count) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  // For now, directly call the appropriate platform's static-like enumerate
  // function A more sophisticated system might try multiple backends or use a
  // pre-initialized default.
#if defined(_WIN32)
  // The ops struct is typically associated with an instance, but for static
  // enumeration, we might call a direct static function from the platform
  // implementation or use a global ops struct. Let's assume the platform
  // implementation provides a static function or uses its global ops. For
  // simplicity, if camera_context_win_mf.h exposes ops_win_mf:
  if (g_camera_ops_win_mf.enumerate_devices) {
    return g_camera_ops_win_mf.enumerate_devices(devices, count);
  }
  return MINIAV_ERROR_NOT_SUPPORTED; // Fallback if not defined
#elif defined(__APPLE__)
  // return macos_ops.enumerate_devices(devices, count);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_EnumerateDevices not implemented for this platform yet.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#elif defined(__linux__)
  // return linux_ops.enumerate_devices(devices, count);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_EnumerateDevices not implemented for this platform yet.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#else
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Camera_EnumerateDevices: Platform not supported.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Camera_GetSupportedFormats(
    const char *device_id, MiniAVVideoFormatInfo **formats, uint32_t *count) {
  if (!device_id || !formats || !count) {
    return MINIAV_ERROR_INVALID_ARG;
  }
#if defined(_WIN32)
  if (g_camera_ops_win_mf.get_supported_formats) {
    return g_camera_ops_win_mf.get_supported_formats(device_id, formats, count);
  }
  return MINIAV_ERROR_NOT_SUPPORTED;
#elif defined(__APPLE__)
  miniav_log(
      MINIAV_LOG_LEVEL_WARN,
      "Camera_GetSupportedFormats not implemented for this platform yet.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#elif defined(__linux__)
  miniav_log(
      MINIAV_LOG_LEVEL_WARN,
      "Camera_GetSupportedFormats not implemented for this platform yet.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#else
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Camera_GetSupportedFormats: Platform not supported.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
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
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to allocate MiniAVCameraContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->base = miniav_context_base_create(
      NULL); // No specific user data for base context itself
  if (!ctx->base) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to create base context for camera.");
    miniav_free(ctx);
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;
#if defined(_WIN32)
  res = miniav_camera_context_platform_init_windows(ctx);
#elif defined(__APPLE__)
  // res = miniav_camera_context_platform_init_macos(ctx);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_CreateContext: macOS platform not fully implemented yet.");
#elif defined(__linux__)
  // res = miniav_camera_context_platform_init_linux(ctx);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "Camera_CreateContext: Linux platform not fully implemented yet.");
#else
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Camera_CreateContext: Platform not supported.");
#endif

  if (res != MINIAV_SUCCESS) {
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to initialize platform-specific camera context.");
    return res;
  }

  // Call the platform's main init after ops are set
  if (ctx->ops && ctx->ops->init_platform) {
    res = ctx->ops->init_platform(ctx);
    if (res != MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR, "Platform init_platform failed.");
      if (ctx->ops->destroy_platform) { // Attempt to clean up partially
                                        // initialized platform context
        ctx->ops->destroy_platform(ctx);
      }
      miniav_context_base_destroy(ctx->base);
      miniav_free(
          ctx->platform_ctx); // platform_ctx should be freed by
                              // destroy_platform or here if init failed early
      miniav_free(ctx);
      return res;
    }
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Platform ops or init_platform not set.");
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    return MINIAV_ERROR_UNKNOWN; // Should have been caught by platform_init
  }

  *context_handle = (MiniAVCameraContextHandle)ctx;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera context created successfully.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context_handle) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx) {
    return MINIAV_ERROR_INVALID_ARG;
  }

  if (ctx->is_running) {
    MiniAV_Camera_StopCapture(context_handle);
  }

  if (ctx->ops && ctx->ops->destroy_platform) {
    ctx->ops->destroy_platform(
        ctx); // Platform cleans up its specific resources (platform_ctx)
  }

  if (ctx->base) {
    miniav_context_base_destroy(ctx->base);
  }
  miniav_free(ctx);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera context destroyed.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Camera_Configure(MiniAVCameraContextHandle context_handle,
                        const char *device_id,
                        const MiniAVVideoFormatInfo *format) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx || !format) { // device_id can be NULL for default
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->ops || !ctx->ops->configure) {
    return MINIAV_ERROR_NOT_SUPPORTED;
  }
  if (ctx->is_running) {
    return MINIAV_ERROR_ALREADY_RUNNING;
  }

  // Store configuration
  ctx->configured_format = *format;
  if (device_id) {
    miniav_strlcpy(ctx->selected_device_id, device_id,
                   sizeof(ctx->selected_device_id));
  } else {
    memset(ctx->selected_device_id, 0,
           sizeof(ctx->selected_device_id)); // Indicate default
  }

  MiniAVResultCode res = ctx->ops->configure(ctx, device_id, format);
  if (res == MINIAV_SUCCESS) {
    ctx->is_configured = 1;
    float fps_approx = (format->frame_rate_denominator == 0)
                           ? 0.0f
                           : (float)format->frame_rate_numerator /
                                 format->frame_rate_denominator;
    miniav_log(
        MINIAV_LOG_LEVEL_INFO,
        "Camera configured: Device='%s', %ux%u @ %u/%u (%.2f) FPS, Format=%d",
        device_id ? device_id : "Default", format->width, format->height,
        format->frame_rate_numerator, format->frame_rate_denominator,
        fps_approx, format->pixel_format);
  } else {
    ctx->is_configured = 0;
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Camera configuration failed.");
  }
  return res;
}

MiniAVResultCode
MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context_handle,
                           MiniAVBufferCallback callback, void *user_data) {
  MiniAVCameraContext *ctx = (MiniAVCameraContext *)context_handle;
  if (!ctx || !callback) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_configured) {
    return MINIAV_ERROR_NOT_INITIALIZED; // Configure must be called first
  }
  if (ctx->is_running) {
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  if (!ctx->ops || !ctx->ops->start_capture) {
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  ctx->app_callback = callback;
  ctx->app_callback_user_data = user_data;

  MiniAVResultCode res = ctx->ops->start_capture(ctx);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = 1;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera capture started.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to start camera capture.");
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
    // Not an error to stop if not running, just do nothing.
    return MINIAV_SUCCESS;
  }
  if (!ctx->ops || !ctx->ops->stop_capture) {
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  MiniAVResultCode res = ctx->ops->stop_capture(ctx);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = 0;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Camera capture stopped.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to stop camera capture cleanly.");
  }
  // Clear callback info even if stop failed, to prevent further calls
  ctx->app_callback = NULL;
  ctx->app_callback_user_data = NULL;
  return res;
}