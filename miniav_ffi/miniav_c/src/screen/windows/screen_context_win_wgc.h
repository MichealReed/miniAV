#ifndef SCREEN_CONTEXT_WIN_WGC_H
#define SCREEN_CONTEXT_WIN_WGC_H

#include "../../../include/miniav_types.h" // For MiniAVResultCode, MiniAVDeviceInfo
#include "../../../include/miniav_buffer.h"  // For MiniAVBuffer, MiniAVPixelFormat
#include "../screen_context.h"             // For MiniAVScreenContext and ScreenContextInternalOps
#include "../../../include/miniav_screen_windows_strict.h"

#ifdef __cplusplus
extern "C" {
#endif

// Global ops struct for Windows Graphics Capture (WGC) implementation.
// This will be defined in the corresponding .c or .cpp file.
extern const ScreenContextInternalOps g_screen_ops_win_wgc;

// Platform initialization function for WGC.
// This function will be called to set up the WGC backend for a screen context.
MiniAVResultCode miniav_screen_context_platform_init_windows_wgc(MiniAVScreenContext *ctx);

// Internal routing. Generic configuration and strict Begin atomically claim the
// same fresh owner; strict contexts must bypass the generic post-call writes.
bool miniav_wgc_context_is_strict(MiniAVScreenContext *ctx);
MiniAVResultCode miniav_wgc_generic_configuration(MiniAVScreenContext *ctx);
MiniAVResultCode miniav_wgc_route_start(MiniAVScreenContext *ctx,
    MiniAVBufferCallback callback, void *user_data, bool *handled);
MiniAVResultCode miniav_wgc_route_stop(MiniAVScreenContext *ctx, bool *handled);
MiniAVResultCode miniav_wgc_set_lost(MiniAVScreenContext *ctx,
    MiniAVContextLostCallback callback, void *user_data);
MiniAVResultCode miniav_wgc_set_cursor(MiniAVScreenContext *ctx, bool enabled);
MiniAVResultCode miniav_wgc_configured_formats(MiniAVScreenContext *ctx,
    MiniAVVideoInfo *video, MiniAVAudioInfo *audio);
void *miniav_wgc_strict_holder(MiniAVScreenContext *ctx);

#ifdef __cplusplus
}
#endif

#endif // SCREEN_CONTEXT_WIN_WGC_H
