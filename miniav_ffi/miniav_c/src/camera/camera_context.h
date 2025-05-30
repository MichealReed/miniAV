#ifndef CAMERA_CONTEXT_H
#define CAMERA_CONTEXT_H

#include "../../include/miniav_types.h"
#include "../../include/miniav_buffer.h"
#include "../../include/miniav_capture.h" // For MiniAVBufferCallback
#include "../common/miniav_context_base.h"

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration of the main context structure
typedef struct MiniAVCameraContext MiniAVCameraContext;

// Defines the operations for a platform-specific camera implementation
typedef struct CameraContextInternalOps {
    MiniAVResultCode (*init_platform)(MiniAVCameraContext *ctx);
    MiniAVResultCode (*destroy_platform)(MiniAVCameraContext *ctx);
    MiniAVResultCode (*enumerate_devices)(MiniAVDeviceInfo **devices_out, uint32_t *count_out);
    MiniAVResultCode (*get_supported_formats)(const char *device_id, MiniAVVideoInfo **formats_out, uint32_t *count_out);
    MiniAVResultCode (*get_default_format)(const char *device_id, MiniAVVideoInfo *format_out);  // Add this line
    MiniAVResultCode (*configure)(MiniAVCameraContext *ctx, const char *device_id, const MiniAVVideoInfo *format);
    MiniAVResultCode (*start_capture)(MiniAVCameraContext *ctx);
    MiniAVResultCode (*stop_capture)(MiniAVCameraContext *ctx);
    MiniAVResultCode (*release_buffer)(MiniAVCameraContext *ctx, void *internal_handle_ptr);
    MiniAVResultCode (*get_configured_video_format)(MiniAVCameraContext *ctx, MiniAVVideoInfo *format_out);
} CameraContextInternalOps;

// --- Camera Backend Entry Structure ---
// Used in the backend table for dynamic selection.
typedef struct MiniAVCameraBackend {
    const char* name;
    const CameraContextInternalOps* ops; // Direct pointer to the ops table for this backend
    // Initial, minimal platform init for selection.
    // This function is responsible for setting ctx->ops and potentially ctx->platform_ctx.
    MiniAVResultCode (*platform_init_for_selection)(MiniAVCameraContext* ctx);
} MiniAVCameraBackend;


// Main camera context structure
struct MiniAVCameraContext {
    MiniAVContextBase* base;                // Common base context utilities (logging, etc.)
    const CameraContextInternalOps* ops;    // Platform-specific operations
    void* platform_ctx;                     // Opaque handle to platform-specific context data (e.g., MF specific structs)

    MiniAVBufferCallback app_callback;      // User-provided callback for new buffers
    void* app_callback_user_data;           // User data for their callback

    int is_configured;
    int is_running;

    MiniAVVideoInfo configured_video_format; // Store the currently configured format
    char selected_device_id[MINIAV_DEVICE_ID_MAX_LEN]; // Store the ID of the selected device
};

// Platform-specific initialization functions
// These will set up ctx->ops and call ops->init_platform
#if defined(_WIN32)
extern MiniAVResultCode miniav_camera_context_platform_init_windows_mf(MiniAVCameraContext* ctx);
extern const CameraContextInternalOps g_camera_ops_win_mf;
#include "windows/camera_context_win_mf.h"
#elif defined(__APPLE__)
#include "macos/camera_context_macos_avf.h"
extern const CameraContextInternalOps g_camera_ops_macos_avf;
extern MiniAVResultCode
miniav_camera_context_platform_init_macos_avf(MiniAVCameraContext* ctx);
#elif defined(__linux__)
#include "linux/camera_context_linux_pipewire.h" // You will need to create this header
extern const CameraContextInternalOps
    g_camera_ops_pipewire; // To be defined in your pipewire .c file
extern MiniAVResultCode miniav_camera_context_platform_init_linux_pipewire(
    MiniAVCameraContext *ctx); // To be defined in your pipewire .c file
#endif


#ifdef __cplusplus
}
#endif

#endif // CAMERA_CONTEXT_H