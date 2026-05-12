#ifndef MINIAV_CAPTURE_H
#define MINIAV_CAPTURE_H

#include "export.h" // For MINIAV_API

#include "miniav_buffer.h"
#include "miniav_types.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Buffer Callback ---
typedef void (*MiniAVBufferCallback)(const MiniAVBuffer *buffer,
                                     void *user_data);

// --- Device Change Notification API ---
//
// All MiniAV_*_SetDeviceChangeCallback / SetDisplayChangeCallback /
// SetWindowChangeCallback / SetGamepadChangeCallback functions follow the
// same contract:
//   - Pass a non-NULL callback to subscribe.
//   - Pass NULL to unsubscribe (and tear down any background watcher).
//   - Calling subscribe again replaces the previous callback.
//   - Implementation may be polling-based; events typically arrive within
//     1-2 seconds of the underlying OS change.
//   - The callback runs on a background thread; do not call back into MiniAV
//     APIs that may block waiting for the same thread.
typedef enum {
  MINIAV_DEVICE_CHANGE_ADDED = 0,
  MINIAV_DEVICE_CHANGE_REMOVED = 1,
  MINIAV_DEVICE_CHANGE_DEFAULT_CHANGED = 2,
} MiniAVDeviceChangeEvent;

typedef void (*MiniAVDeviceChangeCallback)(MiniAVDeviceChangeEvent event,
                                           const MiniAVDeviceInfo *device,
                                           void *user_data);

// --- Per-Context Device-Lost Callback ---
//
// Fires when the device a capture context is currently using becomes
// unavailable mid-stream (unplugged, disabled, format renegotiation failed,
// GPU reset, etc.). Capture is automatically stopped and the context becomes
// unusable; the application should call MiniAV_*_DestroyContext and
// reconfigure if needed.
//
// The callback runs on the capture or watcher thread; treat it like any
// other capture-thread callback.
typedef void (*MiniAVContextLostCallback)(int /*MiniAVResultCode*/ reason,
                                          void *user_data);

// --- Common / Utility API ---
MINIAV_API MiniAVResultCode MiniAV_GetVersion(uint32_t *major, uint32_t *minor,
                                              uint32_t *patch);
MINIAV_API const char *MiniAV_GetVersionString(void);
MINIAV_API MiniAVResultCode MiniAV_SetLogCallback(MiniAVLogCallback callback,
                                                  void *user_data);
MINIAV_API MiniAVResultCode MiniAV_SetLogLevel(MiniAVLogLevel level);
MINIAV_API const char *MiniAV_GetErrorString(MiniAVResultCode code);
MINIAV_API MiniAVResultCode MiniAV_ReleaseBuffer(void *internal_handle);
MINIAV_API MiniAVResultCode MiniAV_Free(void *ptr);
MINIAV_API MiniAVResultCode MiniAV_FreeDeviceList(MiniAVDeviceInfo *devices,
                                                  uint32_t count);
MINIAV_API MiniAVResultCode
MiniAV_FreeFormatList(void *formats,
                      uint32_t count);

// --- Camera Capture API ---
MINIAV_API MiniAVResultCode
MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo **devices, uint32_t *count);
MINIAV_API MiniAVResultCode MiniAV_Camera_GetSupportedFormats(
    const char *device_id, MiniAVVideoInfo **formats,
    uint32_t *count); // Placeholder for MiniAVVideoInfo
MINIAV_API MiniAVResultCode MiniAV_Camera_GetDefaultFormat(
    const char *device_id, MiniAVVideoInfo *format_out);
MINIAV_API MiniAVResultCode MiniAV_Camera_GetConfiguredFormat(
    MiniAVCameraContextHandle context, MiniAVVideoInfo *format_out);
MINIAV_API MiniAVResultCode
MiniAV_Camera_CreateContext(MiniAVCameraContextHandle *context);
MINIAV_API MiniAVResultCode
MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context);
MINIAV_API MiniAVResultCode MiniAV_Camera_Configure(
    MiniAVCameraContextHandle context, const char *device_id,
    const void *format);
MINIAV_API MiniAVResultCode
MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context,
                           MiniAVBufferCallback callback, void *user_data);
MINIAV_API MiniAVResultCode
MiniAV_Camera_StopCapture(MiniAVCameraContextHandle context);

// Device change subscription. Pass NULL callback to unsubscribe.
MINIAV_API MiniAVResultCode MiniAV_Camera_SetDeviceChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);
// Per-context lost notification. Pass NULL callback to unsubscribe.
MINIAV_API MiniAVResultCode MiniAV_Camera_SetContextLostCallback(
    MiniAVCameraContextHandle context, MiniAVContextLostCallback callback,
    void *user_data);

