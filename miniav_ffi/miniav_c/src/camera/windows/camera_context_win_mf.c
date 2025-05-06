#define COBJMACROS // Enables C-style COM interface calling
#include "camera_context_win_mf.h"
#include "../../../include/miniav_buffer.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <shlwapi.h> // For StrCpyN, etc. (safer string copy)
#include <stdio.h>   // For _snwprintf_s
#include <windows.h>

#pragma comment(lib, "mf")
#pragma comment(lib, "mfplat")
#pragma comment(lib, "mfreadwrite")
#pragma comment(lib, "mfuuid")
#pragma comment(lib, "shlwapi")

// Forward declaration for the callback
static HRESULT STDMETHODCALLTYPE MFPlatform_OnReadSample(
    IMFSourceReaderCallback *pThis, HRESULT hrStatus, DWORD dwStreamIndex,
    DWORD dwStreamFlags, LONGLONG llTimestamp, IMFSample *pSample);
static HRESULT STDMETHODCALLTYPE
MFPlatform_OnFlush(IMFSourceReaderCallback *pThis, DWORD dwStreamIndex);
static HRESULT STDMETHODCALLTYPE MFPlatform_OnEvent(
    IMFSourceReaderCallback *pThis, DWORD dwStreamIndex, IMFMediaEvent *pEvent);
static ULONG STDMETHODCALLTYPE
MFPlatform_AddRef(IMFSourceReaderCallback *pThis);
static ULONG STDMETHODCALLTYPE
MFPlatform_Release(IMFSourceReaderCallback *pThis);
static HRESULT STDMETHODCALLTYPE MFPlatform_QueryInterface(
    IMFSourceReaderCallback *pThis, REFIID riid, void **ppvObject);

// Helper to convert MF Subtype GUID to MiniAVPixelFormat
static MiniAVPixelFormat MfSubTypeToMiniAVPixelFormat(const GUID *subtype) {
  if (!subtype)
    return MINIAV_PIXEL_FORMAT_UNKNOWN;
  if (IsEqualGUID(subtype, &MFVideoFormat_NV12))
    return MINIAV_PIXEL_FORMAT_NV12;
  if (IsEqualGUID(subtype, &MFVideoFormat_YUY2))
    return MINIAV_PIXEL_FORMAT_YUY2;
  if (IsEqualGUID(subtype, &MFVideoFormat_RGB24))
    return MINIAV_PIXEL_FORMAT_RGB24;
  if (IsEqualGUID(subtype, &MFVideoFormat_RGB32))
    return MINIAV_PIXEL_FORMAT_BGRA32; // MFVideoFormat_RGB32 is often BGRA
  if (IsEqualGUID(subtype, &MFVideoFormat_ARGB32))
    return MINIAV_PIXEL_FORMAT_ARGB32;
  if (IsEqualGUID(subtype, &MFVideoFormat_MJPG))
    return MINIAV_PIXEL_FORMAT_MJPEG;
  // Add more mappings as needed
  return MINIAV_PIXEL_FORMAT_UNKNOWN;
}

// Helper to convert MiniAVPixelFormat to MF Subtype GUID
static GUID MiniAVPixelFormatToMfSubType(MiniAVPixelFormat format) {
  if (format == MINIAV_PIXEL_FORMAT_NV12)
    return MFVideoFormat_NV12;
  if (format == MINIAV_PIXEL_FORMAT_YUY2)
    return MFVideoFormat_YUY2;
  if (format == MINIAV_PIXEL_FORMAT_RGB24)
    return MFVideoFormat_RGB24;
  if (format == MINIAV_PIXEL_FORMAT_BGRA32)
    return MFVideoFormat_RGB32;
  if (format == MINIAV_PIXEL_FORMAT_ARGB32)
    return MFVideoFormat_ARGB32;
  if (format == MINIAV_PIXEL_FORMAT_MJPEG)
    return MFVideoFormat_MJPG;
  return GUID_NULL;
}

typedef struct MFPlatformContext {
  IMFSourceReaderCallbackVtbl *lpVtbl; // Must be the first member for COM
  LONG ref_count;                      // Reference count for COM
  MiniAVCameraContext *parent_ctx; // Pointer back to the main MiniAV context

  IMFSourceReader *source_reader;
  CRITICAL_SECTION
  critical_section; // For thread safety if needed for app_callback access

  // Store the callback from MiniAVCameraContext to be used by OnReadSample
  MiniAVBufferCallback app_callback_internal;
  void *app_callback_user_data_internal;

  BOOL is_streaming; // Flag to control streaming loop in OnReadSample

  // Optional: Store the symbolic link of the device
  WCHAR symbolic_link[MINIAV_DEVICE_ID_MAX_LEN];

} MFPlatformContext;

// --- IMFSourceReaderCallback Implementation ---
static HRESULT STDMETHODCALLTYPE MFPlatform_QueryInterface(
    IMFSourceReaderCallback *pThis, REFIID riid, void **ppvObject) {
  MFPlatformContext *pCtx = (MFPlatformContext *)pThis;
  if (ppvObject == NULL) {
    return E_POINTER;
  }
  *ppvObject = NULL;

  if (IsEqualIID(riid, &IID_IUnknown) ||
      IsEqualIID(riid, &IID_IMFSourceReaderCallback)) {
    *ppvObject = pCtx;
    MFPlatform_AddRef(pThis);
    return S_OK;
  }
  return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE
MFPlatform_AddRef(IMFSourceReaderCallback *pThis) {
  MFPlatformContext *pCtx = (MFPlatformContext *)pThis;
  return InterlockedIncrement(&pCtx->ref_count);
}

static ULONG STDMETHODCALLTYPE
MFPlatform_Release(IMFSourceReaderCallback *pThis) {
  MFPlatformContext *pCtx = (MFPlatformContext *)pThis;
  ULONG uCount = InterlockedDecrement(&pCtx->ref_count);
  if (uCount == 0) {
    // The MFPlatformContext itself is owned by MiniAVCameraContext's
    // platform_ctx and freed in mf_destroy_platform. We don't free it here.
    // However, if this callback object were allocated independently, it would
    // be freed here.
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "MFPlatform_Release: ref_count is 0, but not freeing "
               "MFPlatformContext as it's owned by MiniAVCameraContext.");
  }
  return uCount;
}

