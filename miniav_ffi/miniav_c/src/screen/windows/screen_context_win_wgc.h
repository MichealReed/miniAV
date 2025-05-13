#ifndef SCREEN_CONTEXT_WIN_WGC_H
#define SCREEN_CONTEXT_WIN_WGC_H

#include "../../../include/miniav_types.h" // For MiniAVResultCode, MiniAVDeviceInfo
#include "../../../include/miniav_buffer.h"  // For MiniAVBuffer, MiniAVPixelFormat
#include "../screen_context.h"             // For MiniAVScreenContext and ScreenContextInternalOps

#ifdef __cplusplus
extern "C" {
#endif

// Global ops struct for Windows Graphics Capture (WGC) implementation.
// This will be defined in the corresponding .c or .cpp file.
extern const ScreenContextInternalOps g_screen_ops_win_wgc;

// Platform initialization function for WGC.
// This function will be called to set up the WGC backend for a screen context.
MiniAVResultCode miniav_screen_context_platform_init_windows_wgc(MiniAVScreenContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // SCREEN_CONTEXT_WIN_WGC_H
