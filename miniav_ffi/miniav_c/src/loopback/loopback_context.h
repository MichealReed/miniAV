#ifndef MINIAV_LOOPBACK_CONTEXT_H
#define MINIAV_LOOPBACK_CONTEXT_H

#include "../../include/miniav.h"

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration
struct MiniAVLoopbackContext;

// --- Loopback Context Operations ---
// These are function pointers for platform-specific implementations.
typedef struct LoopbackContextInternalOps {
  MiniAVResultCode (*init_platform)(struct MiniAVLoopbackContext *ctx);
  MiniAVResultCode (*destroy_platform)(struct MiniAVLoopbackContext *ctx);

  // Enumerates loopback targets for the specific platform.
  // The common loopback_api.c will call this.
  MiniAVResultCode (*enumerate_targets_platform)(
      MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
      uint32_t *count);

  // Configure the loopback capture.
  // The common loopback_api.c will resolve target_device_id to target_info if
  // needed, or pass target_info directly from
  // MiniAV_Loopback_ConfigureWithTargetInfo.
  MiniAVResultCode (*configure_loopback)(
      struct MiniAVLoopbackContext *ctx,
      const MiniAVLoopbackTargetInfo *target_info, // Resolved target
      const char *target_device_id, // Original device_id for platforms that use
                                    // it directly
      const MiniAVAudioInfo *requested_format);

  MiniAVResultCode (*start_capture)(struct MiniAVLoopbackContext *ctx,
                                    MiniAVBufferCallback callback,
                                    void *user_data);
  MiniAVResultCode (*stop_capture)(struct MiniAVLoopbackContext *ctx);

  // Called via a common MiniAV_ReleaseBuffer, which would inspect the payload
  // type to delegate to the correct context's release_buffer op. The void* is
  // the platform-specific resource associated with the buffer that needs
  // releasing.
  MiniAVResultCode (*release_buffer_platform)(
      struct MiniAVLoopbackContext *ctx,
      void *native_buffer_payload_resource_ptr);

  MiniAVResultCode (*get_configured_format)(struct MiniAVLoopbackContext *ctx,
                                            MiniAVAudioInfo *format_out);

  // Optional: Platform-specific property handling
  // MiniAVResultCode (*get_property_platform)(struct MiniAVLoopbackContext
  // *ctx, const char* property_name, void* value, size_t* size);
  // MiniAVResultCode (*set_property_platform)(struct MiniAVLoopbackContext
  // *ctx, const char* property_name, const void* value, size_t size);

} LoopbackContextInternalOps;

// Represents a platform-specific process identifier.
// On Windows, this would be a DWORD (typically uint32_t).
// On POSIX systems, this would be pid_t (typically int).
typedef uint32_t MiniAVProcessId;

// Represents a platform-specific window handle.
// On Windows, this would be HWND (which is essentially void*).
// On X11 (Linux), this would be Window (typically unsigned long).
typedef void *MiniAVWindowHandle; // Add this definition

// --- Loopback Context Structure ---
typedef struct MiniAVLoopbackContext {
  void *
      platform_ctx; // Platform-specific context (e.g.,
                    // LoopbackPlatformContextWin, LoopbackPlatformContextPulse)
  const LoopbackContextInternalOps *ops;

  MiniAVBufferCallback app_callback;
  void *app_callback_user_data;

  bool is_configured; // True if configure_loopback was successful
  bool is_running;    // True if capture is active

  MiniAVAudioInfo configured_format; // The format confirmed by the backend
                                     // after configuration
  MiniAVLoopbackTargetInfo current_target_info; // Information about the current
                                                // capture target (resolved)
  char current_target_device_id
      [MINIAV_DEVICE_ID_MAX_LEN]; // Store the device_id used for configuration

  // Could add a mutex here if internal state needs protection,
  // though callbacks are typically invoked from a single capture thread per
  // context. miniav_mutex_t mutex;

} MiniAVLoopbackContext;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_LOOPBACK_CONTEXT_H