static HRESULT STDMETHODCALLTYPE MFPlatform_OnReadSample(
    IMFSourceReaderCallback *pThis, HRESULT hrStatus, DWORD dwStreamIndex,
    DWORD dwStreamFlags, LONGLONG llTimestamp,
    IMFSample *
        pSample // Can be NULL if dwStreamFlags has
                // MF_SOURCE_READERF_ENDOFSTREAM or MF_SOURCE_READERF_STREAMTICK
) {
  MFPlatformContext *mf_ctx = (MFPlatformContext *)pThis;
  MiniAVCameraContext *parent_ctx = mf_ctx->parent_ctx;
  HRESULT hr = S_OK;
  IMFMediaBuffer *media_buffer = NULL;
  BYTE *raw_buffer_data = NULL;
  DWORD max_length = 0;
  DWORD current_length = 0;

  EnterCriticalSection(&mf_ctx->critical_section);

  if (!parent_ctx || !parent_ctx->is_running || !mf_ctx->is_streaming) {
    miniav_log(
        MINIAV_LOG_LEVEL_DEBUG,
        "MF: OnReadSample called but not running or streaming flag is false.");
    LeaveCriticalSection(&mf_ctx->critical_section);
    return S_OK; // Or an error if this state is unexpected
  }

  if (FAILED(hrStatus)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: OnReadSample received error status: 0x%X", hrStatus);
    // Potentially signal error to application or attempt recovery
    goto request_next_sample; // Try to request next sample anyway, or handle
                              // error more robustly
  }

  if (dwStreamFlags & MF_SOURCE_READERF_ENDOFSTREAM) {
    miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: End of stream.");
    // Signal application if necessary
    goto done;
  }
  if (dwStreamFlags & MF_SOURCE_READERF_STREAMTICK) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Stream tick.");
    goto request_next_sample; // Ignore stream ticks for now, request next
                              // actual sample
  }

  if (pSample == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "MF: OnReadSample pSample is NULL without EOS/Error/Tick flag.");
    goto request_next_sample; // Should not happen if hrStatus is OK and no
                              // other flags
  }

  // Get the media buffer from the sample
  hr = IMFSample_ConvertToContiguousBuffer(pSample, &media_buffer);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to convert to contiguous buffer: 0x%X", hr);
    goto request_next_sample;
  }

  hr = IMFMediaBuffer_Lock(media_buffer, &raw_buffer_data, &max_length,
                           &current_length);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: Failed to lock media buffer: 0x%X",
               hr);
    goto request_next_sample;
  }

  MiniAVBuffer buffer;
  memset(&buffer, 0, sizeof(MiniAVBuffer));
  buffer.type = MINIAV_BUFFER_TYPE_VIDEO;
  buffer.timestamp_us =
      llTimestamp; // MF timestamps are in 100-nanosecond units

  buffer.data.video.width = parent_ctx->configured_format.width;
  buffer.data.video.height = parent_ctx->configured_format.height;
  buffer.data.video.pixel_format = parent_ctx->configured_format.pixel_format;

  // Assuming a single plane for simplicity here. Multi-plane formats (NV12,
  // I420) need more handling.
  buffer.data.video.planes[0] = raw_buffer_data;
  // Stride might need to be obtained from the media type if not simply width *
  // bytes_per_pixel For formats like YUY2, stride is typically width * 2. For
  // RGB24, width * 3. This is a simplification; a robust solution would query
  // stride from IMFMediaType.
  UINT32 stride = 0;
  // MFGetStrideForBitmapInfoHeader can be used if you have the format and
  // width. For now, a basic calculation:
  if (buffer.data.video.pixel_format == MINIAV_PIXEL_FORMAT_YUY2)
    stride = buffer.data.video.width * 2;
  else if (buffer.data.video.pixel_format == MINIAV_PIXEL_FORMAT_RGB24)
    stride = buffer.data.video.width * 3;
  else if (buffer.data.video.pixel_format == MINIAV_PIXEL_FORMAT_BGRA32 ||
           buffer.data.video.pixel_format == MINIAV_PIXEL_FORMAT_ARGB32)
    stride = buffer.data.video.width * 4;
  else if (buffer.data.video.pixel_format == MINIAV_PIXEL_FORMAT_NV12)
    stride = buffer.data.video.width; // Stride for Y plane
  // else, it might be encoded (MJPEG) or needs specific stride calculation.
  buffer.data.video.stride_bytes[0] = stride;
  // For NV12, plane 1 (UV) would also have a stride, typically the same as Y.
  // buffer.data.video.planes[1] = raw_buffer_data + (stride *
  // buffer.data.video.height); // Example for NV12 UV offset
  // buffer.data.video.stride_bytes[1] = stride;

  buffer.data_size_bytes = current_length;
  buffer.user_data = mf_ctx->app_callback_user_data_internal;

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
  if (!payload) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate internal handle payload.");
    IMFMediaBuffer_Unlock(media_buffer);
    goto request_next_sample;
  }
  payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA;
  payload->context_owner = parent_ctx;
  payload->native_resource_ptr = pSample; // Store the IMFSample
  IMFSample_AddRef(pSample);              // AddRef because we are holding it

  buffer.internal_handle = payload;

  if (mf_ctx->app_callback_internal) {
    mf_ctx->app_callback_internal(&buffer,
                                  mf_ctx->app_callback_user_data_internal);
  } else {
    // If no app callback, we still need to release the sample we AddRef'd
    IMFSample_Release(pSample);
    miniav_free(payload); // And the payload we allocated
  }

  IMFMediaBuffer_Unlock(media_buffer);

