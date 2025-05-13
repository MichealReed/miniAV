#include "../common/miniav_logging.h"
#include "../common/miniav_utils.h" // For miniav_calloc, miniav_free
#include "screen_context.h"

// Platform-specific includes. These would typically be guarded by #ifdefs
#ifdef _WIN32
#ifdef USE_DXGI 1
#include "windows/screen_context_win_dxgi.h"
#endif
#ifdef USE_WGC 1
#include "windows/screen_context_win_wgc.h"
#endif
#endif
// #ifdef __linux__
// #include "linux/screen_context_linux_x11.h"
// #endif
// #ifdef __APPLE__
// #include "macos/screen_context_macos_cg.h"
// #endif

MiniAVResultCode MiniAV_Screen_CreateContext(MiniAVScreenContext **ctx_out) {
  if (!ctx_out)
    return MINIAV_ERROR_INVALID_ARG;
  *ctx_out = NULL;

  MiniAVScreenContext *ctx =
      (MiniAVScreenContext *)miniav_calloc(1, sizeof(MiniAVScreenContext));
  if (!ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to allocate MiniAVScreenContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;

  // Platform detection and assignment of ops
#ifdef _WIN32
#ifdef USE_DXGI
  res = miniav_screen_context_platform_init_windows_dxgi(ctx);
#elif defined(USE_WGC)
  res = miniav_screen_context_platform_init_windows_wgc(ctx);
#else
  miniav_log(
      MINIAV_LOG_LEVEL_ERROR,
      "Screen capture not supported on this platform for CreateContext.");
  miniav_free(ctx);
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
#elif defined(__linux__)
  // res = miniav_screen_context_platform_init_linux_x11(ctx);
#elif defined(__APPLE__)
  // res = miniav_screen_context_platform_init_macos(ctx);
#else
  miniav_log(
      MINIAV_LOG_LEVEL_ERROR,
      "Screen capture not supported on this platform for CreateContext.");
  res = MINIAV_ERROR_NOT_SUPPORTED;
#endif

  if (res != MINIAV_SUCCESS) {
    miniav_free(
        ctx); // ctx->ops might not be set, so platform_ctx is not yet allocated
    return res;
  }

  // Ops should be set by the platform_init call above. Now call the platform's
  // main init.
  if (!ctx->ops || !ctx->ops->init_platform) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "Platform ops or init_platform not set after platform init call.");
    miniav_free(ctx);
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  res = ctx->ops->init_platform(ctx); // This initializes platform_ctx
  if (res != MINIAV_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "ctx->ops->init_platform failed with code %d.", res);
    // platform_ctx might be partially initialized, platform's destroy_platform
    // is not called here as it's part of the ops of a fully valid context.
    // However, init_platform itself should clean up its own allocations on
    // failure. We free platform_ctx here as a fallback if init_platform didn't.
    miniav_free(ctx->platform_ctx);
    miniav_free(ctx);
    return res;
  }

  ctx->is_running = false; // Initialize is_running state
  *ctx_out = ctx;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "MiniAV_Screen_CreateContext successful.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Screen_DestroyContext(MiniAVScreenContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;

  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Destroying screen context while capture "
                                      "is running. Attempting to stop.");
    MiniAV_Screen_StopCapture(ctx); // Attempt to gracefully stop
  }

  if (ctx->ops && ctx->ops->destroy_platform) {
    ctx->ops->destroy_platform(ctx); // This should free ctx->platform_ctx
  } else {
    // Fallback if destroy_platform wasn't called or set, or if ops is NULL
    // (though ops should be set if context is valid)
    miniav_free(ctx->platform_ctx);
  }

  miniav_free(ctx);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "MiniAV_Screen_DestroyContext successful.");
  return MINIAV_SUCCESS;
}

