#include "../common/miniav_logging.h"
#include "../common/miniav_utils.h" // For miniav_calloc, miniav_free, miniav_strdup
#include "loopback_context.h"
#include <string.h> // For memset, strncpy
#include <stdio.h>  // For sscanf

// --- Platform-Specific Ops Declarations ---
// These functions and ops tables need to be defined in their respective
// platform files e.g., loopback_context_win.c, loopback_context_linux_pulse.c,
// etc.

#ifdef _WIN32
extern const LoopbackContextInternalOps *miniav_loopback_get_win_ops(void);
extern MiniAVResultCode miniav_loopback_enumerate_targets_win(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
    uint32_t *count);
#elif __APPLE__
extern const LoopbackContextInternalOps *miniav_loopback_get_macos_ops(void);
extern MiniAVResultCode miniav_loopback_enumerate_targets_macos(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
    uint32_t *count);
#elif __linux__
// For Linux, you might have multiple backends (Pulse, PipeWire)
// This selection logic would be more complex, potentially based on availability
// or a global setting. For simplicity here, we'll assume a primary one or a
// function that decides.
extern const LoopbackContextInternalOps *miniav_loopback_get_linux_ops(
    void); // This function would decide Pulse/PipeWire
extern MiniAVResultCode miniav_loopback_enumerate_targets_linux(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
    uint32_t *count);
#else
// Fallback or error for unsupported platforms
const LoopbackContextInternalOps *miniav_loopback_get_unsupported_ops(void) {
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "Loopback audio is not supported on this platform.");
  return NULL;
}
MiniAVResultCode miniav_loopback_enumerate_targets_unsupported(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
    uint32_t *count) {
  MINIAV_UNUSED(target_type_filter);
  MINIAV_UNUSED(targets);
  MINIAV_UNUSED(count);
  miniav_log(
      MINIAV_LOG_LEVEL_ERROR,
      "Loopback audio target enumeration is not supported on this platform.");
  return MINIAV_ERROR_NOT_SUPPORTED;
}
#endif

MiniAVResultCode
MiniAV_Loopback_EnumerateTargets(MiniAVLoopbackTargetType target_type_filter,
                                 MiniAVDeviceInfo **targets, uint32_t *count) {
  if (!targets || !count) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  *targets = NULL;
  *count = 0;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "Enumerating loopback audio targets with filter: %d",
             target_type_filter);

#ifdef _WIN32
  return miniav_loopback_enumerate_targets_win(target_type_filter, targets,
                                               count);
#elif __APPLE__
  return miniav_loopback_enumerate_targets_macos(target_type_filter, targets,
                                                 count);
#elif __linux__
  return miniav_loopback_enumerate_targets_linux(target_type_filter, targets,
                                                 count);
#else
  return miniav_loopback_enumerate_targets_unsupported(target_type_filter,
                                                       targets, count);
#endif
}