request_next_sample:
  if (mf_ctx->is_streaming && parent_ctx->is_running && mf_ctx->source_reader) {
    hr = IMFSourceReader_ReadSample(
        mf_ctx->source_reader,
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, // dwStreamIndex
        0,                                          // dwControlFlags
        NULL,  // pdwActualStreamIndex (out)
        NULL,  // pdwStreamFlags (out)
        NULL,  // pllTimestamp (out)
        NULL); // ppSample (out) // Request next sample
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: Failed to request next sample: 0x%X", hr);
      mf_ctx->is_streaming = FALSE; // Stop streaming on error
      // Consider signaling an error to the parent context / application
    }
  }

done:
  if (media_buffer)
    IMFMediaBuffer_Release(media_buffer);
  // pSample is managed by the caller of OnReadSample or AddRef'd and stored in
  // payload
  LeaveCriticalSection(&mf_ctx->critical_section);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE
MFPlatform_OnFlush(IMFSourceReaderCallback *pThis, DWORD dwStreamIndex) {
  MINIAV_UNUSED(pThis);
  MINIAV_UNUSED(dwStreamIndex);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: OnFlush called for stream %u.",
             dwStreamIndex);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE
MFPlatform_OnEvent(IMFSourceReaderCallback *pThis, DWORD dwStreamIndex,
                   IMFMediaEvent *pEvent) {
  MINIAV_UNUSED(pThis);
  MINIAV_UNUSED(dwStreamIndex);
  MediaEventType met;
  if (pEvent && SUCCEEDED(IMFMediaEvent_GetType(pEvent, &met))) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "MF: OnEvent called for stream %u, event type %d.",
               dwStreamIndex, met);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "MF: OnEvent called for stream %u (pEvent or GetType failed).",
               dwStreamIndex);
  }
  return S_OK;
}

// VTable for our IMFSourceReaderCallback implementation
static IMFSourceReaderCallbackVtbl g_MFPlatformVtbl = {
    MFPlatform_QueryInterface, MFPlatform_AddRef,  MFPlatform_Release,
    MFPlatform_OnReadSample,   MFPlatform_OnFlush, MFPlatform_OnEvent};

// --- Platform Ops Implementation ---

static MiniAVResultCode mf_init_platform(MiniAVCameraContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Initializing platform context (real). Thread ID: %lu",
             GetCurrentThreadId());
  HRESULT hr_com_init;   // Stores the result of CoInitializeEx
  HRESULT hr_mf_startup; // Stores the result of MFStartup

  // Initialize COM
  hr_com_init =
      CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(hr_com_init)) {
    if (hr_com_init == RPC_E_CHANGED_MODE) {
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "MF: CoInitializeEx returned RPC_E_CHANGED_MODE on thread %lu. "
          "COM already initialized, possibly with a different concurrency "
          "model. Proceeding.",
          GetCurrentThreadId());
      // COM is already initialized; this function didn't initialize it in this
      // call. We will proceed, but we won't be the one to call CoUninitialize
      // if subsequent steps fail *within this function*. The corresponding
      // CoUninitialize should be handled by the original initializer.
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: CoInitializeEx failed on thread %lu with error: 0x%X",
                 GetCurrentThreadId(), hr_com_init);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED; // Critical failure, cannot
                                              // proceed
    }
  }
  // If hr_com_init is S_OK, this function call is responsible for a
  // corresponding CoUninitialize.

  // Initialize Media Foundation
  hr_mf_startup = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr_mf_startup)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFStartup failed on thread %lu with error: 0x%X",
               GetCurrentThreadId(), hr_mf_startup);
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      // Only call CoUninitialize if this specific call to CoInitializeEx
      // succeeded with S_OK.
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Allocate platform-specific context
  MFPlatformContext *mf_ctx =
      (MFPlatformContext *)miniav_calloc(1, sizeof(MFPlatformContext));
  if (!mf_ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate MFPlatformContext on thread %lu.",
               GetCurrentThreadId());
    MFShutdown(); // Shutdown MF
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      // Only call CoUninitialize if this specific call to CoInitializeEx
      // succeeded with S_OK.
      CoUninitialize();
    }
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  // Initialize MFPlatformContext members
  mf_ctx->lpVtbl = &g_MFPlatformVtbl; // Assign the VTable for COM
  mf_ctx->ref_count = 1;              // Initial reference count
  mf_ctx->parent_ctx = ctx;
  mf_ctx->source_reader = NULL;
  mf_ctx->is_streaming = FALSE;
  if (!InitializeCriticalSectionAndSpinCount(&mf_ctx->critical_section,
                                             0x00000400)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to initialize critical section on thread %lu.",
               GetCurrentThreadId());
    miniav_free(mf_ctx); // Free allocated context
    MFShutdown();
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  ctx->platform_ctx = mf_ctx;
  miniav_log(
      MINIAV_LOG_LEVEL_INFO,
      "MF: Platform context initialized successfully (real). Thread ID: %lu",
      GetCurrentThreadId());
  return MINIAV_SUCCESS;
}

