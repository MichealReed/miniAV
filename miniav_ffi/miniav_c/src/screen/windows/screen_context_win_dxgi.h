#ifndef SCREEN_CONTEXT_WIN_DXGI_H
#define SCREEN_CONTEXT_WIN_DXGI_H

#include "../../../include/miniav_types.h" // For MiniAVResultCode, MiniAVDeviceInfo
#include "../../../include/miniav_buffer.h"  // For MiniAVBuffer, MiniAVPixelFormat
#include "../screen_context.h"             // For MiniAVScreenContext and ScreenContextInternalOps

#ifdef __cplusplus
extern "C" {
#endif

// Global ops struct for Media Foundation implementation.
// Used by camera_api.c for static-like calls (enumerate, get_formats)
// and by miniav_camera_context_platform_init_windows to assign to context instance.
extern const ScreenContextInternalOps g_screen_ops_win_dxgi;

// Platform initialization function
MiniAVResultCode miniav_screen_context_platform_init_windows_dxgi(MiniAVScreenContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // SCREEN_CONTEXT_WIN_DXGI_H