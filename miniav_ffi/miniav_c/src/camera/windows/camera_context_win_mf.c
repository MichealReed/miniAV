#define COBJMACROS // Enables C-style COM interface calling
#include "camera_context_win_mf.h"
#include "../../../include/miniav_buffer.h" // Assumed to be updated for shared handles
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <shlwapi.h> // For StrCpyN, etc. (safer string copy)
#include <stdio.h>   // For _snwprintf_s
#include <windows.h>

#include <initguid.h> // For GUIDs

// DirectX includes for shared textures
#include <d3d11.h>
#include <dxgi1_2.h> // For IDXGIResource1 and CreateSharedHandle

#pragma comment(lib, "mf")
#pragma comment(lib, "mfplat")
#pragma comment(lib, "mfreadwrite")
#pragma comment(lib, "mfuuid")
#pragma comment(lib, "shlwapi")
#pragma comment(lib, "d3d11")
#pragma comment(lib, "dxgi")

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

  // DirectX related objects for GPU texture sharing
  IMFDXGIDeviceManager *dxgi_manager;
  ID3D11Device *d3d_device;
  ID3D11DeviceContext *d3d_device_context; // Immediate context
  UINT dxgi_manager_reset_token;

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

  miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: OnReadSample - ENTRY POINT REACHED.");

  MFPlatformContext *mf_ctx = (MFPlatformContext *)pThis;
  MiniAVCameraContext *parent_ctx = mf_ctx->parent_ctx;
  HRESULT hr = S_OK; // hr for internal operations, hrStatus is from MF
  IMFMediaBuffer *media_buffer = NULL;
  BYTE *raw_buffer_data = NULL;
  DWORD max_length = 0;
  DWORD current_length = 0;
  BOOL processed_as_gpu_texture = FALSE;

  EnterCriticalSection(&mf_ctx->critical_section);

  if (!parent_ctx || !parent_ctx->is_running || !mf_ctx->is_streaming) {
    miniav_log(
        MINIAV_LOG_LEVEL_DEBUG,
        "MF: OnReadSample called but not running or streaming flag is false.");
    LeaveCriticalSection(&mf_ctx->critical_section);
    return S_OK;
  }

  if (FAILED(hrStatus)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: OnReadSample received error status from MF: 0x%X",
               hrStatus);
    hr = hrStatus; // Propagate MF error to our internal hr for
                   // request_next_sample logic
    goto request_next_sample;
  }

  if (dwStreamFlags & MF_SOURCE_READERF_ENDOFSTREAM) {
    miniav_log(MINIAV_LOG_LEVEL_INFO, "MF: End of stream.");
    // TODO: Signal application via callback with a special buffer type or flag
    goto done;
  }
  if (dwStreamFlags & MF_SOURCE_READERF_STREAMTICK) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Stream tick.");
    goto request_next_sample;
  }

  if (pSample == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "MF: OnReadSample pSample is NULL without EOS/Error/Tick flag.");
    goto request_next_sample;
  }

  MiniAVBuffer *buffer_ptr =
      (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
  if (!buffer_ptr) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate MiniAVBuffer struct.");
    hr = E_OUTOFMEMORY;
    goto request_next_sample; // Or appropriate cleanup that doesn't assume
                              // media_buffer exists
  }
  buffer_ptr->type = MINIAV_BUFFER_TYPE_VIDEO;
  buffer_ptr->timestamp_us = llTimestamp;
  buffer_ptr->data.video.width = parent_ctx->configured_format.width;
  buffer_ptr->data.video.height = parent_ctx->configured_format.height;
  buffer_ptr->data.video.pixel_format =
      parent_ctx->configured_format.pixel_format;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: OnReadSample - parent_ctx->configured_format.pixel_format is "
             "%d (0x%X)",
             parent_ctx->configured_format.pixel_format,
             parent_ctx->configured_format.pixel_format);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: OnReadSample - buffer.data.video.pixel_format is %d (0x%X) "
             "before callback",
             buffer_ptr->data.video.pixel_format,
             buffer_ptr->data.video.pixel_format);
  // Assuming MiniAVBuffer has these fields (actual_output_preference_achieved,
  // shared_texture_handle, native_gpu_texture_ptr)
  // buffer.data.video.actual_output_preference_achieved =
  // MINIAV_OUTPUT_PREFERENCE_CPU; // Default
  buffer_ptr->data.video.native_gpu_shared_handle = NULL;
  buffer_ptr->data.video.native_gpu_texture_ptr = NULL;

  MiniAVOutputPreference desired_output_pref =
      parent_ctx->configured_format.output_preference;

  // Attempt GPU shared texture path if D3D manager exists and GPU preference is
  // set
  if (mf_ctx->dxgi_manager && mf_ctx->d3d_device &&
      mf_ctx->d3d_device_context &&
      (desired_output_pref ==
       MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE)) { // Or other specific shared
                                                     // texture prefs
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "MF: Attempting GPU shared texture path.");
    hr = IMFSample_GetBufferByIndex(pSample, 0, &media_buffer);
    if (SUCCEEDED(hr)) {
      IMFDXGIBuffer *dxgi_buffer = NULL;
      hr = IMFMediaBuffer_QueryInterface(media_buffer, &IID_IMFDXGIBuffer,
                                         (void **)&dxgi_buffer);
      if (SUCCEEDED(hr)) {
        ID3D11Texture2D *d3d11_texture = NULL;
        hr = IMFDXGIBuffer_GetResource(dxgi_buffer, &IID_ID3D11Texture2D,
                                       (void **)&d3d11_texture);
        if (SUCCEEDED(hr)) {
          D3D11_TEXTURE2D_DESC tex_desc;
          ID3D11Texture2D_GetDesc(d3d11_texture, &tex_desc);
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "MF: D3D11 Texture Desc: Width=%u, Height=%u, Format=%u, "
                     "MiscFlags=0x%X, BindFlags=0x%X",
                     tex_desc.Width, tex_desc.Height, tex_desc.Format,
                     tex_desc.MiscFlags, tex_desc.BindFlags);

          if (!(tex_desc.MiscFlags & D3D11_RESOURCE_MISC_SHARED)) {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "MF: Texture from IMFDXGIBuffer is NOT shareable "
                       "(D3D11_RESOURCE_MISC_SHARED flag missing). "
                       "Attempting to copy to a shareable texture.");

            ID3D11Texture2D *shareable_texture = NULL;
            D3D11_TEXTURE2D_DESC shareable_tex_desc =
                tex_desc; // Copy original desc
            shareable_tex_desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED |
                                           D3D11_RESOURCE_MISC_SHARED_NTHANDLE;
            shareable_tex_desc.CPUAccessFlags = 0;
            shareable_tex_desc.Usage = D3D11_USAGE_DEFAULT;
            // BindFlags should be compatible with CopyResource source and
            // render target/shader resource if needed later For now, let's keep
            // original bind flags and see if CreateTexture2D and CopyResource
            // work. If CreateTexture2D fails with E_INVALIDARG, BindFlags might
            // need adjustment (e.g. ensure D3D11_BIND_SHADER_RESOURCE)

            hr = ID3D11Device_CreateTexture2D(mf_ctx->d3d_device,
                                              &shareable_tex_desc, NULL,
                                              &shareable_texture);
            if (SUCCEEDED(hr)) {
              ID3D11DeviceContext_CopyResource(
                  mf_ctx->d3d_device_context,
                  (ID3D11Resource *)shareable_texture,
                  (ID3D11Resource *)d3d11_texture);
              miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                         "MF: Copied to a new shareable texture.");

              IDXGIResource1 *dxgi_resource_new = NULL;
              hr = ID3D11Texture2D_QueryInterface(shareable_texture,
                                                  &IID_IDXGIResource1,
                                                  (void **)&dxgi_resource_new);
              if (SUCCEEDED(hr)) {
                HANDLE shared_handle = NULL;
                hr = IDXGIResource1_CreateSharedHandle(
                    dxgi_resource_new, NULL, DXGI_SHARED_RESOURCE_READ, NULL,
                    &shared_handle);
                if (SUCCEEDED(hr)) {
                  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                             "MF: Successfully created DXGI shared handle from "
                             "copied texture: %p",
                             shared_handle);
                  buffer_ptr->data.video.planes[0] = NULL;
                  buffer_ptr->data.video.native_gpu_texture_ptr = d3d11_texture;
                  buffer_ptr->data.video.native_gpu_shared_handle = shared_handle;
                  buffer_ptr->data.video.stride_bytes[0] = 0;
                  buffer_ptr->data_size_bytes = 0;
                  processed_as_gpu_texture = TRUE;
                  buffer_ptr->content_type =
                      MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE;
                  // The application is responsible for
                  // CloseHandle(shared_handle) The shareable_texture itself is
                  // released below.
                } else {
                  miniav_log(MINIAV_LOG_LEVEL_ERROR,
                             "MF: Failed to create DXGI shared handle from "
                             "copied texture: 0x%X. Will fallback to CPU.",
                             hr);
                }
                IDXGIResource1_Release(dxgi_resource_new);
              } else {
                miniav_log(MINIAV_LOG_LEVEL_ERROR,
                           "MF: Failed to query IDXGIResource1 from copied "
                           "texture: 0x%X. Will fallback to CPU.",
                           hr);
              }
              ID3D11Texture2D_Release(shareable_texture);
            } else {
              miniav_log(MINIAV_LOG_LEVEL_ERROR,
                         "MF: Failed to create a shareable texture for copy: "
                         "0x%X. Will fallback to CPU.",
                         hr);
            }
          } else { // Original texture is shareable
            IDXGIResource1 *dxgi_resource = NULL;
            hr = ID3D11Texture2D_QueryInterface(
                d3d11_texture, &IID_IDXGIResource1, (void **)&dxgi_resource);
            if (SUCCEEDED(hr)) {
              HANDLE shared_handle = NULL;
              hr = IDXGIResource1_CreateSharedHandle(
                  dxgi_resource, NULL,       // No specific security attributes
                  DXGI_SHARED_RESOURCE_READ, // Read-only access
                  NULL,                      // Unnamed resource
                  &shared_handle);
              if (SUCCEEDED(hr)) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                           "MF: Successfully created DXGI shared handle from "
                           "original texture: %p",
                           shared_handle);
                buffer_ptr->data.video.planes[0] = NULL;
                buffer_ptr->data.video.native_gpu_shared_handle = shared_handle;
                buffer_ptr->data.video.native_gpu_texture_ptr = d3d11_texture;
                buffer_ptr->data.video.stride_bytes[0] = 0;
                buffer_ptr->data_size_bytes = 0;
                processed_as_gpu_texture = TRUE;
                buffer_ptr->content_type =
                    MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE;
              } else {
                miniav_log(MINIAV_LOG_LEVEL_ERROR,
                           "MF: Failed to create DXGI shared handle from "
                           "original texture: 0x%X. "
                           "Will fallback to CPU.",
                           hr);
              }
              IDXGIResource1_Release(dxgi_resource);
            } else {
              miniav_log(MINIAV_LOG_LEVEL_ERROR,
                         "MF: Failed to query IDXGIResource1 from original "
                         "texture: 0x%X. Will "
                         "fallback to CPU.",
                         hr);
            }
          }
          ID3D11Texture2D_Release(d3d11_texture);
        } else {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "MF: Failed to get D3D11 texture from DXGI buffer: 0x%X. "
                     "Might not be a D3D backed sample. Will fallback to CPU.",
                     hr);
        }
        IMFDXGIBuffer_Release(dxgi_buffer);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "MF: Failed to query IMFDXGIBuffer from media buffer: 0x%X. "
                   "Not a DXGI buffer. Will fallback to CPU.",
                   hr);
      }
      IMFMediaBuffer_Release(media_buffer);
      media_buffer = NULL;
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: Failed to get buffer from sample for DXGI path: 0x%X. "
                 "Will fallback to CPU.",
                 hr);
    }
  }

  // CPU Path (if not processed as GPU texture, or if CPU is preferred, or if
  // GPU_IF_AVAILABLE failed to produce shareable texture)
  if (!processed_as_gpu_texture) {
    buffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
    if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE) {
      miniav_log(MINIAV_LOG_LEVEL_INFO,
                 "MF: GPU_IF_AVAILABLE preference: Falling back to CPU path "
                 "for sample processing.");
    } else if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_CPU) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "MF: CPU preference: Processing sample on CPU path.");
    }
    // Add handling here if you introduce a
    // MINIAV_OUTPUT_PREFERENCE_SHARED_TEXTURE_DXGI_REQUIRE enum, in which case,
    // if processed_as_gpu_texture is false, it would be a hard error. e.g., if
    // (desired_output_pref ==
    // MINIAV_OUTPUT_PREFERENCE_SHARED_TEXTURE_DXGI_REQUIRE &&
    // !processed_as_gpu_texture) {
    //    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: DXGI shared texture was
    //    required but could not be obtained."); hr = E_FAIL; // Or a more
    //    specific error goto request_next_sample;
    // }

    // buffer.data.video.actual_output_preference_achieved =
    // MINIAV_OUTPUT_PREFERENCE_CPU;

    hr = IMFSample_ConvertToContiguousBuffer(pSample, &media_buffer);
    if (FAILED(hr)) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "MF: Failed to convert to contiguous buffer for CPU path: 0x%X", hr);
      goto request_next_sample;
    }

    hr = IMFMediaBuffer_Lock(media_buffer, &raw_buffer_data, &max_length,
                             &current_length);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: Failed to lock media buffer for CPU path: 0x%X", hr);
      goto request_next_sample;
    }

    buffer_ptr->data.video.planes[0] = raw_buffer_data;

    LONG temp_stride_signed = 0;
    UINT32 stride = 0;

    GUID mf_subtype = MiniAVPixelFormatToMfSubType(
        parent_ctx->configured_format.pixel_format);

    if (!IsEqualGUID(&mf_subtype, &GUID_NULL)) {
      HRESULT hr_stride = MFGetStrideForBitmapInfoHeader(
          mf_subtype.Data1, parent_ctx->configured_format.width,
          &temp_stride_signed);

      if (SUCCEEDED(hr_stride) && temp_stride_signed != 0) {
        stride = (UINT32)abs(temp_stride_signed);
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "MF: Stride from MFGetStrideForBitmapInfoHeader: %ld, abs: %u",
            temp_stride_signed, stride);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "MF: MFGetStrideForBitmapInfoHeader failed (0x%X) or "
                   "returned 0 stride for format %lu (MiniAV format %d), width "
                   "%u. Falling back to manual calculation.",
                   hr_stride, mf_subtype.Data1,
                   parent_ctx->configured_format.pixel_format,
                   parent_ctx->configured_format.width);
      }
    } else {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "MF: Could not map MiniAVPixelFormat %d to MF subtype for "
                 "stride calculation. Falling back to manual calculation.",
                 parent_ctx->configured_format.pixel_format);
    }

    if (stride == 0) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "MF: Using fallback stride calculation for pixel format %d.",
                 buffer_ptr->data.video.pixel_format);
      if (buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_YUY2 ||
          buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_UYVY)
        stride = buffer_ptr->data.video.width * 2;
      else if (buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_RGB24 ||
               buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_BGR24)
        stride = buffer_ptr->data.video.width * 3;
      else if (buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_RGBA32 ||
               buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_BGRA32 ||
               buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_ARGB32 ||
               buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_ABGR32)
        stride = buffer_ptr->data.video.width * 4;
      else if (buffer_ptr->data.video.pixel_format ==
                   MINIAV_PIXEL_FORMAT_NV12 ||
               buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_NV21)
        stride = buffer_ptr->data.video.width;
      else if (buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_I420)
        stride = buffer_ptr->data.video.width;
      else {
        miniav_log(
            MINIAV_LOG_LEVEL_WARN,
            "MF: Unknown pixel format for fallback stride calculation: %d. "
            "Defaulting stride to width * 4.",
            buffer_ptr->data.video.pixel_format);
        stride = buffer_ptr->data.video.width * 4;
      }
    }
    buffer_ptr->data.video.stride_bytes[0] = stride;

    if (buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_NV12 ||
        buffer_ptr->data.video.pixel_format == MINIAV_PIXEL_FORMAT_NV21) {
      buffer_ptr->data.video.planes[1] =
          raw_buffer_data + (stride * buffer_ptr->data.video.height);
      buffer_ptr->data.video.stride_bytes[1] = stride;
    } else if (buffer_ptr->data.video.pixel_format ==
               MINIAV_PIXEL_FORMAT_I420) {
      buffer_ptr->data.video.planes[1] =
          raw_buffer_data + (stride * buffer_ptr->data.video.height);
      buffer_ptr->data.video.stride_bytes[1] = stride / 2;
      buffer_ptr->data.video.planes[2] =
          raw_buffer_data + (stride * buffer_ptr->data.video.height) +
          (stride / 2 * buffer_ptr->data.video.height / 2);
      buffer_ptr->data.video.stride_bytes[2] = stride / 2;
    }
    buffer_ptr->data_size_bytes = current_length;
  }

  // Common path for callback
  buffer_ptr->user_data = mf_ctx->app_callback_user_data_internal;

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)miniav_calloc(
          1, sizeof(MiniAVNativeBufferInternalPayload));
  if (!payload) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate internal handle payload.");
    miniav_free(buffer_ptr); // Free the MiniAVBuffer we just allocated
    if (processed_as_gpu_texture &&
        buffer_ptr->data.video.native_gpu_shared_handle != NULL) {
      CloseHandle(buffer_ptr->data.video.native_gpu_shared_handle);
    }
    hr = E_OUTOFMEMORY;
    goto request_next_sample;
  }
  payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA;
  payload->context_owner = parent_ctx;
  payload->native_resource_ptr = pSample;
  payload->parent_miniav_buffer_ptr =
      buffer_ptr; // Store pointer to the containing MiniAVBuffer

  if (pSample) { // Only AddRef if pSample is not NULL (e.g. not a stream tick
                 // without sample)
    IMFSample_AddRef(pSample);
  }

  buffer_ptr->internal_handle = payload;

  if (mf_ctx->app_callback_internal) {
    mf_ctx->app_callback_internal(
        buffer_ptr, // Pass pointer to heap-allocated struct
        mf_ctx->app_callback_user_data_internal);
  } else {
    // No app callback, release resources we took/created
    if (pSample)
      IMFSample_Release(pSample); // Release the AddRef for payload
    miniav_free(payload);
    miniav_free(buffer_ptr); // Free the MiniAVBuffer as well
    if (processed_as_gpu_texture &&
        buffer_ptr->data.video.native_gpu_shared_handle != NULL) {
      CloseHandle(buffer_ptr->data.video.native_gpu_shared_handle);
    }
  }

  if (raw_buffer_data) { // Only unlock if it was locked (CPU path)
    IMFMediaBuffer_Unlock(media_buffer);
  }
  // Note: If processed_as_gpu_texture, the shared_handle (stored in
  // buffer.data.video.planes[0]) is passed to the application. The application
  // is responsible for calling CloseHandle on it when it's done with the
  // buffer (unless there was no app_callback_internal, in which case we closed
  // it). MiniAV's mf_release_buffer will release the IMFSample.