static MiniAVResultCode mf_destroy_platform(MiniAVCameraContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Destroying platform context (real).");
  if (ctx && ctx->platform_ctx) {
    MFPlatformContext *mf_ctx = (MFPlatformContext *)ctx->platform_ctx;

    if (mf_ctx->is_streaming) {
      // This should ideally be handled by MiniAV_Camera_StopCapture
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "MF: Destroying platform while still streaming. Attempting to stop.");
      // Call a simplified stop, actual stop logic is in mf_stop_capture
      mf_ctx->is_streaming = FALSE; // Prevent further ReadSample requests
      // No explicit flush here, source reader release should handle it.
    }

    if (mf_ctx->source_reader) {
      IMFSourceReader_Release(mf_ctx->source_reader);
      mf_ctx->source_reader = NULL;
    }

    DeleteCriticalSection(&mf_ctx->critical_section);
    // The MFPlatformContext itself is freed here as it's part of the
    // MiniAVCameraContext
    miniav_free(mf_ctx);
    ctx->platform_ctx = NULL;
  }

  MFShutdown();
  CoUninitialize(); // Assuming CoInitialize was successful or returned
                    // RPC_E_CHANGED_MODE
  miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: Platform context destroyed (real).");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode mf_enumerate_devices(MiniAVDeviceInfo **devices_out,
                                             uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Enumerating devices (real). Thread ID: %lu",
             GetCurrentThreadId());
  *devices_out = NULL;
  *count_out = 0;

  HRESULT hr = S_OK;
  IMFAttributes *attributes = NULL;
  IMFActivate **devices = NULL;
  UINT32 count = 0;
  MiniAVDeviceInfo *result_devices = NULL;
  BOOL com_initialized_here = FALSE;
  BOOL mf_started_here = FALSE;

  // Initialize COM for this function's scope if not already initialized
  HRESULT hr_com_init =
      CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (SUCCEEDED(hr_com_init)) {
    if (hr_com_init == S_OK) { // S_OK means COM was initialized by this call
      com_initialized_here = TRUE;
    }
    // If S_FALSE or RPC_E_CHANGED_MODE, COM was already initialized, proceed.
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: CoInitializeEx failed in enumerate_devices: 0x%X",
               hr_com_init);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Initialize Media Foundation for this function's scope
  HRESULT hr_mf_startup = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr_mf_startup)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFStartup failed in enumerate_devices: 0x%X",
               hr_mf_startup);
    if (com_initialized_here) {
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  mf_started_here = TRUE; // Assume MFStartup needs a corresponding MFShutdown

  hr = MFCreateAttributes(&attributes, 1);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: MFCreateAttributes failed: 0x%X",
               hr);
    goto cleanup_and_exit;
  }

  hr = IMFAttributes_SetGUID(attributes, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: SetGUID MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID "
               "failed: 0x%X",
               hr);
    goto cleanup_and_exit;
  }

  hr = MFEnumDeviceSources(attributes, &devices, &count);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: MFEnumDeviceSources failed: 0x%X",
               hr);
    goto cleanup_and_exit;
  }

  if (count == 0) {
    miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: No video capture devices found.");
    // No devices is not an error, hr should be S_OK
    goto cleanup_and_exit;
  }

  result_devices =
      (MiniAVDeviceInfo *)miniav_calloc(count, sizeof(MiniAVDeviceInfo));
  if (!result_devices) {
    hr = E_OUTOFMEMORY;
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate memory for device list.");
    goto cleanup_and_exit;
  }

  for (UINT32 i = 0; i < count; i++) {
    WCHAR *friendly_name = NULL;
    UINT32 friendly_name_len = 0;
    WCHAR *symbolic_link = NULL;
    UINT32 symbolic_link_len = 0;
    HRESULT hr_attr;

    hr_attr = IMFActivate_GetAllocatedString(
        devices[i], &MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &friendly_name,
        &friendly_name_len);
    if (SUCCEEDED(hr_attr)) {
      WideCharToMultiByte(CP_UTF8, 0, friendly_name, -1, result_devices[i].name,
                          MINIAV_DEVICE_NAME_MAX_LEN, NULL, NULL);
      CoTaskMemFree(friendly_name);
    } else {
      StrCpyNA(result_devices[i].name, "Unknown MF Device",
               MINIAV_DEVICE_NAME_MAX_LEN);
    }

    hr_attr = IMFActivate_GetAllocatedString(
        devices[i], &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        &symbolic_link, &symbolic_link_len);
    if (SUCCEEDED(hr_attr)) {
      WideCharToMultiByte(CP_UTF8, 0, symbolic_link, -1,
                          result_devices[i].device_id, MINIAV_DEVICE_ID_MAX_LEN,
                          NULL, NULL);
      CoTaskMemFree(symbolic_link);
    } else {
      char temp_id[32];
      sprintf_s(temp_id, sizeof(temp_id), "MF_Device_%u_NoLink", i);
      StrCpyNA(result_devices[i].device_id, temp_id, MINIAV_DEVICE_ID_MAX_LEN);
    }
    result_devices[i].is_default = (i == 0);
  }

  *devices_out = result_devices;
  *count_out = count;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: Enumerated %u devices (real).", count);

cleanup_and_exit:
  if (attributes) {
    IMFAttributes_Release(attributes);
  }
  if (devices) {
    for (UINT32 i = 0; i < count;
         i++) { // 'count' might be 0 if MFEnumDeviceSources failed but devices
                // was allocated by a previous call in a bug, or if count is
                // from a successful call
      if (devices[i]) {
        IMFActivate_Release(devices[i]);
      }
    }
    CoTaskMemFree(devices);
  }

  if (FAILED(hr) && result_devices) {
    miniav_free(result_devices);
    *devices_out = NULL;
    *count_out = 0;
  }

  if (mf_started_here) {
    MFShutdown();
  }
  if (com_initialized_here) {
    CoUninitialize();
  }

  return SUCCEEDED(hr) ? MINIAV_SUCCESS : MINIAV_ERROR_SYSTEM_CALL_FAILED;
}

