#ifndef CAMERA_CONTEXT_MACOS_AVF_H
#define CAMERA_CONTEXT_MACOS_AVF_H

#include "../camera_context.h" // Provides MiniAVCameraContext and CameraContextInternalOps

#ifdef __cplusplus
extern "C" {
#endif

// Declare the AVFoundation-specific operations table
extern const CameraContextInternalOps g_camera_ops_macos_avf;

// Declare the platform initialization function for AVFoundation
// This function will be called by camera_api.c to select and do minimal setup for this backend.
MiniAVResultCode miniav_camera_context_platform_init_macos_avf(MiniAVCameraContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // CAMERA_CONTEXT_MACOS_AVF_H