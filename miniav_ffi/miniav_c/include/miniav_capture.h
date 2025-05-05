#ifndef MINIAV_CAPTURE_H
#define MINIAV_CAPTURE_H

#include <stdint.h>
#include "miniav_types.h"
#include "miniav_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- Buffer Callback ---
typedef void (*MiniAVBufferCallback)(const MiniAVBuffer* buffer, void* user_data);

// --- Common / Utility API ---
MiniAVResultCode MiniAV_GetVersion(uint32_t* major, uint32_t* minor, uint32_t* patch);
const char* MiniAV_GetVersionString(void);
MiniAVResultCode MiniAV_SetLogCallback(MiniAVLogCallback callback, void* user_data);
MiniAVResultCode MiniAV_SetLogLevel(MiniAVLogLevel level);
const char* MiniAV_GetErrorString(MiniAVResultCode code);
MiniAVResultCode MiniAV_ReleaseBuffer(void* internal_handle);

// --- Camera Capture API ---
MiniAVResultCode MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo** devices, uint32_t* count);
MiniAVResultCode MiniAV_FreeDeviceList(MiniAVDeviceInfo* devices, uint32_t count);
MiniAVResultCode MiniAV_Camera_GetSupportedFormats(const char* device_id, void** formats, uint32_t* count); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_FreeFormatList(void* formats, uint32_t count); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_Camera_CreateContext(MiniAVCameraContextHandle* context);
MiniAVResultCode MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context);
MiniAVResultCode MiniAV_Camera_Configure(MiniAVCameraContextHandle context, const char* device_id, const void* format); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context, MiniAVBufferCallback callback, void* user_data);
MiniAVResultCode MiniAV_Camera_StopCapture(MiniAVCameraContextHandle context);

// --- Screen Capture API ---
MiniAVResultCode MiniAV_Screen_EnumerateDisplays(MiniAVDeviceInfo** displays, uint32_t* count);
MiniAVResultCode MiniAV_Screen_EnumerateWindows(MiniAVDeviceInfo** windows, uint32_t* count);
MiniAVResultCode MiniAV_Screen_CreateContext(MiniAVScreenContextHandle* context);
MiniAVResultCode MiniAV_Screen_DestroyContext(MiniAVScreenContextHandle context);
MiniAVResultCode MiniAV_Screen_ConfigureDisplay(MiniAVScreenContextHandle context, const char* display_id, const void* format); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_Screen_ConfigureWindow(MiniAVScreenContextHandle context, const char* window_id, const void* format); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_Screen_ConfigureRegion(MiniAVScreenContextHandle context, const char* display_id, int x, int y, int width, int height, const void* format); // Placeholder for MiniAVVideoFormatInfo
MiniAVResultCode MiniAV_Screen_StartCapture(MiniAVScreenContextHandle context, MiniAVBufferCallback callback, void* user_data);
MiniAVResultCode MiniAV_Screen_StopCapture(MiniAVScreenContextHandle context);

// --- Audio Capture API ---
MiniAVResultCode MiniAV_Audio_EnumerateDevices(MiniAVDeviceInfo** devices, uint32_t* count);
MiniAVResultCode MiniAV_Audio_GetSupportedFormats(const char* device_id, void** formats, uint32_t* count); // Placeholder for MiniAVAudioFormatInfo
MiniAVResultCode MiniAV_Audio_CreateContext(MiniAVAudioContextHandle* context);
MiniAVResultCode MiniAV_Audio_DestroyContext(MiniAVAudioContextHandle context);
MiniAVResultCode MiniAV_Audio_Configure(MiniAVAudioContextHandle context, const char* device_id, const void* format); // Placeholder for MiniAVAudioFormatInfo
MiniAVResultCode MiniAV_Audio_StartCapture(MiniAVAudioContextHandle context, MiniAVBufferCallback callback, void* user_data);
MiniAVResultCode MiniAV_Audio_StopCapture(MiniAVAudioContextHandle context);

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