static MiniAVResultCode
mf_get_supported_formats(const char *device_id_utf8,
                         MiniAVVideoFormatInfo **formats_out,
                         uint32_t *count_out) {
  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "MF: Getting supported formats for device %s (real). Thread ID: %lu",
      device_id_utf8, GetCurrentThreadId());
  *formats_out = NULL;
  *count_out = 0;

  HRESULT hr = S_OK;
  HRESULT hr_loop_check;
  IMFActivate *device_activate = NULL;
  IMFMediaSource *media_source = NULL;
  IMFSourceReader *source_reader = NULL;
  MiniAVVideoFormatInfo *result_formats_list = NULL;
  uint32_t allocated_formats = 0;
  uint32_t found_formats = 0;
  IMFAttributes *enum_attributes = NULL;
  IMFActivate **all_devices = NULL;
  UINT32 num_all_devices = 0;
  IMFMediaType *media_type = NULL;

  BOOL com_initialized_here = FALSE;
  BOOL mf_started_here = FALSE;

  // Initialize COM for this function's scope if not already initialized
  HRESULT hr_com_init =
      CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (SUCCEEDED(hr_com_init)) {
    if (hr_com_init == S_OK) { // S_OK means COM was initialized by this call
      com_initialized_here = TRUE;
    }
    // If S_FALSE or RPC_E_CHANGED_MODE, COM was already initialized, proceed.
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: CoInitializeEx failed in get_supported_formats: 0x%X",
               hr_com_init);
    // No resources allocated yet that need MF specific cleanup
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Initialize Media Foundation for this function's scope
  HRESULT hr_mf_startup = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr_mf_startup)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFStartup failed in get_supported_formats: 0x%X",
               hr_mf_startup);
    if (com_initialized_here) {
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  mf_started_here = TRUE;

  WCHAR device_id_wchar[MINIAV_DEVICE_ID_MAX_LEN];
  MultiByteToWideChar(CP_UTF8, 0, device_id_utf8, -1, device_id_wchar,
                      MINIAV_DEVICE_ID_MAX_LEN);

  hr = MFCreateAttributes(&enum_attributes, 1);
  if (FAILED(hr))
    goto error_exit;
  hr = IMFAttributes_SetGUID(enum_attributes,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr))
    goto error_exit;
  hr = MFEnumDeviceSources(enum_attributes, &all_devices, &num_all_devices);
  if (FAILED(hr))
    goto error_exit;

  for (UINT32 i = 0; i < num_all_devices; ++i) {
    WCHAR *current_sym_link = NULL;
    HRESULT hr_link = IMFActivate_GetAllocatedString(
        all_devices[i],
        &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        &current_sym_link, NULL);
    if (SUCCEEDED(hr_link)) {
      if (wcscmp(current_sym_link, device_id_wchar) == 0) {
        device_activate = all_devices[i];
        IMFActivate_AddRef(device_activate); // We took a reference
      }
      CoTaskMemFree(current_sym_link);
    }
    if (device_activate)
      break;
  }

  if (!device_activate) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Could not find IMFActivate for device ID: %s",
               device_id_utf8);
    hr = HRESULT_FROM_WIN32(
        MINIAV_ERROR_DEVICE_NOT_FOUND); // More specific error
    goto error_exit;
  }

  hr = IMFActivate_ActivateObject(device_activate, &IID_IMFMediaSource,
                                  (void **)&media_source);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: IMFActivate_ActivateObject failed for %s: 0x%X",
               device_id_utf8, hr);
    goto error_exit;
  }
  hr = MFCreateSourceReaderFromMediaSource(media_source, NULL, &source_reader);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFCreateSourceReaderFromMediaSource failed: 0x%X", hr);
    goto error_exit;
  }

  DWORD media_type_index = 0;
  // IMFMediaType *media_type = NULL; // Moved declaration up
  while (TRUE) {
    hr_loop_check = IMFSourceReader_GetNativeMediaType(
        source_reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, media_type_index,
        &media_type);

    if (FAILED(hr_loop_check)) {
      if (hr_loop_check == MF_E_NO_MORE_TYPES) {
        hr = S_OK;
      } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "MF: GetNativeMediaType failed with HRESULT 0x%X",
                   hr_loop_check);
        hr = hr_loop_check;
      }
      break;
    }

    if (media_type == NULL) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "MF: GetNativeMediaType SUCCEEDED but media_type is NULL! Index: %u.",
          media_type_index);
      hr = E_UNEXPECTED;
      goto error_exit;
    }

    GUID subtype_guid;
    HRESULT hr_attr;

    hr_attr = IMFMediaType_GetGUID(media_type, &MF_MT_SUBTYPE, &subtype_guid);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }

    MiniAVPixelFormat pixel_format =
        MfSubTypeToMiniAVPixelFormat(&subtype_guid);
    if (pixel_format == MINIAV_PIXEL_FORMAT_UNKNOWN) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }

    UINT32 width = 0, height = 0;
    UINT64 packed_frame_size = 0;
    hr_attr = IMFMediaType_GetUINT64(media_type, &MF_MT_FRAME_SIZE,
                                     &packed_frame_size);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }
    width = (UINT32)(packed_frame_size >> 32);
    height = (UINT32)(packed_frame_size & 0xFFFFFFFF);

    UINT32 fr_num = 0, fr_den = 0;
    UINT64 packed_frame_rate = 0;
    hr_attr = IMFMediaType_GetUINT64(media_type, &MF_MT_FRAME_RATE,
                                     &packed_frame_rate);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }
    fr_num = (UINT32)(packed_frame_rate >> 32);
    fr_den = (UINT32)(packed_frame_rate & 0xFFFFFFFF);

    if (width == 0 || height == 0 || fr_den == 0) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }

    if (found_formats >= allocated_formats) {
      allocated_formats = (allocated_formats == 0) ? 8 : allocated_formats * 2;
      MiniAVVideoFormatInfo *new_list = (MiniAVVideoFormatInfo *)miniav_realloc(
          result_formats_list,
          allocated_formats * sizeof(MiniAVVideoFormatInfo));
      if (!new_list) {
        miniav_free(result_formats_list);
        result_formats_list = NULL;
        IMFMediaType_Release(media_type);
        media_type = NULL;
        hr = E_OUTOFMEMORY;
        goto error_exit;
      }
      result_formats_list = new_list;
    }

    result_formats_list[found_formats].width = width;
    result_formats_list[found_formats].height = height;
    result_formats_list[found_formats].frame_rate_numerator = fr_num;
    result_formats_list[found_formats].frame_rate_denominator = fr_den;
    result_formats_list[found_formats].pixel_format = pixel_format;
    found_formats++;

    IMFMediaType_Release(media_type);
    media_type = NULL;
    media_type_index++;
  }

  if (SUCCEEDED(hr)) {
    *formats_out = result_formats_list;
    *count_out = found_formats;
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "MF: Found %u supported formats for %s (real).", found_formats,
               device_id_utf8);
  } else {
    miniav_free(result_formats_list);
    result_formats_list = NULL; // Defensive
    *formats_out = NULL;
    *count_out = 0;
  }