// Static-like enumeration, does not require a context
MiniAVResultCode
MiniAV_Screen_EnumerateDisplays(MiniAVDeviceInfo **displays_out,
                                uint32_t *count_out) {
  if (!displays_out || !count_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *displays_out = NULL;
  *count_out = 0;

#ifdef _WIN32
#ifdef USE_DXGI
  if (g_screen_ops_win_dxgi.enumerate_displays) {
    return g_screen_ops_win_dxgi.enumerate_displays(displays_out, count_out);
  }
#elif defined(USE_WGC)
  if (g_screen_ops_win_wgc.enumerate_displays) {
    return g_screen_ops_win_wgc.enumerate_displays(displays_out, count_out);
  }
#endif
  // Potentially try other backends if DXGI is not available or fails
#elif defined(__linux__)
  // if (g_screen_ops_linux_x11.enumerate_displays) { ... }
#elif defined(__APPLE__)
  // if (g_screen_ops_macos_cg.enumerate_displays) { ... }
#else
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Screen_EnumerateDisplays: Platform not supported.");
#endif
  return MINIAV_ERROR_NOT_SUPPORTED;
}

// Static-like enumeration, does not require a context
MiniAVResultCode MiniAV_Screen_EnumerateWindows(MiniAVDeviceInfo **windows_out,
                                                uint32_t *count_out) {
  if (!windows_out || !count_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *windows_out = NULL;
  *count_out = 0;

#ifdef _WIN32
#ifdef USE_DXGI
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "DXGI: EnumerateWindows is not supported by DXGI backend.");
  return MINIAV_ERROR_NOT_SUPPORTED;
#elif defined(USE_WGC)
  if (g_screen_ops_win_wgc.enumerate_windows) {
    return g_screen_ops_win_wgc.enumerate_windows(windows_out, count_out);
  }
#endif
#else
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Screen_EnumerateWindows: Platform not supported.");
#endif
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_ConfigureDisplay(MiniAVScreenContext *ctx, const char *display_id,
                               const MiniAVVideoFormatInfo *format,
                               bool capture_audio) {
  if (!ctx || !ctx->ops || !ctx->ops->configure_display || !display_id ||
      !format) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Cannot configure display while capture is running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  ctx->capture_target_type = MINIAV_CAPTURE_TYPE_DISPLAY;
  ctx->capture_audio_requested = capture_audio;
  return ctx->ops->configure_display(ctx, display_id, format);
}

MiniAVResultCode
MiniAV_Screen_ConfigureWindow(MiniAVScreenContext *ctx, const char *window_id,
                              const MiniAVVideoFormatInfo *format,
                              bool capture_audio) {
  if (!ctx || !ctx->ops || !ctx->ops->configure_window || !window_id ||
      !format) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Cannot configure window while capture is running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  ctx->capture_target_type = MINIAV_CAPTURE_TYPE_WINDOW;
  ctx->capture_audio_requested = capture_audio;
  return ctx->ops->configure_window(ctx, window_id, format);
}

MiniAVResultCode MiniAV_Screen_ConfigureRegion(
    MiniAVScreenContext *ctx, const char *target_id, int x, int y, int width,
    int height, const MiniAVVideoFormatInfo *format, bool capture_audio) {
  if (!ctx || !ctx->ops || !ctx->ops->configure_region || !target_id ||
      !format || width <= 0 || height <= 0) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Cannot configure region while capture is running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  ctx->capture_target_type = MINIAV_CAPTURE_TYPE_REGION;
  ctx->capture_audio_requested = capture_audio;
  return ctx->ops->configure_region(ctx, target_id, x, y, width, height,
                                    format);
}

MiniAVResultCode MiniAV_Screen_StartCapture(MiniAVScreenContext *ctx,
                                            MiniAVBufferCallback callback,
                                            void *user_data) {
  if (!ctx || !ctx->ops || !ctx->ops->start_capture || !callback) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Screen capture already running.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  // Check if configured (simplistic check, backend might need more)
  if (ctx->configured_format.width == 0 || ctx->configured_format.height == 0) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "Screen capture not configured. Call a configure function first.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  ctx->app_callback = callback;
  ctx->app_callback_user_data = user_data;

  MiniAVResultCode res = ctx->ops->start_capture(ctx, callback, user_data);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = true;
  } else {
    ctx->app_callback = NULL;
    ctx->app_callback_user_data = NULL;
  }
  return res;
}

MiniAVResultCode MiniAV_Screen_StopCapture(MiniAVScreenContext *ctx) {
  if (!ctx || !ctx->ops || !ctx->ops->stop_capture) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "Screen capture not running or already stopped.");
    return MINIAV_SUCCESS;
  }

  MiniAVResultCode res = ctx->ops->stop_capture(ctx);
  // Always update state
  ctx->is_running = false;
  // Consider if app_callback should be cleared here or if it's okay to leave
  // for potential restart with same callback. For now, let's not clear it.
  return res;
}

MiniAVResultCode
MiniAV_Screen_GetConfiguredFormat(MiniAVScreenContext *ctx,
                                  MiniAVVideoFormatInfo *format_out) {
  if (!ctx || !format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->configured_format.width == 0 || ctx->configured_format.height == 0) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "Screen context not configured or configuration resulted in "
               "zero dimensions.");
    memset(format_out, 0, sizeof(MiniAVVideoFormatInfo));
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  *format_out = ctx->configured_format;
  return MINIAV_SUCCESS;
}