// --- Screen Capture API ---
MINIAV_API MiniAVResultCode
MiniAV_Screen_CreateContext(MiniAVScreenContextHandle *context);
MINIAV_API MiniAVResultCode MiniAV_Screen_EnumerateDisplays(
    MiniAVDeviceInfo **displays_out, uint32_t *count_out);
MINIAV_API MiniAVResultCode
MiniAV_Screen_EnumerateWindows(MiniAVDeviceInfo **windows, uint32_t *count);
MINIAV_API MiniAVResultCode MiniAV_Screen_GetDefaultFormats(
    const char *display_id, MiniAVVideoInfo *video_format_out,
    MiniAVAudioInfo *audio_format_out);
MINIAV_API MiniAVResultCode
MiniAV_Screen_DestroyContext(MiniAVScreenContextHandle context);
MINIAV_API MiniAVResultCode MiniAV_Screen_ConfigureDisplay(
    MiniAVScreenContextHandle context, const char *display_id,
    const MiniAVVideoInfo *format, // Corrected type
    bool capture_audio);
MINIAV_API MiniAVResultCode MiniAV_Screen_ConfigureWindow(
    MiniAVScreenContextHandle context, const char *window_id,
    const MiniAVVideoInfo *format, bool capture_audio);
MINIAV_API MiniAVResultCode MiniAV_Screen_ConfigureRegion(
    MiniAVScreenContextHandle context, const char *display_id, int x, int y,
    int width, int height, const MiniAVVideoInfo *format,
    bool capture_audio);
MINIAV_API MiniAVResultCode MiniAV_Screen_GetConfiguredFormats(
    MiniAVScreenContextHandle context, MiniAVVideoInfo *video_format_out,
    MiniAVAudioInfo *audio_format_out);
MINIAV_API MiniAVResultCode
MiniAV_Screen_StartCapture(MiniAVScreenContextHandle context,
                           MiniAVBufferCallback callback, void *user_data);
MINIAV_API MiniAVResultCode
MiniAV_Screen_StopCapture(MiniAVScreenContextHandle context);

// Subscribe for display add/remove notifications. Pass NULL to unsubscribe.
MINIAV_API MiniAVResultCode MiniAV_Screen_SetDisplayChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);
// Subscribe for window add/remove notifications. Pass NULL to unsubscribe.
// Polling is comparatively heavy on Windows because EnumWindows must run
// each cycle; subscribe sparingly.
MINIAV_API MiniAVResultCode MiniAV_Screen_SetWindowChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);
// Per-context lost notification. Fires e.g. when a captured display is
// disconnected or the captured window is closed.
MINIAV_API MiniAVResultCode MiniAV_Screen_SetContextLostCallback(
    MiniAVScreenContextHandle context, MiniAVContextLostCallback callback,
    void *user_data);

// --- Audio Capture API ---
MINIAV_API MiniAVResultCode
MiniAV_Audio_EnumerateDevices(MiniAVDeviceInfo **devices, uint32_t *count);
MINIAV_API MiniAVResultCode MiniAV_Audio_GetSupportedFormats(
    const char *device_id, MiniAVAudioInfo **formats_out, uint32_t *count_out);
MINIAV_API MiniAVResultCode MiniAV_Audio_GetDefaultFormat(
    const char *device_id, MiniAVAudioInfo *format_out);
MINIAV_API MiniAVResultCode MiniAV_Audio_GetConfiguredFormat(
    MiniAVAudioContextHandle context, MiniAVAudioInfo *format_out);
MINIAV_API MiniAVResultCode
MiniAV_Audio_CreateContext(MiniAVAudioContextHandle *context);
MINIAV_API MiniAVResultCode
MiniAV_Audio_DestroyContext(MiniAVAudioContextHandle context);
MINIAV_API MiniAVResultCode
MiniAV_Audio_Configure(MiniAVAudioContextHandle context, const char *device_id,
                       const MiniAVAudioInfo *format);
MINIAV_API MiniAVResultCode
MiniAV_Audio_StartCapture(MiniAVAudioContextHandle context,
                          MiniAVBufferCallback callback, void *user_data);
MINIAV_API MiniAVResultCode
MiniAV_Audio_StopCapture(MiniAVAudioContextHandle context);

// Subscribe for audio capture device add/remove notifications.
MINIAV_API MiniAVResultCode MiniAV_Audio_SetDeviceChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);
// Per-context lost notification (microphone unplugged, format renegotiation
// failed, etc.).
MINIAV_API MiniAVResultCode MiniAV_Audio_SetContextLostCallback(
    MiniAVAudioContextHandle context, MiniAVContextLostCallback callback,
    void *user_data);

