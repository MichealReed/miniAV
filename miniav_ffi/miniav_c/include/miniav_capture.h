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