MiniAVResultCode
MiniAV_Loopback_CreateContext(MiniAVLoopbackContextHandle *context_handle) {
  if (!context_handle) {
    return MINIAV_ERROR_INVALID_ARG;
  }

  *context_handle = NULL;
  MiniAVLoopbackContext *ctx =
      (MiniAVLoopbackContext *)miniav_calloc(1, sizeof(MiniAVLoopbackContext));
  if (!ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to allocate memory for LoopbackContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

#ifdef _WIN32
  ctx->ops = miniav_loopback_get_win_ops();
#elif __APPLE__
  ctx->ops = miniav_loopback_get_macos_ops();
#elif __linux__
  ctx->ops = miniav_loopback_get_linux_ops();
#else
  ctx->ops = miniav_loopback_get_unsupported_ops();
#endif

  if (!ctx->ops || !ctx->ops->init_platform) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Loopback audio not supported or ops "
                                       "table is invalid for this platform.");
    miniav_free(ctx);
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  MiniAVResultCode res = ctx->ops->init_platform(ctx);
  if (res != MINIAV_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Platform-specific loopback context initialization failed.");
    miniav_free(ctx); // platform_ctx should be cleaned by init_platform on
                      // failure or by destroy_platform
    return res;
  }

  ctx->is_configured = false;
  ctx->is_running = false;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "LoopbackContext created successfully.");
  *context_handle = (MiniAVLoopbackContextHandle)ctx;
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Loopback_DestroyContext(MiniAVLoopbackContextHandle context_handle) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }

  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Loopback capture is running during "
                                      "DestroyContext. Attempting to stop.");
    if (ctx->ops && ctx->ops->stop_capture) {
      ctx->ops->stop_capture(ctx);
    }
    ctx->is_running = false;
  }

  if (ctx->ops && ctx->ops->destroy_platform) {
    ctx->ops->destroy_platform(ctx);
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "LoopbackContext destroyed.");
  miniav_free(ctx);
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Loopback_Configure(
    MiniAVLoopbackContextHandle context_handle,
    const char *target_device_id_str, // Renamed for clarity
    const MiniAVAudioInfo *format) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx || !ctx->ops || !ctx->ops->configure_loopback) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }
  if (!format) { // target_device_id_str can be NULL for system default
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Cannot configure loopback while capture is running.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  MiniAVLoopbackTargetInfo target_info_struct;
  const MiniAVLoopbackTargetInfo *target_info_to_pass = NULL;
  const char *device_id_to_pass = NULL;
  MiniAVResultCode res;

  if (target_device_id_str) {
    if (strncmp(target_device_id_str, "hwnd:", 5) == 0) {
      memset(&target_info_struct, 0, sizeof(MiniAVLoopbackTargetInfo));
      target_info_struct.type = MINIAV_LOOPBACK_TARGET_WINDOW;
      void *temp_hwnd_ptr = NULL;
      // Ensure sscanf_s for safety on Windows if possible, or careful buffer
      // handling. %p expects void* argument. MiniAVWindowHandle is void*.
      if (sscanf(target_device_id_str + 5, "%p", &temp_hwnd_ptr) == 1) {
        target_info_struct.TARGETHANDLE.window_handle =
            (MiniAVWindowHandle)temp_hwnd_ptr;
        target_info_to_pass = &target_info_struct;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "API Configure: Parsed HWND: %p from ID: %s",
                   target_info_struct.TARGETHANDLE.window_handle,
                   target_device_id_str);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "API Configure: Failed to parse HWND from ID: %s",
                   target_device_id_str);
        return MINIAV_ERROR_INVALID_ARG;
      }
    } else if (strncmp(target_device_id_str, "pid:", 4) == 0) {
      memset(&target_info_struct, 0, sizeof(MiniAVLoopbackTargetInfo));
      target_info_struct.type = MINIAV_LOOPBACK_TARGET_PROCESS;
      // MiniAVProcessId is uint32_t. DWORD on Windows is unsigned long
      // (typically 32-bit).
      if (sscanf(target_device_id_str + 4, "%lu",
                 &target_info_struct.TARGETHANDLE.process_id) == 1) {
        target_info_to_pass = &target_info_struct;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "API Configure: Parsed PID: %lu from ID: %s",
                   target_info_struct.TARGETHANDLE.process_id,
                   target_device_id_str);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "API Configure: Failed to parse PID from ID: %s",
                   target_device_id_str);
        return MINIAV_ERROR_INVALID_ARG;
      }
    } else {
      // Assumed to be a system audio device ID string
      device_id_to_pass = target_device_id_str;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "API Configure: Using system device ID: %s",
                 target_device_id_str);
    }
  } else {
    // NULL target_device_id_str means system default audio device
    device_id_to_pass =
        NULL; // Platform layer interprets NULL string as default system device
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "API Configure: Using default system audio device "
               "(target_device_id_str is NULL)");
  }

  res = ctx->ops->configure_loopback(ctx, target_info_to_pass,
                                     device_id_to_pass, format);

  if (res == MINIAV_SUCCESS) {
    ctx->is_configured = true;
    if (target_info_to_pass) { // Configured with hwnd: or pid:
      ctx->current_target_info = *target_info_to_pass;
      memset(ctx->current_target_device_id, 0, MINIAV_DEVICE_ID_MAX_LEN);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Loopback configured for parsed target type: %d",
                 ctx->current_target_info.type);
    } else { // Configured with device string (or NULL for default system)
      if (device_id_to_pass) {
        strncpy(ctx->current_target_device_id, device_id_to_pass,
                MINIAV_DEVICE_ID_MAX_LEN - 1);
        ctx->current_target_device_id[MINIAV_DEVICE_ID_MAX_LEN - 1] = '\0';
      } else {
        memset(ctx->current_target_device_id, 0,
               MINIAV_DEVICE_ID_MAX_LEN); // System default
      }
      // When using device_id_to_pass, current_target_info should reflect system
      // audio.
      ctx->current_target_info.type = MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO;
      ctx->current_target_info.TARGETHANDLE.process_id =
          0; // Clear specific handles
      ctx->current_target_info.TARGETHANDLE.window_handle = NULL;

      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "Loopback configured for device_id: %s",
                 device_id_to_pass ? device_id_to_pass : "(system default)");
    }
  } else {
    ctx->is_configured = false;
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR, "Loopback configuration failed for input: %s",
        target_device_id_str ? target_device_id_str : "(system default)");
  }
  return res;
}