// --- Loopback Audio Capture API ---
MINIAV_API MiniAVResultCode MiniAV_Loopback_EnumerateTargets(
    MiniAVLoopbackTargetType
        target_type_filter,         // e.g., system audio, specific process
    MiniAVDeviceInfo **targets_out, // Array of available loopback targets
    uint32_t *count_out             // Number of targets found
);
MINIAV_API MiniAVResultCode MiniAV_Loopback_GetSupportedFormats(
    const char *target_device_id,
    MiniAVAudioInfo **formats_out, // Array of supported audio formats
    uint32_t *count_out            // Number of formats found
);
MINIAV_API MiniAVResultCode MiniAV_Loopback_GetDefaultFormat(
    const char *target_device_id, MiniAVAudioInfo *format_out);
MINIAV_API MiniAVResultCode MiniAV_Loopback_GetConfiguredFormat(
    MiniAVLoopbackContextHandle context, MiniAVAudioInfo *format_out);
MINIAV_API MiniAVResultCode
MiniAV_Loopback_CreateContext(MiniAVLoopbackContextHandle *context_out);
MINIAV_API MiniAVResultCode
MiniAV_Loopback_DestroyContext(MiniAVLoopbackContextHandle context);
MINIAV_API MiniAVResultCode MiniAV_Loopback_Configure(
    MiniAVLoopbackContextHandle context,
    const char *target_device_id, // Optional: Specific device ID from
                                  // enumeration. NULL for default system audio
                                  // output. For process/window, this might be
                                  // NULL if target_info is used.
    const MiniAVAudioInfo
        *requested_format // Desired audio format for the loopback capture
    // Consider adding MiniAVLoopbackTargetInfo here if more complex targeting
    // is needed beyond device_id const MiniAVLoopbackTargetInfo* target_info
);
MINIAV_API MiniAVResultCode
MiniAV_Loopback_StartCapture(MiniAVLoopbackContextHandle context,
                             MiniAVBufferCallback callback, void *user_data);
MINIAV_API MiniAVResultCode
MiniAV_Loopback_StopCapture(MiniAVLoopbackContextHandle context);

// Subscribe for loopback target add/remove notifications. The watcher emits
// for the default system-audio target type; use MiniAV_Loopback_EnumerateTargets
// to inspect the current full list at any time.
MINIAV_API MiniAVResultCode MiniAV_Loopback_SetDeviceChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);
// Per-context lost notification (e.g. WASAPI returned AUDCLNT_E_DEVICE_INVALIDATED
// because the captured render endpoint was unplugged).
MINIAV_API MiniAVResultCode MiniAV_Loopback_SetContextLostCallback(
    MiniAVLoopbackContextHandle context, MiniAVContextLostCallback callback,
    void *user_data);

// --- Input Capture API ---
MINIAV_API MiniAVResultCode
MiniAV_Input_EnumerateGamepads(MiniAVDeviceInfo **devices, uint32_t *count);
MINIAV_API MiniAVResultCode
MiniAV_Input_CreateContext(MiniAVInputContextHandle *context);
MINIAV_API MiniAVResultCode
MiniAV_Input_DestroyContext(MiniAVInputContextHandle context);
MINIAV_API MiniAVResultCode
MiniAV_Input_Configure(MiniAVInputContextHandle context,
                       const MiniAVInputConfig *config);
MINIAV_API MiniAVResultCode
MiniAV_Input_StartCapture(MiniAVInputContextHandle context);
MINIAV_API MiniAVResultCode
MiniAV_Input_StopCapture(MiniAVInputContextHandle context);

// Subscribe for gamepad add/remove notifications.
MINIAV_API MiniAVResultCode MiniAV_Input_SetGamepadChangeCallback(
    MiniAVDeviceChangeCallback callback, void *user_data);

// --- Global Lifecycle ---
//
// MiniAV_Dispose() atomically disables all callback dispatch and waits for
// any in-flight callback invocations to complete before returning.  Call this
// before tearing down Dart NativeCallable handles — for example, from
// Flutter's reassemble() — to prevent "Callback invoked after it has been
// deleted" fatal crashes during hot restart.
//
// MiniAV_EnableCallbacks() re-enables callback dispatch.  It is called
// automatically by every MiniAV_*_StartCapture() function so that a new
// recording session works correctly after a previous MiniAV_Dispose() call.
// Explicit calls are rarely needed.
MINIAV_API MiniAVResultCode MiniAV_Dispose(void);
MINIAV_API MiniAVResultCode MiniAV_EnableCallbacks(void);

// --- Property APIs (TBD) ---
// MiniAV_Camera_GetPropertyInfo(...)
// MiniAV_Camera_GetProperty(...)
// MiniAV_Camera_SetProperty(...)
// MiniAV_Screen_GetProperty(...)
// MiniAV_Screen_SetProperty(...)
// MiniAV_Audio_GetProperty(...)
// MiniAV_Audio_SetProperty(...)

#ifdef __cplusplus
}
#endif

#endif // MINIAV_CAPTURE_H