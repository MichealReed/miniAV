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

// Structure defining the operations for a platform-specific camera implementation
typedef struct CameraContextInternalOps {
    // Initializes platform-specific parts of the context. platform_ctx will be stored in MiniAVCameraContext.
    MiniAVResultCode (*init_platform)(MiniAVCameraContext* ctx);
    // Destroys platform-specific parts of the context.
    MiniAVResultCode (*destroy_platform)(MiniAVCameraContext* ctx);
    // Configures the camera device and format.
    MiniAVResultCode (*configure)(MiniAVCameraContext* ctx, const char* device_id, const MiniAVVideoFormatInfo* format);
    // Starts the capture stream.
    MiniAVResultCode (*start_capture)(MiniAVCameraContext* ctx);
    // Stops the capture stream.
    MiniAVResultCode (*stop_capture)(MiniAVCameraContext* ctx);
    // Releases a specific buffer previously provided by the platform.
    // native_buffer_payload is the MiniAVNativeBufferInternalPayload->native_resource_ptr.
    MiniAVResultCode (*release_buffer)(MiniAVCameraContext* ctx, void* native_buffer_payload);

    // Static-like operations (don't take a full MiniAVCameraContext but might need some platform init)
    MiniAVResultCode (*enumerate_devices)(MiniAVDeviceInfo** devices, uint32_t* count);
    MiniAVResultCode (*get_supported_formats)(const char* device_id, MiniAVVideoFormatInfo** formats, uint32_t* count);

} CameraContextInternalOps;

// Main camera context structure
struct MiniAVCameraContext {
    MiniAVContextBase* base;                // Common base context utilities (logging, etc.)
    const CameraContextInternalOps* ops;    // Platform-specific operations
    void* platform_ctx;                     // Opaque handle to platform-specific context data (e.g., MF specific structs)

    MiniAVBufferCallback app_callback;      // User-provided callback for new buffers
    void* app_callback_user_data;           // User data for their callback

    int is_configured;
    int is_running;

    MiniAVVideoFormatInfo configured_format; // Store the currently configured format
    char selected_device_id[MINIAV_DEVICE_ID_MAX_LEN]; // Store the ID of the selected device

    // Any other common state for camera contexts
};

// Platform-specific initialization functions (to be implemented in platform files)
// These will set up ctx->ops and call ops->init_platform
#if defined(_WIN32)
MiniAVResultCode miniav_camera_context_platform_init_windows(MiniAVCameraContext* ctx);
#elif defined(__APPLE__)
// MiniAVResultCode miniav_camera_context_platform_init_macos(MiniAVCameraContext* ctx);
#elif defined(__linux__)
// MiniAVResultCode miniav_camera_context_platform_init_linux(MiniAVCameraContext* ctx);
#else
// Potentially a fallback or error
#endif


#ifdef __cplusplus
}
#endif

#endif // CAMERA_CONTEXT_H