request_next_sample:
  if (mf_ctx->is_streaming && parent_ctx->is_running && mf_ctx->source_reader) {
    // Only request next sample if the current sample processing was generally
    // successful (hr is S_OK) or if the error was non-fatal for streaming (e.g.
    // a recoverable glitch). For simplicity here, we request next sample if hr
    // is SUCCEEDED. If hr is a failure (e.g. E_FAIL from a required GPU texture
    // not being available, or E_OUTOFMEMORY), we might choose to stop streaming
    // or log and continue trying.
    if (SUCCEEDED(hr)) {
      HRESULT hr_read = IMFSourceReader_ReadSample(
          mf_ctx->source_reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
          NULL, NULL, NULL, NULL);
      if (FAILED(hr_read)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "MF: Failed to request next sample: 0x%X", hr_read);
        mf_ctx->is_streaming = FALSE; // Stop streaming on read error
        // Potentially signal an error to the application through a callback
        // status
      }
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: Not requesting next sample due to error in current "
                 "sample processing: 0x%X",
                 hr);
      // If a "REQUIRE_GPU" preference failed, this is where you might set
      // mf_ctx->is_streaming = FALSE; For GPU_IF_AVAILABLE, a failure to get
      // GPU texture already fell back to CPU, so 'hr' here would reflect issues
      // in CPU path or payload allocation.
    }
  }