MiniAVResultCode MiniAV_Loopback_ConfigureWithTargetInfo(
    MiniAVLoopbackContextHandle context_handle,
    const MiniAVLoopbackTargetInfo *target_info,
    const MiniAVAudioInfo *format) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx || !ctx->ops || !ctx->ops->configure_loopback) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }
  if (!target_info || !format) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Cannot configure loopback while capture is running.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  // For this version, target_device_id is NULL as we're using explicit
  // target_info.
  MiniAVResultCode res =
      ctx->ops->configure_loopback(ctx, target_info, NULL, format);
  if (res == MINIAV_SUCCESS) {
    ctx->is_configured = true;
    ctx->current_target_info = *target_info; // Store the provided target info
    memset(ctx->current_target_device_id, 0,
           MINIAV_DEVICE_ID_MAX_LEN); // Clear device_id as we used target_info
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "Loopback configured with explicit TargetInfo (type: %d).",
               target_info->type);
  } else {
    ctx->is_configured = false;
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "Loopback configuration failed with explicit TargetInfo (type: %d).",
        target_info->type);
  }
  return res;
}

MiniAVResultCode
MiniAV_Loopback_StartCapture(MiniAVLoopbackContextHandle context_handle,
                             MiniAVBufferCallback callback, void *user_data) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx || !ctx->ops || !ctx->ops->start_capture) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }
  if (!callback) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Loopback must be configured before starting capture.");
    return MINIAV_ERROR_NOT_INITIALIZED; // Or a more specific "not configured"
                                         // error
  }
  if (ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Loopback capture is already running.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  ctx->app_callback = callback;
  ctx->app_callback_user_data = user_data;

  MiniAVResultCode res = ctx->ops->start_capture(ctx, callback, user_data);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = true;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Loopback capture started.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to start loopback capture.");
  }
  return res;
}

MiniAVResultCode
MiniAV_Loopback_StopCapture(MiniAVLoopbackContextHandle context_handle) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx || !ctx->ops || !ctx->ops->stop_capture) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }
  if (!ctx->is_running) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "Loopback capture is not running.");
    return MINIAV_SUCCESS;
  }

  MiniAVResultCode res = ctx->ops->stop_capture(ctx);
  if (res == MINIAV_SUCCESS) {
    ctx->is_running = false;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Loopback capture stopped.");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to stop loopback capture cleanly.");
  }
  // Reset callback pointers even if stop failed, to prevent further calls
  ctx->app_callback = NULL;
  ctx->app_callback_user_data = NULL;
  return res;
}

MiniAVResultCode
MiniAV_Loopback_GetConfiguredFormat(MiniAVLoopbackContextHandle context_handle,
                                    MiniAVAudioInfo *format_out) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)context_handle;
  if (!ctx) {
    return MINIAV_ERROR_INVALID_HANDLE;
  }
  if (!format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "Loopback not configured, format may be invalid.");
    // Optionally return an error or just provide zeroed/default format
    // return MINIAV_ERROR_NOT_INITIALIZED;
  }

  *format_out = ctx->configured_format; // Assumes configured_format is updated
                                        // by platform's configure_loopback
  return MINIAV_SUCCESS;
}
