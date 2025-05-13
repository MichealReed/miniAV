#ifndef MINIAV_SCREEN_CONTEXT_H
#define MINIAV_SCREEN_CONTEXT_H

#include "../../include/miniav.h"


#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration
struct MiniAVScreenContext;

// --- Screen Context Operations ---
// These are function pointers for platform-specific implementations.
typedef struct ScreenContextInternalOps {
    MiniAVResultCode (*init_platform)(struct MiniAVScreenContext *ctx);
    MiniAVResultCode (*destroy_platform)(struct MiniAVScreenContext *ctx);

    MiniAVResultCode (*enumerate_displays)(MiniAVDeviceInfo **displays_out, uint32_t *count_out);
    MiniAVResultCode (*enumerate_windows)(MiniAVDeviceInfo **windows_out, uint32_t *count_out);
    // MiniAV_FreeDeviceList is used to free the lists from enumerate_displays/windows

    MiniAVResultCode (*configure_display)(struct MiniAVScreenContext *ctx, const char *display_id, const MiniAVVideoFormatInfo *format);
    MiniAVResultCode (*configure_window)(struct MiniAVScreenContext *ctx, const char *window_id, const MiniAVVideoFormatInfo *format); // window_id might be HWND as string or a title
    MiniAVResultCode (*configure_region)(struct MiniAVScreenContext *ctx, const char *display_id_or_window_id, int x, int y, int width, int height, const MiniAVVideoFormatInfo *format);

    MiniAVResultCode (*start_capture)(struct MiniAVScreenContext *ctx, MiniAVBufferCallback callback, void *user_data);
    MiniAVResultCode (*stop_capture)(struct MiniAVScreenContext *ctx);

    // Called via the common MiniAV_ReleaseBuffer, which inspects the payload
    MiniAVResultCode (*release_buffer)(struct MiniAVScreenContext *ctx, void *native_buffer_payload_resource_ptr);

} ScreenContextInternalOps;

// --- Screen Context Structure ---
typedef struct MiniAVScreenContext {
    void *platform_ctx; // Platform-specific context (e.g., DXGIScreenPlatformContext)
    const ScreenContextInternalOps *ops;

    MiniAVBufferCallback app_callback;
    void *app_callback_user_data;

    bool is_running; // TRUE if capture is active
    MiniAVVideoFormatInfo configured_format; // The format requested by the user and/or confirmed by the backend

    // Add any other common state needed across platforms
    MiniAVCaptureType capture_target_type; // DISPLAY, WINDOW, REGION

    bool capture_audio_requested; // Whether the user requested audio capture

} MiniAVScreenContext;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_SCREEN_CONTEXT_H
