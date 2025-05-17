#ifndef CAMERA_CONTEXT_PIPEWIRE_H
#define CAMERA_CONTEXT_PIPEWIRE_H

#include "../camera_context.h" // For MiniAVCameraContext and CameraContextInternalOps

#ifdef __cplusplus
extern "C" {
#endif

// Global ops struct for PipeWire implementation.
extern const CameraContextInternalOps g_camera_ops_pipewire;

// Initializes the PipeWire specific parts of the camera context.
MiniAVResultCode
miniav_camera_context_platform_init_linux_pipewire(MiniAVCameraContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // CAMERA_CONTEXT_PIPEWIRE_H