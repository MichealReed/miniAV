// #include "../common/miniav_logging.h"
// #include "../common/miniav_utils.h" // For miniav_calloc, miniav_free
// #include "screen_context.h"

// // Platform-specific includes. These would typically be guarded by #ifdefs
// // For now, assuming Windows DXGI is one of the backends.
// #ifdef _WIN32
// #include "windows/screen_context_win_dxgi.h"
// // #include "windows/screen_context_win_gdi.h" // If you add a GDI backend
// #endif
// // #ifdef __linux__
// // #include "linux/screen_context_linux_x11.h"
// // #endif
// // #ifdef __APPLE__
// // #include "macos/screen_context_macos_cg.h"
// // #endif

// MiniAVResultCode MiniAV_Screen_CreateContext(MiniAVScreenContext **ctx_out) {
//   if (!ctx_out)
//     return MINIAV_ERROR_INVALID_ARG;
//   *ctx_out = NULL;

//   MiniAVScreenContext *ctx =
//       (MiniAVScreenContext *)miniav_calloc(1, sizeof(MiniAVScreenContext));
//   if (!ctx) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "Failed to allocate MiniAVScreenContext.");
//     return MINIAV_ERROR_OUT_OF_MEMORY;
//   }

//   MiniAVResultCode res = MINIAV_ERROR_NOT_SUPPORTED;

//   // Platform detection and initialization
// #ifdef _WIN32
//   // Attempt DXGI first, then potentially GDI as a fallback or alternative
//   res = miniav_screen_context_platform_init_windows_dxgi(ctx);
//   if (res != MINIAV_SUCCESS) {
//     miniav_log(MINIAV_LOG_LEVEL_WARN,
//                "DXGI screen context init failed (code %d). Trying GDI...", res);
//     // res = miniav_screen_context_platform_init_windows_gdi(ctx); // Example
//     // fallback if (res != MINIAV_SUCCESS) {
//     //    miniav_log(MINIAV_LOG_LEVEL_ERROR, "GDI screen context init also
//     //    failed (code %d).", res);
//     // }
//   }
// #elif defined(__linux__)
//   // res = miniav_screen_context_platform_init_linux_x11(ctx);
// #elif defined(__APPLE__)
//   // res = miniav_screen_context_platform_init_macos(ctx);
// #else
//   miniav_log(MINIAV_LOG_LEVEL_ERROR,
//              "Screen capture not supported on this platform.");
//   res = MINIAV_ERROR_NOT_SUPPORTED;
// #endif

//   if (res != MINIAV_SUCCESS) {
//     miniav_free(ctx);
//     return res;
//   }

//   if (!ctx->ops || !ctx->ops->init_platform) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "Platform ops or init_platform not set after platform init.");
//     miniav_free(ctx);
//     return MINIAV_ERROR_NOT_INITIALIZED; // Or NOT_INITIALIZED
//   }

//   res = ctx->ops->init_platform(ctx);
//   if (res != MINIAV_SUCCESS) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "ctx->ops->init_platform failed with code %d.", res);
//     // No platform-specific destroy needed here as platform_ctx might not be
//     // fully up.
//     miniav_free(ctx->platform_ctx); // Free what might have been allocated by
//                                     // the platform_init_...
//     miniav_free(ctx);
//     return res;
//   }

//   ctx->is_running = false;
//   *ctx_out = ctx;
//   miniav_log(MINIAV_LOG_LEVEL_INFO, "MiniAV_Screen_CreateContext successful.");
//   return MINIAV_SUCCESS;
// }

// MiniAVResultCode MiniAV_Screen_DestroyContext(MiniAVScreenContext *ctx) {
//   if (!ctx)
//     return MINIAV_ERROR_INVALID_ARG;

//   if (ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_WARN, "Destroying screen context while capture "
//                                       "is running. Attempting to stop.");
//     MiniAV_Screen_StopCapture(ctx); // Attempt to gracefully stop
//   }

//   if (ctx->ops && ctx->ops->destroy_platform) {
//     ctx->ops->destroy_platform(ctx); // This should free ctx->platform_ctx
//   } else {
//     miniav_free(
//         ctx->platform_ctx); // Fallback if destroy_platform wasn't called or set
//   }

//   miniav_free(ctx);
//   miniav_log(MINIAV_LOG_LEVEL_INFO, "MiniAV_Screen_DestroyContext successful.");
//   return MINIAV_SUCCESS;
// }

// MiniAVResultCode
// MiniAV_Screen_EnumerateDisplays(MiniAVScreenContext *ctx,
//                                 MiniAVDeviceInfo **displays_out,
//                                 uint32_t *count_out) {
//   if (!ctx || !ctx->ops || !ctx->ops->enumerate_displays || !displays_out ||
//       !count_out) {
//     if (displays_out)
//       *displays_out = NULL;
//     if (count_out)
//       *count_out = 0;
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   return ctx->ops->enumerate_displays(displays_out, count_out);
// }

// MiniAVResultCode MiniAV_Screen_EnumerateWindows(MiniAVScreenContext *ctx,
//                                                 MiniAVDeviceInfo **windows_out,
//                                                 uint32_t *count_out) {
//   if (!ctx || !ctx->ops || !ctx->ops->enumerate_windows || !windows_out ||
//       !count_out) {
//     if (windows_out)
//       *windows_out = NULL;
//     if (count_out)
//       *count_out = 0;
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   return ctx->ops->enumerate_windows(windows_out, count_out);
// }