error_exit:
  if (media_type)
    IMFMediaType_Release(media_type);
  if (source_reader)
    IMFSourceReader_Release(source_reader);
  if (media_source)
    IMFMediaSource_Release(media_source);
  if (device_activate)
    IMFActivate_Release(device_activate); // We AddRef'd it
  if (enum_attributes)
    IMFAttributes_Release(enum_attributes);
  if (all_devices) {
    for (UINT32 i = 0; i < num_all_devices; ++i) {
      // device_activate was AddRef'd and released above if it was found.
      // all_devices[i] that was not chosen for device_activate still needs
      // release.
      if (all_devices[i] !=
          device_activate) { // Avoid double release if device_activate came
                             // from all_devices
        if (all_devices[i])
          IMFActivate_Release(all_devices[i]);
      }
    }
    CoTaskMemFree(all_devices);
  }

  if (FAILED(hr)) {
    if (*formats_out != NULL ||
        result_formats_list !=
            NULL) { // result_formats_list might be assigned before an error
      miniav_free(result_formats_list ? result_formats_list : *formats_out);
      *formats_out = NULL; // Ensure out params are clear on error
      *count_out = 0;
    }
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: mf_get_supported_formats failed for %s with HRESULT 0x%X",
               device_id_utf8, hr);
  }

  if (mf_started_here) {
    MFShutdown();
  }
  if (com_initialized_here) {
    CoUninitialize();
  }

  return SUCCEEDED(hr) ? MINIAV_SUCCESS : MINIAV_ERROR_SYSTEM_CALL_FAILED;
}

