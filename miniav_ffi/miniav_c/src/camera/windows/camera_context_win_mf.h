#ifndef CAMERA_CONTEXT_WIN_MF_H
#define CAMERA_CONTEXT_WIN_MF_H

#include "../camera_context.h" // For MiniAVCameraContext and CameraContextInternalOps

#ifdef __cplusplus
extern "C" {
#endif

// Global ops struct for Media Foundation implementation.
// Used by camera_api.c for static-like calls (enumerate, get_formats)
// and by miniav_camera_context_platform_init_windows to assign to context
// instance.
extern const CameraContextInternalOps g_camera_ops_win_mf;

// MiniAV_VideoBuffer_GetColor for a Media Foundation camera frame; 0 for any
// other buffer.
uint32_t miniav_mf_get_color(const MiniAVBuffer *buffer, uint32_t *matrix,
                             uint32_t *full_range);

// Initializes the Windows Media Foundation specific parts of the camera
// context. This function will set ctx->ops = &g_camera_ops_win_mf; and then
// call g_camera_ops_win_mf.init_platform(ctx);
MiniAVResultCode
miniav_camera_context_platform_init_windows_mf(MiniAVCameraContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // CAMERA_CONTEXT_WIN_MF_H