// MiniAVResultCode
// MiniAV_Screen_ConfigureDisplay(MiniAVScreenContext *ctx, const char *display_id,
//                                const MiniAVVideoFormatInfo *format) {
//   if (!ctx || !ctx->ops || !ctx->ops->configure_display || !display_id ||
//       !format) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "Cannot configure display while capture is running.");
//     return MINIAV_ERROR_ALREADY_RUNNING;
//   }
//   ctx->capture_target_type = MINIAV_CAPTURE_TYPE_DISPLAY;
//   // The backend will update ctx->configured_format with actual values if
//   // different
//   MiniAVResultCode res = ctx->ops->configure_display(ctx, display_id, format);
//   if (res == MINIAV_SUCCESS) {
//     // Backend should have updated ctx->configured_format with actuals
//   }
//   return res;
// }

// MiniAVResultCode
// MiniAV_Screen_ConfigureWindow(MiniAVScreenContext *ctx, const char *window_id,
//                               const MiniAVVideoFormatInfo *format) {
//   if (!ctx || !ctx->ops || !ctx->ops->configure_window || !window_id ||
//       !format) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "Cannot configure window while capture is running.");
//     return MINIAV_ERROR_ALREADY_RUNNING;
//   }
//   ctx->capture_target_type = MINIAV_CAPTURE_TYPE_WINDOW;
//   return ctx->ops->configure_window(ctx, window_id, format);
// }

// MiniAVResultCode
// MiniAV_Screen_ConfigureRegion(MiniAVScreenContext *ctx, const char *target_id,
//                               int x, int y, int width, int height,
//                               const MiniAVVideoFormatInfo *format) {
//   if (!ctx || !ctx->ops || !ctx->ops->configure_region || !target_id ||
//       !format || width <= 0 || height <= 0) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_ERROR,
//                "Cannot configure region while capture is running.");
//     return MINIAV_ERROR_ALREADY_RUNNING;
//   }
//   ctx->capture_target_type = MINIAV_CAPTURE_TYPE_REGION;
//   return ctx->ops->configure_region(ctx, target_id, x, y, width, height,
//                                     format);
// }

// MiniAVResultCode MiniAV_Screen_StartCapture(MiniAVScreenContext *ctx,
//                                             MiniAVBufferCallback callback,
//                                             void *user_data) {
//   if (!ctx || !ctx->ops || !ctx->ops->start_capture || !callback) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_WARN, "Screen capture already running.");
//     return MINIAV_ERROR_ALREADY_RUNNING;
//   }
//   // Check if configured (simplistic check, backend might need more)
//   if (ctx->configured_format.width == 0 || ctx->configured_format.height == 0) {
//     miniav_log(
//         MINIAV_LOG_LEVEL_ERROR,
//         "Screen capture not configured. Call a configure function first.");
//     return MINIAV_ERROR_NOT_INITIALIZED; // Or INVALID_STATE
//   }

//   ctx->app_callback = callback;
//   ctx->app_callback_user_data = user_data;

//   MiniAVResultCode res = ctx->ops->start_capture(ctx, callback, user_data);
//   if (res == MINIAV_SUCCESS) {
//     ctx->is_running = false;
//   } else {
//     ctx->app_callback = NULL;
//     ctx->app_callback_user_data = NULL;
//   }
//   return res;
// }

// MiniAVResultCode MiniAV_Screen_StopCapture(MiniAVScreenContext *ctx) {
//   if (!ctx || !ctx->ops || !ctx->ops->stop_capture) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (!ctx->is_running) {
//     miniav_log(MINIAV_LOG_LEVEL_WARN,
//                "Screen capture not running or already stopped.");
//     return MINIAV_SUCCESS; // Or INVALID_OPERATION
//   }

//   MiniAVResultCode res = ctx->ops->stop_capture(ctx);
//   // Always update state even if backend reports an issue, to allow re-start
//   // attempts.
//   ctx->is_running = false;
//   // ctx->app_callback = NULL; // Keep callback for potential restart? Or clear?
//   // ctx->app_callback_user_data = NULL;
//   return res;
// }

// MiniAVResultCode
// MiniAV_Screen_GetConfiguredFormat(MiniAVScreenContext *ctx,
//                                   MiniAVVideoFormatInfo *format_out) {
//   if (!ctx || !format_out) {
//     return MINIAV_ERROR_INVALID_ARG;
//   }
//   if (ctx->configured_format.width == 0 || ctx->configured_format.height == 0) {
//     miniav_log(MINIAV_LOG_LEVEL_WARN,
//                "Screen context not configured or configuration resulted in "
//                "zero dimensions.");
//     // Optionally clear format_out or return an error indicating not configured
//     memset(format_out, 0, sizeof(MiniAVVideoFormatInfo));
//     return MINIAV_ERROR_NOT_INITIALIZED; // Or INVALID_STATE
//   }
//   *format_out = ctx->configured_format;
//   return MINIAV_SUCCESS;
// }

// // Note: MiniAV_ReleaseBuffer is a general API function.
// // The screen backend's release_buffer op is called by the common
// // MiniAV_ReleaseBuffer after inspecting the MiniAVNativeBufferInternalPayload.