done:
  if (media_buffer)
    IMFMediaBuffer_Release(media_buffer);
  LeaveCriticalSection(&mf_ctx->critical_section);
  return S_OK; // Always return S_OK from OnReadSample itself, errors are
               // handled internally
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
  HRESULT hr_com_init;
  HRESULT hr_mf_startup;

  hr_com_init =
      CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  // ... (existing COM init logging and error handling) ...
  if (FAILED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: CoInitializeEx failed: 0x%X",
               hr_com_init);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  hr_mf_startup = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  if (FAILED(hr_mf_startup)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: MFStartup failed: 0x%X",
               hr_mf_startup);
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  MFPlatformContext *mf_ctx =
      (MFPlatformContext *)miniav_calloc(1, sizeof(MFPlatformContext));
  if (!mf_ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to allocate MFPlatformContext.");
    MFShutdown();
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  mf_ctx->lpVtbl = &g_MFPlatformVtbl;
  mf_ctx->ref_count = 1;
  mf_ctx->parent_ctx = ctx;
  mf_ctx->source_reader = NULL;
  mf_ctx->is_streaming = FALSE;
  mf_ctx->dxgi_manager = NULL; // Init new D3D members
  mf_ctx->d3d_device = NULL;
  mf_ctx->d3d_device_context = NULL;
  mf_ctx->dxgi_manager_reset_token = 0;

  if (!InitializeCriticalSectionAndSpinCount(&mf_ctx->critical_section,
                                             0x00000400)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Failed to initialize critical section.");
    miniav_free(mf_ctx);
    MFShutdown();
    if (SUCCEEDED(hr_com_init) && hr_com_init != RPC_E_CHANGED_MODE) {
      CoUninitialize();
    }
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  ctx->platform_ctx = mf_ctx;
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "MF: Platform context initialized successfully.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode mf_destroy_platform(MiniAVCameraContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: Destroying platform context (real).");
  if (ctx && ctx->platform_ctx) {
    MFPlatformContext *mf_ctx = (MFPlatformContext *)ctx->platform_ctx;

    // ... (existing streaming stop and source_reader release) ...
    if (mf_ctx->is_streaming) {
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "MF: Destroying platform while still streaming. Attempting to stop.");
      mf_ctx->is_streaming = FALSE;
      if (mf_ctx->source_reader) {
        IMFSourceReader_Flush(mf_ctx->source_reader,
                              MF_SOURCE_READER_ALL_STREAMS);
      }
    }
    if (mf_ctx->source_reader) {
      IMFSourceReader_Release(mf_ctx->source_reader);
      mf_ctx->source_reader = NULL;
    }

    // Release DirectX objects
    if (mf_ctx->d3d_device_context) {
      ID3D11DeviceContext_Release(mf_ctx->d3d_device_context);
      mf_ctx->d3d_device_context = NULL;
    }
    if (mf_ctx->d3d_device) {
      ID3D11Device_Release(mf_ctx->d3d_device);
      mf_ctx->d3d_device = NULL;
    }
    if (mf_ctx->dxgi_manager) {
      IMFDXGIDeviceManager_Release(mf_ctx->dxgi_manager);
      mf_ctx->dxgi_manager = NULL;
    }

    DeleteCriticalSection(&mf_ctx->critical_section);
    miniav_free(mf_ctx);
    ctx->platform_ctx = NULL;
  }

  MFShutdown();
  CoUninitialize();
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

    uint32_t width = 0, height = 0;
    UINT64 packed_frame_size = 0;
    hr_attr = IMFMediaType_GetUINT64(media_type, &MF_MT_FRAME_SIZE,
                                     &packed_frame_size);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }
    width = (uint32_t)(packed_frame_size >> 32);
    height = (uint32_t)(packed_frame_size & 0xFFFFFFFF);

    uint32_t fr_num = 0, fr_den = 0;
    UINT64 packed_frame_rate = 0;
    hr_attr = IMFMediaType_GetUINT64(media_type, &MF_MT_FRAME_RATE,
                                     &packed_frame_rate);
    if (FAILED(hr_attr)) {
      IMFMediaType_Release(media_type);
      media_type = NULL;
      media_type_index++;
      continue;
    }
    fr_num = (uint32_t)(packed_frame_rate >> 32);
    fr_den = (uint32_t)(packed_frame_rate & 0xFFFFFFFF);

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
    result_formats_list[found_formats].output_preference =
        MINIAV_OUTPUT_PREFERENCE_CPU;

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
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "MF: Configuring device %s with format %ux%u @ %u/%u (approx "
             "%.2f) FPS, PixelFormat %d, OutputPref %d (real).",
             device_id_utf8 ? device_id_utf8
                            : "Default (Error: device_id_utf8 is NULL)",
             format->width, format->height, format->frame_rate_numerator,
             format->frame_rate_denominator, fps_approx, format->pixel_format,
             format->output_preference);

  // set ctx format
  mf_ctx->parent_ctx->configured_format = *format;

  if (!device_id_utf8) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: device_id_utf8 is NULL in mf_configure.");
    return MINIAV_ERROR_INVALID_ARG;
  }
  if (!format) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: format is NULL in mf_configure.");
    return MINIAV_ERROR_INVALID_ARG;
  }

  // --- D3D Device and Manager Setup for GPU output preferences ---
  // Release existing D3D resources if any, before creating new ones for this
  // configuration attempt
  if (mf_ctx->d3d_device_context) {
    ID3D11DeviceContext_Release(mf_ctx->d3d_device_context);
    mf_ctx->d3d_device_context = NULL;
  }
  if (mf_ctx->d3d_device) {
    ID3D11Device_Release(mf_ctx->d3d_device);
    mf_ctx->d3d_device = NULL;
  }
  if (mf_ctx->dxgi_manager) {
    IMFDXGIDeviceManager_Release(mf_ctx->dxgi_manager);
    mf_ctx->dxgi_manager = NULL;
  }
  mf_ctx->dxgi_manager_reset_token = 0;

  // Corrected: Only set use_gpu_preference if a GPU preference is actually
  // selected. If you add more specific GPU enums like
  // _SHARED_TEXTURE_DXGI_REQUIRE or _FALLBACK_CPU, include them in this
  // condition.
  bool use_gpu_preference =
      format->output_preference == MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE;

  if (use_gpu_preference) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "MF: GPU output preference detected, setting up D3D Manager.");
    hr = MFCreateDXGIDeviceManager(&mf_ctx->dxgi_manager_reset_token,
                                   &mf_ctx->dxgi_manager);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: MFCreateDXGIDeviceManager failed: 0x%X", hr);
      // If GPU is "if_available", failing to create D3D manager means we'll
      // just use CPU path. If a "REQUIRE_GPU" type preference existed, this
      // would be a fatal error.
      use_gpu_preference = false; // Disable GPU path as setup failed
    } else {
      // Create D3D11 device
      UINT create_device_flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef _DEBUG
      // create_device_flags |= D3D11_CREATE_DEVICE_DEBUG; // Enable if D3D SDK
      // layers are installed
#endif
      D3D_FEATURE_LEVEL feature_levels[] = {
          D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
          D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
      hr = D3D11CreateDevice(
          NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, create_device_flags,
          feature_levels, ARRAYSIZE(feature_levels), D3D11_SDK_VERSION,
          &mf_ctx->d3d_device, NULL, &mf_ctx->d3d_device_context);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: D3D11CreateDevice failed: 0x%X",
                   hr);
        if (mf_ctx->dxgi_manager) {
          IMFDXGIDeviceManager_Release(mf_ctx->dxgi_manager);
          mf_ctx->dxgi_manager = NULL;
        }
        use_gpu_preference = false; // Disable GPU path
      } else {
        hr = IMFDXGIDeviceManager_ResetDevice(mf_ctx->dxgi_manager,
                                              (IUnknown *)mf_ctx->d3d_device,
                                              mf_ctx->dxgi_manager_reset_token);
        if (FAILED(hr)) {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "MF: IMFDXGIDeviceManager_ResetDevice failed: 0x%X", hr);
          if (mf_ctx->d3d_device_context) {
            ID3D11DeviceContext_Release(mf_ctx->d3d_device_context);
            mf_ctx->d3d_device_context = NULL;
          }
          if (mf_ctx->d3d_device) {
            ID3D11Device_Release(mf_ctx->d3d_device);
            mf_ctx->d3d_device = NULL;
          }
          if (mf_ctx->dxgi_manager) {
            IMFDXGIDeviceManager_Release(mf_ctx->dxgi_manager);
            mf_ctx->dxgi_manager = NULL;
          }
          use_gpu_preference = false; // Disable GPU path
        } else {
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "MF: D3D Manager and Device configured successfully.");
        }
      }
    }
  }
  // --- End D3D Device and Manager Setup ---

  WCHAR target_symbolic_link_wchar[MINIAV_DEVICE_ID_MAX_LEN];
  MultiByteToWideChar(CP_UTF8, 0, device_id_utf8, -1,
                      target_symbolic_link_wchar, MINIAV_DEVICE_ID_MAX_LEN);
  StrCpyNW(mf_ctx->symbolic_link, target_symbolic_link_wchar,
           MINIAV_DEVICE_ID_MAX_LEN);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Attempting to configure with target symbolic link: %ls",
             mf_ctx->symbolic_link);

  IMFAttributes *enum_attributes = NULL;
  IMFActivate **all_video_devices = NULL;
  UINT32 num_video_devices = 0;

  hr = MFCreateAttributes(&enum_attributes, 1);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFCreateAttributes for enumeration failed: 0x%X", hr);
    goto error_cleanup_no_device_activate_release;
  }

  hr = IMFAttributes_SetGUID(enum_attributes,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: SetGUID for VIDCAP_GUID failed: 0x%X", hr);
    IMFAttributes_Release(enum_attributes);
    enum_attributes = NULL;
    goto error_cleanup_no_device_activate_release;
  }

  hr = MFEnumDeviceSources(enum_attributes, &all_video_devices,
                           &num_video_devices);
  IMFAttributes_Release(enum_attributes);
  enum_attributes = NULL;

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: MFEnumDeviceSources (to find specific link) failed: 0x%X",
               hr);
    goto error_cleanup_no_device_activate_release;
  }

  if (num_video_devices == 0) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "MF: No video capture devices found during configuration search.");
    hr = MF_E_NOT_FOUND; // Or MINIAV_ERROR_DEVICE_NOT_FOUND
    goto error_cleanup_no_device_activate_release;
  }

  for (UINT32 i = 0; i < num_video_devices; ++i) {
    WCHAR *current_sym_link_iter = NULL;
    HRESULT hr_link = IMFActivate_GetAllocatedString(
        all_video_devices[i],
        &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        &current_sym_link_iter, NULL);
    if (SUCCEEDED(hr_link)) {
      if (wcscmp(mf_ctx->symbolic_link, current_sym_link_iter) == 0) {
        device_activate = all_video_devices[i];
        IMFActivate_AddRef(device_activate); // We are keeping this one
      }
      CoTaskMemFree(current_sym_link_iter);
    }
    if (device_activate) {
      break; // Found our device
    }
  }

  if (all_video_devices) {
    for (UINT32 i = 0; i < num_video_devices; ++i) {
      if (all_video_devices[i] != device_activate) { // Release those not chosen
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
    hr = MF_E_NOT_FOUND; // Or MINIAV_ERROR_DEVICE_NOT_FOUND
    goto error_cleanup_no_device_activate_release;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Found matching IMFActivate for configuration using link: %ls",
             mf_ctx->symbolic_link);

  if (mf_ctx->source_reader) {
    IMFSourceReader_Release(mf_ctx->source_reader);
    mf_ctx->source_reader = NULL;
  }
  if (media_source) { // Should be NULL here, but defensive
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

  hr = MFCreateAttributes(&reader_attributes, use_gpu_preference ? 2 : 1);
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

  if (use_gpu_preference &&
      mf_ctx->dxgi_manager) { // Only set if D3D manager was successfully
                              // created and GPU pref is active
    hr = IMFAttributes_SetUnknown(reader_attributes,
                                  &MF_SOURCE_READER_D3D_MANAGER,
                                  (IUnknown *)mf_ctx->dxgi_manager);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: Failed to set D3D_MANAGER attribute: 0x%X", hr);
      // If GPU is "if_available", failing to set this attribute means we'll
      // likely get CPU samples. This is not necessarily fatal for
      // "if_available". If a "REQUIRE_GPU" preference existed, this could be an
      // error.
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "MF: MF_SOURCE_READER_D3D_MANAGER attribute set.");
    }
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
  while (TRUE) {
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
        hr = hr_loop_check; // Propagate error
      }
      break; // Exit loop on error or no more types
    }

    if (target_media_type == NULL) { // Should not happen if SUCCEEDED
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "MF: GetNativeMediaType SUCCEEDED but target_media_type is "
                 "NULL! Index: %u.",
                 media_type_index);
      hr = E_UNEXPECTED;
      goto error_cleanup; // Critical unexpected state
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

        hr = IMFSourceReader_SetCurrentMediaType(
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
          // hr is already set with the failure code
        }
        IMFMediaType_Release(target_media_type);
        target_media_type = NULL;
        break; // Exit loop (either success or failure in SetCurrentMediaType)
      }
    }

    IMFMediaType_Release(target_media_type);
    target_media_type = NULL;
    media_type_index++;
  }

  if (FAILED(hr)) { // If GetNativeMediaType or SetCurrentMediaType failed
    goto error_cleanup;
  }

  if (!found_match) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "MF: Could not find or set matching media type for "
               "configuration. Target: %ux%u @ %u/%u FPS, PixelFormat %d",
               format->width, format->height, format->frame_rate_numerator,
               format->frame_rate_denominator, format->pixel_format);
    hr = MF_E_INVALIDMEDIATYPE; // Specific error for no matching type
    goto error_cleanup;
  }

  // Configuration successful
  mf_ctx->app_callback_internal = ctx->app_callback;
  mf_ctx->app_callback_user_data_internal = ctx->app_callback_user_data;
  ctx->configured_format = *format;
  mf_ctx->parent_ctx->configured_format = *format;
  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "MF: mf_configure - ctx->configured_format.pixel_format set to %d (0x%X)",
      ctx->configured_format.pixel_format, ctx->configured_format.pixel_format);

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "MF: Configured device %ls successfully (real).",
             mf_ctx->symbolic_link);

  // Normal successful exit path releases
  if (target_media_type)
    IMFMediaType_Release(
        target_media_type); // Should be NULL if loop exited cleanly
  if (reader_attributes)
    IMFAttributes_Release(reader_attributes);
  if (media_source)
    IMFMediaSource_Release(media_source);
  if (device_activate)
    IMFActivate_Release(device_activate); // Was AddRef'd

  return MINIAV_SUCCESS;