static MiniAVResultCode mf_configure(
    MiniAVCameraContext *ctx,
    const char
        *device_id_utf8, // This is the symbolic link from initial enumeration
    const MiniAVVideoFormatInfo *format) {
  MFPlatformContext *mf_ctx = (MFPlatformContext *)ctx->platform_ctx;
  HRESULT hr = S_OK;
  HRESULT hr_loop_check;
  HRESULT hr_attr;

  IMFActivate *device_activate =
      NULL; // This will be the specific device to configure
  IMFMediaSource *media_source = NULL;
  IMFAttributes *reader_attributes = NULL;
  IMFMediaType *target_media_type =
      NULL; // For iterating and setting the chosen format

  float fps_approx = (format->frame_rate_denominator == 0)
                         ? 0.0f
                         : (float)format->frame_rate_numerator /
                               format->frame_rate_denominator;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Configuring device %s with format %ux%u @ %u/%u (approx "
             "%.2f) FPS, PixelFormat %d (real).",
             device_id_utf8 ? device_id_utf8
                            : "Default (Error: device_id_utf8 is NULL)",
             format->width, format->height, format->frame_rate_numerator,
             format->frame_rate_denominator, fps_approx, format->pixel_format);

  if (!device_id_utf8) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: device_id_utf8 is NULL in mf_configure.");
    return MINIAV_ERROR_INVALID_ARG;
  }

  // Convert the incoming UTF-8 device ID (symbolic link) to WCHAR
  // This symbolic link is stored in mf_ctx->symbolic_link by mf_init_platform
  // or earlier. For configuration, we need to find the IMFActivate object
  // corresponding to this.
  WCHAR target_symbolic_link_wchar[MINIAV_DEVICE_ID_MAX_LEN];
  MultiByteToWideChar(CP_UTF8, 0, device_id_utf8, -1,
                      target_symbolic_link_wchar, MINIAV_DEVICE_ID_MAX_LEN);

  // Store it in mf_ctx if not already there or if it could change (though
  // device_id_utf8 should be the one to use)
  StrCpyNW(mf_ctx->symbolic_link, target_symbolic_link_wchar,
           MINIAV_DEVICE_ID_MAX_LEN);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Attempting to configure with target symbolic link: %ls",
             mf_ctx->symbolic_link);

  // --- Find the IMFActivate* for the given symbolic link ---
  IMFAttributes *enum_attributes = NULL;
  IMFActivate **all_video_devices = NULL;
  UINT32 num_video_devices = 0;

  hr = MFCreateAttributes(&enum_attributes, 1);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFCreateAttributes for enumeration failed: 0x%X", hr);
    goto error_cleanup;
  }

  hr = IMFAttributes_SetGUID(enum_attributes,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: SetGUID for VIDCAP_GUID failed: 0x%X", hr);
    IMFAttributes_Release(enum_attributes);
    goto error_cleanup;
  }

  hr = MFEnumDeviceSources(enum_attributes, &all_video_devices,
                           &num_video_devices);
  IMFAttributes_Release(enum_attributes);
  enum_attributes = NULL;

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFEnumDeviceSources (to find specific link) failed: 0x%X",
               hr);
    goto error_cleanup;
  }

  if (num_video_devices == 0) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "MF: No video capture devices found during configuration search.");
    hr = MF_E_NOT_FOUND;
    goto error_cleanup;
  }

  for (UINT32 i = 0; i < num_video_devices; ++i) {
    WCHAR *current_sym_link_iter =
        NULL; // Use a different name to avoid confusion
    HRESULT hr_link = IMFActivate_GetAllocatedString(
        all_video_devices[i],
        &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        &current_sym_link_iter, NULL);
    if (SUCCEEDED(hr_link)) {
      if (wcscmp(mf_ctx->symbolic_link, current_sym_link_iter) == 0) {
        device_activate = all_video_devices[i];
        IMFActivate_AddRef(device_activate);
      }
      CoTaskMemFree(current_sym_link_iter);
    }
    if (device_activate) {
      break;
    }
  }

  if (all_video_devices) {
    for (UINT32 i = 0; i < num_video_devices; ++i) {
      if (all_video_devices[i] != device_activate) {
        IMFActivate_Release(all_video_devices[i]);
      }
    }
    CoTaskMemFree(all_video_devices);
    all_video_devices = NULL;
  }

  if (!device_activate) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to find/match device for symbolic link: %ls",
               mf_ctx->symbolic_link);
    hr = MF_E_NOT_FOUND;
    goto error_cleanup;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Found matching IMFActivate for configuration using link: %ls",
             mf_ctx->symbolic_link);
  // --- End finding IMFActivate* ---

  // Release existing source reader if any (e.g., from a previous configuration)
  if (mf_ctx->source_reader) {
    IMFSourceReader_Release(mf_ctx->source_reader);
    mf_ctx->source_reader = NULL;
  }
  // Also release media_source if it was somehow populated before (defensive)
  if (media_source) {
    IMFMediaSource_Release(media_source);
    media_source = NULL;
  }

  hr = IMFActivate_ActivateObject(device_activate, &IID_IMFMediaSource,
                                  (void **)&media_source);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: IMFActivate_ActivateObject failed for %ls: 0x%X",
               mf_ctx->symbolic_link, hr);
    goto error_cleanup;
  }

  hr = MFCreateAttributes(&reader_attributes, 1);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFCreateAttributes for reader failed: 0x%X", hr);
    goto error_cleanup;
  }
  hr = IMFAttributes_SetUnknown(
      reader_attributes, &MF_SOURCE_READER_ASYNC_CALLBACK, (IUnknown *)mf_ctx);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: SetUnknown for ASYNC_CALLBACK failed: 0x%X", hr);
    goto error_cleanup;
  }

  hr = MFCreateSourceReaderFromMediaSource(media_source, reader_attributes,
                                           &mf_ctx->source_reader);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFCreateSourceReaderFromMediaSource failed: 0x%X", hr);
    goto error_cleanup;
  }

  DWORD media_type_index = 0;
  BOOL found_match = FALSE;
  while (TRUE) { // Loop to find and set the desired media type
    hr_loop_check = IMFSourceReader_GetNativeMediaType(
        mf_ctx->source_reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM,
        media_type_index, &target_media_type);

    if (FAILED(hr_loop_check)) {
      if (hr_loop_check == MF_E_NO_MORE_TYPES) {
        hr = S_OK; // Reached end of types, if no match found, it's an error
                   // handled after loop
      } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "MF: GetNativeMediaType failed with HRESULT 0x%X",
                   hr_loop_check);
        hr = hr_loop_check;
      }
      break;
    }

    if (target_media_type == NULL) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: GetNativeMediaType SUCCEEDED but target_media_type is "
                 "NULL! Index: %u.",
                 media_type_index);
      hr = E_UNEXPECTED;
      goto error_cleanup;
    }

    GUID subtype_guid;
    UINT32 mt_width = 0, mt_height = 0, mt_fr_num = 0, mt_fr_den = 0;
    UINT64 packed_value = 0;

    hr_attr =
        IMFMediaType_GetGUID(target_media_type, &MF_MT_SUBTYPE, &subtype_guid);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(target_media_type);
      target_media_type = NULL;
      media_type_index++;
      continue;
    }

    hr_attr = IMFMediaType_GetUINT64(target_media_type, &MF_MT_FRAME_SIZE,
                                     &packed_value);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(target_media_type);
      target_media_type = NULL;
      media_type_index++;
      continue;
    }
    mt_width = (UINT32)(packed_value >> 32);
    mt_height = (UINT32)(packed_value & 0xFFFFFFFF);

    hr_attr = IMFMediaType_GetUINT64(target_media_type, &MF_MT_FRAME_RATE,
                                     &packed_value);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(target_media_type);
      target_media_type = NULL;
      media_type_index++;
      continue;
    }
    mt_fr_num = (UINT32)(packed_value >> 32);
    mt_fr_den = (UINT32)(packed_value & 0xFFFFFFFF);

    if (mt_width != 0 && mt_height != 0 && mt_fr_den != 0) {
      MiniAVPixelFormat mt_pixel_format =
          MfSubTypeToMiniAVPixelFormat(&subtype_guid);
      if (mt_width == format->width && mt_height == format->height &&
          mt_fr_num == format->frame_rate_numerator &&
          mt_fr_den == format->frame_rate_denominator &&
          mt_pixel_format == format->pixel_format) {

        hr = IMFSourceReader_SetCurrentMediaType( // Use main 'hr' for this
                                                  // critical op
            mf_ctx->source_reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL,
            target_media_type);
        if (SUCCEEDED(hr)) {
          found_match = TRUE;
          miniav_log(
              MINIAV_LOG_LEVEL_DEBUG,
              "MF: Successfully set media type: %ux%u @ %u/%u, Format: %d",
              mt_width, mt_height, mt_fr_num, mt_fr_den, mt_pixel_format);
        } else {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "MF: SetCurrentMediaType failed: 0x%X", hr);
        }
        IMFMediaType_Release(target_media_type); // Always release after use
        target_media_type = NULL;
        break;
      }
    }

    IMFMediaType_Release(target_media_type);
    target_media_type = NULL;
    media_type_index++;
  }

  if (FAILED(hr)) { // If SetCurrentMediaType failed or GetNativeMediaType had a
                    // critical error
    goto error_cleanup;
  }

  if (!found_match) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Could not find or set matching media type for "
               "configuration. Target: %ux%u @ %u/%u FPS, PixelFormat %d",
               format->width, format->height, format->frame_rate_numerator,
               format->frame_rate_denominator, format->pixel_format);
    hr = MF_E_INVALIDMEDIATYPE; // Or E_FAIL
    goto error_cleanup;
  }

  mf_ctx->app_callback_internal = ctx->app_callback;
  mf_ctx->app_callback_user_data_internal = ctx->app_callback_user_data;

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "MF: Configured device %ls successfully (real).",
             mf_ctx->symbolic_link);

