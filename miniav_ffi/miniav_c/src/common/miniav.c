#include "../include/miniav.h"
#include "miniav_logging.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Version info
#define MINIAV_VERSION_MAJOR 0
#define MINIAV_VERSION_MINOR 1
#define MINIAV_VERSION_PATCH 0

// --- Error Strings ---
static const char *miniav_error_string(MiniAVResultCode code) {
  switch (code) {
  case MINIAV_SUCCESS:
    return "Success";
  case MINIAV_ERROR_UNKNOWN:
    return "Unknown error";
  case MINIAV_ERROR_INVALID_ARG:
    return "Invalid argument";
  case MINIAV_ERROR_NOT_INITIALIZED:
    return "Not initialized";
  case MINIAV_ERROR_SYSTEM_CALL_FAILED:
    return "System call failed";
  case MINIAV_ERROR_NOT_SUPPORTED:
    return "Not supported";
  case MINIAV_ERROR_BUFFER_TOO_SMALL:
    return "Buffer too small";
  case MINIAV_ERROR_INVALID_HANDLE:
    return "Invalid handle";
  case MINIAV_ERROR_DEVICE_NOT_FOUND:
    return "Device not found";
  case MINIAV_ERROR_DEVICE_BUSY:
    return "Device busy";
  case MINIAV_ERROR_ALREADY_RUNNING:
    return "Already running";
  case MINIAV_ERROR_NOT_RUNNING:
    return "Not running";
  case MINIAV_ERROR_OUT_OF_MEMORY:
    return "Out of memory";
  case MINIAV_ERROR_TIMEOUT:
    return "Timeout";
  default:
    return "Unrecognized error code";
  }
}

// --- API Implementations ---

MiniAVResultCode MiniAV_GetVersion(uint32_t *major, uint32_t *minor,
                                   uint32_t *patch) {
  if (!major || !minor || !patch)
    return MINIAV_ERROR_INVALID_ARG;
  *major = MINIAV_VERSION_MAJOR;
  *minor = MINIAV_VERSION_MINOR;
  *patch = MINIAV_VERSION_PATCH;
  return MINIAV_SUCCESS;
}

const char *MiniAV_GetVersionString(void) { return "0.1.0"; }

const char *MiniAV_GetErrorString(MiniAVResultCode code) {
  return miniav_error_string(code);
}

MiniAVResultCode MiniAV_SetLogCallback(MiniAVLogCallback callback,
                                       void *user_data) {
  miniav_set_log_callback(callback, user_data);
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_SetLogLevel(MiniAVLogLevel level) {
  miniav_set_log_level(level);
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_ReleaseBuffer(void *internal_handle) {
  if (!internal_handle)
    return MINIAV_ERROR_INVALID_ARG;
  free(internal_handle);
  return MINIAV_SUCCESS;
}

// --- Stub Implementations for Capture APIs ---

MiniAVResultCode MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo **devices,
                                                uint32_t *count) {
  (void)devices;
  (void)count;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_FreeDeviceList(MiniAVDeviceInfo *devices,
                                       uint32_t count) {
  (void)count;
  free(devices);
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Camera_GetSupportedFormats(const char *device_id,
                                                   void **formats,
                                                   uint32_t *count) {
  (void)device_id;
  (void)formats;
  (void)count;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_FreeFormatList(void *formats, uint32_t count) {
  (void)count;
  free(formats);
  return MINIAV_SUCCESS;
}

MiniAVResultCode
MiniAV_Camera_CreateContext(MiniAVCameraContextHandle *context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Camera_Configure(MiniAVCameraContextHandle context,
                                         const char *device_id,
                                         const void *format) {
  (void)context;
  (void)device_id;
  (void)format;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context,
                                            MiniAVBufferCallback callback,
                                            void *user_data) {
  (void)context;
  (void)callback;
  (void)user_data;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Camera_StopCapture(MiniAVCameraContextHandle context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Screen_EnumerateDisplays(MiniAVDeviceInfo **displays,
                                                 uint32_t *count) {
  (void)displays;
  (void)count;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Screen_EnumerateWindows(MiniAVDeviceInfo **windows,
                                                uint32_t *count) {
  (void)windows;
  (void)count;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_CreateContext(MiniAVScreenContextHandle *context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_DestroyContext(MiniAVScreenContextHandle context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_ConfigureDisplay(MiniAVScreenContextHandle context,
                               const char *display_id, const void *format) {
  (void)context;
  (void)display_id;
  (void)format;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_ConfigureWindow(MiniAVScreenContextHandle context,
                              const char *window_id, const void *format) {
  (void)context;
  (void)window_id;
  (void)format;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode
MiniAV_Screen_ConfigureRegion(MiniAVScreenContextHandle context,
                              const char *display_id, int x, int y, int width,
                              int height, const void *format) {
  (void)context;
  (void)display_id;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  (void)format;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Screen_StartCapture(MiniAVScreenContextHandle context,
                                            MiniAVBufferCallback callback,
                                            void *user_data) {
  (void)context;
  (void)callback;
  (void)user_data;
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode MiniAV_Screen_StopCapture(MiniAVScreenContextHandle context) {
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
}