error_cleanup: // For errors after device_activate is AddRef'd
  if (device_activate)
    IMFActivate_Release(device_activate);
error_cleanup_no_device_activate_release: // For errors before device_activate
                                          // is AddRef'd or if it's from
                                          // all_video_devices
  if (target_media_type)
    IMFMediaType_Release(target_media_type);
  if (reader_attributes)
    IMFAttributes_Release(reader_attributes);
  if (media_source)
    IMFMediaSource_Release(media_source);
  // device_activate is handled by the more specific labels or was never
  // set/already released from all_video_devices

  if (mf_ctx->source_reader) { // Clean up source reader on any failure path
    IMFSourceReader_Release(mf_ctx->source_reader);
    mf_ctx->source_reader = NULL;
  }
  // D3D resources are released at the start of this function if they existed,
  // or should be released in mf_destroy_platform if this configure fails
  // and they were partially created.
  // For robustness, ensure they are cleared if this function fails after their
  // creation.
  if (FAILED(hr)) { // Ensure D3D resources are cleared if configure fails after
                    // their setup
    if (mf_ctx->d3d_device_context) {
      ID3D11DeviceContext_Release(mf_ctx->d3d_device_context);
      mf_ctx->d3d_device_context = NULL;
    }
    if (mf_ctx->d3d_device) {
      ID3D11Device_Release(mf_ctx->d3d_device);
      mf_ctx->d3d_device = NULL;
    }
    if (mf_ctx->dxgi_manager) {
      IMFDXGIDeviceManager_Release(mf_ctx->dxgi_manager);
      mf_ctx->dxgi_manager = NULL;
    }
  }

  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "MF: mf_configure failed for %s with HRESULT 0x%X",
             device_id_utf8 ? device_id_utf8 : "Unknown Device", hr);
  return (hr == MF_E_INVALIDMEDIATYPE || hr == MF_E_NOT_FOUND)
             ? MINIAV_ERROR_NOT_SUPPORTED
             : MINIAV_ERROR_SYSTEM_CALL_FAILED;
}