error_cleanup:
  if (target_media_type)
    IMFMediaType_Release(target_media_type);
  if (reader_attributes)
    IMFAttributes_Release(reader_attributes);
  if (media_source)
    IMFMediaSource_Release(media_source);
  if (device_activate)
    IMFActivate_Release(device_activate); // Was AddRef'd if found

  // Do not release mf_ctx->source_reader here if SUCCEEDED(hr)
  // It's part of the mf_ctx and should be released when the context is
  // destroyed or reconfigured. Only release it on failure.
  if (FAILED(hr)) {
    if (mf_ctx->source_reader) {
      IMFSourceReader_Release(mf_ctx->source_reader);
      mf_ctx->source_reader = NULL;
    }
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: mf_configure failed for %s with HRESULT 0x%X",
               device_id_utf8 ? device_id_utf8 : "Unknown Device", hr);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  return MINIAV_SUCCESS;
}

static MiniAVResultCode mf_start_capture(MiniAVCameraContext *ctx) {
  MFPlatformContext *mf_ctx = (MFPlatformContext *)ctx->platform_ctx;
  if (!mf_ctx || !mf_ctx->source_reader) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Starting capture (real).");

  EnterCriticalSection(&mf_ctx->critical_section);
  mf_ctx->is_streaming = TRUE;
  // Store app callback details from parent context (might have changed if
  // reconfigured without restart)
  mf_ctx->app_callback_internal = ctx->app_callback;
  mf_ctx->app_callback_user_data_internal = ctx->app_callback_user_data;
  LeaveCriticalSection(&mf_ctx->critical_section);

  // Initial call to ReadSample. Subsequent calls are made from OnReadSample.
  HRESULT hr = IMFSourceReader_ReadSample(
      mf_ctx->source_reader,
      (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, // dwStreamIndex
      0,                                          // dwControlFlags
      NULL,                                       // pdwActualStreamIndex (out)
      NULL,                                       // pdwStreamFlags (out)
      NULL,                                       // pllTimestamp (out)
      NULL                                        // ppSample (out)
  );

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to initiate ReadSample: 0x%X", hr);
    EnterCriticalSection(&mf_ctx->critical_section);
    mf_ctx->is_streaming = FALSE;
    LeaveCriticalSection(&mf_ctx->critical_section);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "MF: Capture started (real), ReadSample requested.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode mf_stop_capture(MiniAVCameraContext *ctx) {
  MFPlatformContext *mf_ctx = (MFPlatformContext *)ctx->platform_ctx;
  if (!mf_ctx) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Stopping capture (real).");

  EnterCriticalSection(&mf_ctx->critical_section);
  BOOL was_streaming = mf_ctx->is_streaming;
  mf_ctx->is_streaming =
      FALSE; // Signal OnReadSample to stop requesting more frames
  LeaveCriticalSection(&mf_ctx->critical_section);

  if (was_streaming && mf_ctx->source_reader) {
    // Flushing can help ensure that any pending OnReadSample calls complete or
    // are cancelled. This is a synchronous call.
    HRESULT hr_flush = IMFSourceReader_Flush(
        mf_ctx->source_reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    if (FAILED(hr_flush)) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "MF: IMFSourceReader_Flush failed during stop: 0x%X",
                 hr_flush);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "MF: IMFSourceReader_Flush completed.");
    }
  }
  // The source reader itself is released during destroy_platform or
  // re-configure.
  miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: Capture stopped (real).");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
mf_release_buffer(MiniAVCameraContext *ctx,
                  void *native_buffer_payload_resource_ptr) {
  MINIAV_UNUSED(ctx);
  if (!native_buffer_payload_resource_ptr) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  IMFSample *pSample = (IMFSample *)native_buffer_payload_resource_ptr;
  ULONG ref_count_before =
      IMFSample_Release(pSample); // Release the AddRef from OnReadSample
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Released IMFSample. Ref count before release: %lu",
             ref_count_before);
  return MINIAV_SUCCESS;
}

// Define the actual ops struct for Media Foundation
const CameraContextInternalOps g_camera_ops_win_mf = {
    .init_platform = mf_init_platform,
    .destroy_platform = mf_destroy_platform,
    .enumerate_devices = mf_enumerate_devices,
    .get_supported_formats = mf_get_supported_formats,
    .configure = mf_configure,
    .start_capture = mf_start_capture,
    .stop_capture = mf_stop_capture,
    .release_buffer = mf_release_buffer};

MiniAVResultCode
miniav_camera_context_platform_init_windows(MiniAVCameraContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;
  ctx->ops = &g_camera_ops_win_mf;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Assigned Windows Media Foundation camera ops (real).");
  // The caller (MiniAV_Camera_CreateContext) will call
  // ctx->ops->init_platform()
  return MINIAV_SUCCESS;
}