static MiniAVResultCode
mf_release_buffer(MiniAVCameraContext *ctx,
                  void *native_buffer_payload_resource_ptr) {
  MINIAV_UNUSED(ctx); // ctx might be used for logging or specific checks later
  if (!native_buffer_payload_resource_ptr) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "MF: mf_release_buffer called with NULL payload resource ptr.");
    return MINIAV_ERROR_INVALID_ARG;
  }

  IMFSample *pSample = (IMFSample *)native_buffer_payload_resource_ptr;

  // The MiniAVNativeBufferInternalPayload that holds this pSample
  // (and for which IMFSample_AddRef was called in OnReadSample)
  // is freed by the caller (miniav_buffer_release).
  // This function's job is to release the native resource (IMFSample)
  // that was AddRef'd for the payload.

  ULONG ref_count_after_release = IMFSample_Release(pSample);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "MF: Released IMFSample via mf_release_buffer. Ref count after "
             "release: %lu",
             ref_count_after_release);

  // If the MiniAVBuffer passed to the user contained a shared_texture_handle
  // (HANDLE), the application is responsible for calling CloseHandle on it when
  // it's done. If it contained a native_gpu_texture_ptr (e.g.,
  // ID3D11Texture2D*) that was AddRef'd specifically for the application's use
  // (beyond the IMFSample's ownership), the application would also be
  // responsible for Releasing that. This function primarily manages the
  // IMFSample's lifetime as tracked by the internal payload.

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
  mf_ctx->parent_ctx->configured_format = ctx->configured_format;
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
