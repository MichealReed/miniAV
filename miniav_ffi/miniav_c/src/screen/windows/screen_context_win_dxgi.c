#define COBJMACROS // Enables C-style COM interface calling
#include "screen_context_win_dxgi.h"
#include "../../../include/miniav.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h" // For miniav_get_qpc_microseconds, miniav_get_qpc_frequency
#include "../../common/miniav_utils.h"

#include <d3d11.h>
#include <dxgi1_2.h> // For IDXGIOutputDuplication
#include <stdio.h>   // For _snprintf_s
#include <windows.h>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

// Enum for payload type
typedef enum DXGIPayloadType {
  DXGI_PAYLOAD_TYPE_CPU,
  DXGI_PAYLOAD_TYPE_GPU
} DXGIPayloadType;

// Payload for releasing DXGI frame resources
typedef struct DXGIFrameReleasePayload {
  DXGIPayloadType type;
  union {
    struct {                                      // For CPU
      ID3D11Texture2D *staging_texture_for_frame; // AddRef'd
      ID3D11DeviceContext *d3d_context_for_unmap; // Pointer, not AddRef'd
      UINT subresource_for_unmap;
    } cpu;
    struct {                               // For GPU
      ID3D11Texture2D *shared_gpu_texture; // AddRef'd (texture from which
                                           // handle was created)
    } gpu;
  };
} DXGIFrameReleasePayload;

typedef struct DXGIScreenPlatformContext {
  MiniAVScreenContext *parent_ctx; // Pointer back to the main MiniAV context

  IDXGIOutputDuplication *output_duplication;
  ID3D11Device *d3d_device;
  ID3D11DeviceContext *d3d_context;
  ID3D11Texture2D
      *staging_texture; // General staging texture, or per-frame if needed

  DXGI_OUTPUT_DESC output_desc;
  UINT adapter_index_internal;
  UINT output_index_internal;
  char selected_device_id[MINIAV_DEVICE_ID_MAX_LEN];

  MiniAVBufferCallback app_callback_internal;
  void *app_callback_user_data_internal;

  BOOL is_streaming;
  HANDLE capture_thread_handle;
  HANDLE stop_event_handle;
  CRITICAL_SECTION critical_section; // For thread-safe access to shared members

  MiniAVVideoInfo configured_video_format; // Store user's requested format
                                           // (FPS, output_preference)
  UINT target_fps;
  UINT frame_width;               // Actual width from DXGI
  UINT frame_height;              // Actual height from DXGI
  MiniAVPixelFormat pixel_format; // Should be BGRA32 for DXGI

  LARGE_INTEGER qpc_frequency;

  // --- Audio Loopback Members ---
  MiniAVLoopbackContextHandle loopback_audio_ctx;
  BOOL audio_loopback_enabled_and_configured;
  MiniAVAudioInfo configured_audio_format;

} DXGIScreenPlatformContext;

// --- Forward declarations for static functions ---
static DWORD WINAPI dxgi_capture_thread_proc(LPVOID param);
static MiniAVResultCode
dxgi_init_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx,
                              UINT adapter_idx, UINT output_idx);
static void
dxgi_cleanup_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx);

// --- Platform Ops Implementation ---

static MiniAVResultCode dxgi_init_platform(MiniAVScreenContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Initializing platform context.");
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;

  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)miniav_calloc(
          1, sizeof(DXGIScreenPlatformContext));
  if (!dxgi_ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to allocate DXGIScreenPlatformContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  dxgi_ctx->parent_ctx = ctx;
  ctx->platform_ctx = dxgi_ctx;
  dxgi_ctx->pixel_format =
      MINIAV_PIXEL_FORMAT_BGRA32; // Default for DXGI desktop duplication
  dxgi_ctx->stop_event_handle = CreateEvent(
      NULL, TRUE, FALSE, NULL); // Manual-reset, initially non-signaled
  if (dxgi_ctx->stop_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to create stop event.");
    miniav_free(dxgi_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!InitializeCriticalSectionAndSpinCount(&dxgi_ctx->critical_section,
                                             0x00000400)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to initialize critical section.");
    CloseHandle(dxgi_ctx->stop_event_handle);
    miniav_free(dxgi_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  dxgi_ctx->qpc_frequency = miniav_get_qpc_frequency();
  dxgi_ctx->loopback_audio_ctx = NULL; // Initialize audio loopback members
  dxgi_ctx->audio_loopback_enabled_and_configured = FALSE;

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "DXGI: Platform context initialized successfully.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode dxgi_destroy_platform(MiniAVScreenContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Destroying platform context.");
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;

  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)ctx->platform_ctx;

  if (dxgi_ctx->is_streaming) {
    miniav_log(
        MINIAV_LOG_LEVEL_WARN,
        "DXGI: Platform being destroyed while streaming. Attempting to stop.");
    // This should have been called by MiniAV_Screen_StopCapture
    // Ensure audio is stopped first if it was running
    if (dxgi_ctx->loopback_audio_ctx &&
        dxgi_ctx->audio_loopback_enabled_and_configured) {
      MiniAV_Loopback_StopCapture(dxgi_ctx->loopback_audio_ctx);
    }
    if (dxgi_ctx->stop_event_handle)
      SetEvent(dxgi_ctx->stop_event_handle);
    if (dxgi_ctx->capture_thread_handle) {
      WaitForSingleObject(dxgi_ctx->capture_thread_handle, INFINITE);
      CloseHandle(dxgi_ctx->capture_thread_handle);
      dxgi_ctx->capture_thread_handle = NULL;
    }
    dxgi_ctx->is_streaming = FALSE;
  }

  dxgi_cleanup_d3d_and_duplication(dxgi_ctx);

  // Destroy loopback audio context if it exists
  if (dxgi_ctx->loopback_audio_ctx) {
    MiniAV_Loopback_DestroyContext(dxgi_ctx->loopback_audio_ctx);
    dxgi_ctx->loopback_audio_ctx = NULL;
    dxgi_ctx->audio_loopback_enabled_and_configured = FALSE;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI: Loopback audio context destroyed.");
  }

  if (dxgi_ctx->stop_event_handle) {
    CloseHandle(dxgi_ctx->stop_event_handle);
    dxgi_ctx->stop_event_handle = NULL;
  }
  DeleteCriticalSection(&dxgi_ctx->critical_section);

  miniav_free(dxgi_ctx);
  ctx->platform_ctx = NULL;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode dxgi_enumerate_displays(MiniAVDeviceInfo **displays_out,
                                                uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Enumerating displays.");
  if (!displays_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *displays_out = NULL;
  *count_out = 0;

  HRESULT hr;
  IDXGIFactory1 *factory = NULL;
  MiniAVDeviceInfo *result_devices = NULL;
  uint32_t current_device_count = 0;
  uint32_t allocated_devices = 0;

  hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to create DXGIFactory1: 0x%X", hr);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  IDXGIAdapter1 *adapter = NULL;
  for (UINT i = 0;
       factory && SUCCEEDED(IDXGIFactory1_EnumAdapters1(factory, i, &adapter));
       ++i) {
    IDXGIOutput *output = NULL;
    for (UINT j = 0;
         adapter && SUCCEEDED(IDXGIAdapter1_EnumOutputs(adapter, j, &output));
         ++j) {
      DXGI_OUTPUT_DESC desc;
      if (SUCCEEDED(IDXGIOutput_GetDesc(output, &desc))) {
        if (current_device_count >= allocated_devices) {
          allocated_devices =
              (allocated_devices == 0) ? 4 : allocated_devices * 2;
          MiniAVDeviceInfo *new_list = (MiniAVDeviceInfo *)miniav_realloc(
              result_devices, allocated_devices * sizeof(MiniAVDeviceInfo));
          if (!new_list) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR,
                       "DXGI: Failed to reallocate device list.");
            miniav_free(result_devices);
            if (output)
              IDXGIOutput_Release(output);
            if (adapter)
              IDXGIAdapter1_Release(adapter);
            IDXGIFactory1_Release(factory);
            return MINIAV_ERROR_OUT_OF_MEMORY;
          }
          result_devices = new_list;
        }

        MiniAVDeviceInfo *current_device_info =
            &result_devices[current_device_count];
        memset(current_device_info, 0, sizeof(MiniAVDeviceInfo));

        // Create a unique ID like "Adapter0_Output0"
        _snprintf_s(current_device_info->device_id, MINIAV_DEVICE_ID_MAX_LEN,
                    _TRUNCATE, "Adapter%u_Output%u", i, j);

        // Convert monitor name (WCHAR) to UTF-8
        WideCharToMultiByte(CP_UTF8, 0, desc.DeviceName, -1,
                            current_device_info->name,
                            MINIAV_DEVICE_NAME_MAX_LEN, NULL, NULL);

        current_device_info->is_default =
            (desc.DesktopCoordinates.left == 0 &&
             desc.DesktopCoordinates.top == 0); // Simplistic default check

        current_device_count++;
      }
      if (output)
        IDXGIOutput_Release(output);
      output = NULL;
    }
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    adapter = NULL;
  }

  if (factory)
    IDXGIFactory1_Release(factory);

  *displays_out = result_devices;
  *count_out = current_device_count;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Enumerated %u displays.",
             current_device_count);
  return MINIAV_SUCCESS;
}

static MiniAVResultCode dxgi_enumerate_windows(MiniAVDeviceInfo **windows_out,
                                               uint32_t *count_out) {
  MINIAV_UNUSED(windows_out);
  MINIAV_UNUSED(count_out);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "DXGI: EnumerateWindows is not supported by DXGI backend.");
  return MINIAV_ERROR_NOT_SUPPORTED;
}

static MiniAVResultCode
dxgi_init_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx,
                              UINT adapter_idx, UINT output_idx) {
  HRESULT hr;
  IDXGIFactory1 *factory = NULL;
  IDXGIAdapter1 *adapter = NULL;
  IDXGIOutput *output = NULL;
  IDXGIOutput1 *output1 = NULL;

  dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // Clean up any previous state

  hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to create DXGIFactory1 for duplication: 0x%X", hr);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (FAILED(IDXGIFactory1_EnumAdapters1(factory, adapter_idx, &adapter))) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to get adapter %u.",
               adapter_idx);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_DEVICE_NOT_FOUND;
  }

  D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  hr = D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, 0,
                         feature_levels, ARRAYSIZE(feature_levels),
                         D3D11_SDK_VERSION, &dxgi_ctx->d3d_device, NULL,
                         &dxgi_ctx->d3d_context);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: D3D11CreateDevice failed: 0x%X",
               hr);
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (FAILED(IDXGIAdapter1_EnumOutputs(adapter, output_idx, &output))) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to get output %u on adapter %u.", output_idx,
               adapter_idx);
    dxgi_cleanup_d3d_and_duplication(dxgi_ctx); // Releases D3D device/context
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_DEVICE_NOT_FOUND;
  }

  if (FAILED(IDXGIOutput_QueryInterface(output, &IID_IDXGIOutput1,
                                        (void **)&output1))) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: Failed to query IDXGIOutput1.");
    dxgi_cleanup_d3d_and_duplication(dxgi_ctx);
    if (output)
      IDXGIOutput_Release(output);
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  hr = IDXGIOutput1_DuplicateOutput(output1, (IUnknown *)dxgi_ctx->d3d_device,
                                    &dxgi_ctx->output_duplication);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: DuplicateOutput failed: 0x%X",
               hr);
    dxgi_cleanup_d3d_and_duplication(dxgi_ctx);
    // Release sequence
    if (output1)
      IDXGIOutput1_Release(output1);
    if (output)
      IDXGIOutput_Release(output);
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  IDXGIOutput_GetDesc(output, &dxgi_ctx->output_desc);
  dxgi_ctx->frame_width = dxgi_ctx->output_desc.DesktopCoordinates.right -
                          dxgi_ctx->output_desc.DesktopCoordinates.left;
  dxgi_ctx->frame_height = dxgi_ctx->output_desc.DesktopCoordinates.bottom -
                           dxgi_ctx->output_desc.DesktopCoordinates.top;

  // Create staging texture
  D3D11_TEXTURE2D_DESC staging_desc;
  ZeroMemory(&staging_desc, sizeof(staging_desc));
  staging_desc.Width = dxgi_ctx->frame_width;
  staging_desc.Height = dxgi_ctx->frame_height;
  staging_desc.MipLevels = 1;
  staging_desc.ArraySize = 1;
  staging_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; // Common desktop format
  staging_desc.SampleDesc.Count = 1;
  staging_desc.Usage = D3D11_USAGE_STAGING;
  staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

  hr = ID3D11Device_CreateTexture2D(dxgi_ctx->d3d_device, &staging_desc, NULL,
                                    &dxgi_ctx->staging_texture);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to create staging texture: 0x%X", hr);
    dxgi_cleanup_d3d_and_duplication(
        dxgi_ctx); // This will release output_duplication too
    if (output1)
      IDXGIOutput1_Release(output1);
    if (output)
      IDXGIOutput_Release(output);
    if (adapter)
      IDXGIAdapter1_Release(adapter);
    IDXGIFactory1_Release(factory);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (output1)
    IDXGIOutput1_Release(output1);
  if (output)
    IDXGIOutput_Release(output);
  if (adapter)
    IDXGIAdapter1_Release(adapter);
  if (factory)
    IDXGIFactory1_Release(factory);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "DXGI: D3D and Duplication initialized for Adapter%u Output%u.",
             adapter_idx, output_idx);
  return MINIAV_SUCCESS;
}

static void
dxgi_cleanup_d3d_and_duplication(DXGIScreenPlatformContext *dxgi_ctx) {
  if (dxgi_ctx->output_duplication) {
    IDXGIOutputDuplication_Release(dxgi_ctx->output_duplication);
    dxgi_ctx->output_duplication = NULL;
  }
  if (dxgi_ctx->staging_texture) {
    ID3D11Texture2D_Release(dxgi_ctx->staging_texture);
    dxgi_ctx->staging_texture = NULL;
  }
  if (dxgi_ctx->d3d_context) {
    ID3D11DeviceContext_Release(dxgi_ctx->d3d_context);
    dxgi_ctx->d3d_context = NULL;
  }
  if (dxgi_ctx->d3d_device) {
    ID3D11Device_Release(dxgi_ctx->d3d_device);
    dxgi_ctx->d3d_device = NULL;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "DXGI: D3D and Duplication resources cleaned up.");
}

static MiniAVResultCode
dxgi_get_default_formats(const char *device_id_utf8,
                         MiniAVVideoInfo *video_format_out,
                         MiniAVAudioInfo *audio_format_out) {
  if (!device_id_utf8 || !video_format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  memset(video_format_out, 0, sizeof(MiniAVVideoInfo));
  if (audio_format_out) {
    memset(audio_format_out, 0, sizeof(MiniAVAudioInfo));
  }

  unsigned int adapter_idx = 0, output_idx = 0;
  if (sscanf_s(device_id_utf8, "Adapter%u_Output%u", &adapter_idx,
               &output_idx) != 2) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI GetDefaultFormats: Invalid display_id format: %s. "
               "Expected AdapterX_OutputY.",
               device_id_utf8);
    return MINIAV_ERROR_INVALID_ARG;
  }

  // --- Video Format ---
  video_format_out->pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // DXGI default
  video_format_out->frame_rate_numerator = 60;                 // Common default
  video_format_out->frame_rate_denominator = 1;
  video_format_out->output_preference =
      MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE; // Default preference

  // Get display dimensions
  HRESULT hr;
  IDXGIFactory1 *factory = NULL;
  IDXGIAdapter1 *adapter = NULL;
  IDXGIOutput *output = NULL;
  BOOL found_output = FALSE;

  hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI GetDefaultFormats: Failed to create DXGIFactory1: 0x%X",
               hr);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (SUCCEEDED(IDXGIFactory1_EnumAdapters1(factory, adapter_idx, &adapter))) {
    if (SUCCEEDED(IDXGIAdapter1_EnumOutputs(adapter, output_idx, &output))) {
      DXGI_OUTPUT_DESC desc;
      if (SUCCEEDED(IDXGIOutput_GetDesc(output, &desc))) {
        video_format_out->width =
            desc.DesktopCoordinates.right - desc.DesktopCoordinates.left;
        video_format_out->height =
            desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top;
        found_output = TRUE;
      } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "DXGI GetDefaultFormats: GetDesc failed for %s",
                   device_id_utf8);
      }
      IDXGIOutput_Release(output);
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "DXGI GetDefaultFormats: Failed to enum output %u for adapter %u",
          output_idx, adapter_idx);
    }
    IDXGIAdapter1_Release(adapter);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI GetDefaultFormats: Failed to enum adapter %u",
               adapter_idx);
  }
  IDXGIFactory1_Release(factory);

  if (!found_output) {
    return MINIAV_ERROR_DEVICE_NOT_FOUND;
  }
  if (video_format_out->width == 0 || video_format_out->height == 0) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "DXGI GetDefaultFormats: Target %s has zero width or height.",
               device_id_utf8);
    // Allow proceeding, but this is unusual.
  }

  // --- Audio Format (Optional) ---
  if (audio_format_out) {
    // For DXGI, we always query the system default audio output for loopback
    // as it captures the entire screen.
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI GetDefaultFormats: Querying system default audio format.");
    MiniAVResultCode audio_res =
        MiniAV_Loopback_GetDefaultFormat(NULL, audio_format_out);
    if (audio_res != MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "DXGI GetDefaultFormats: Failed to get default audio format "
                 "for %s: %s. Audio format not set.",
                 device_id_utf8, MiniAV_GetErrorString(audio_res));
      // audio_format_out is already zeroed
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI GetDefaultFormats: Default audio format for target %s: "
                 "Format=%d, Ch=%u, Rate=%u",
                 device_id_utf8, audio_format_out->format,
                 audio_format_out->channels, audio_format_out->sample_rate);
    }
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "DXGI GetDefaultFormats: Video: %ux%u @ %u/%u FPS, PixelFormat: "
             "%d. Audio queried: %s",
             video_format_out->width, video_format_out->height,
             video_format_out->frame_rate_numerator,
             video_format_out->frame_rate_denominator,
             video_format_out->pixel_format, audio_format_out ? "Yes" : "No");

  return MINIAV_SUCCESS;
}

static MiniAVResultCode
dxgi_get_configured_video_formats(MiniAVScreenContext *ctx,
                            MiniAVVideoInfo *video_format_out,
                            MiniAVAudioInfo *audio_format_out) {
  if (!ctx || !ctx->platform_ctx || !video_format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)ctx->platform_ctx;

  memset(video_format_out, 0, sizeof(MiniAVVideoInfo));
  if (audio_format_out) {
    memset(audio_format_out, 0, sizeof(MiniAVAudioInfo));
  }

  if (!ctx->is_configured) { // is_configured is set by the main API after
                             // successful configure_xxx
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "DXGI GetConfiguredFormats: Context not configured.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  // Video format is stored in the parent context's configured_video_format
  // which is updated by dxgi_configure_display
  *video_format_out = ctx->configured_video_format;

  // Audio format
  if (audio_format_out) {
    if (dxgi_ctx->audio_loopback_enabled_and_configured) {
      *audio_format_out = dxgi_ctx->configured_audio_format;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI GetConfiguredFormats: Audio: Format=%d, Ch=%u, Rate=%u",
                 audio_format_out->format, audio_format_out->channels,
                 audio_format_out->sample_rate);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI GetConfiguredFormats: Audio loopback not enabled or not "
                 "configured. Audio format not set.");
      // audio_format_out remains zeroed
    }
  }

  miniav_log(
      MINIAV_LOG_LEVEL_INFO,
      "DXGI GetConfiguredFormats: Video: %ux%u @ %u/%u FPS, PixelFormat: %d. "
      "Audio configured: %s",
      video_format_out->width, video_format_out->height,
      video_format_out->frame_rate_numerator,
      video_format_out->frame_rate_denominator, video_format_out->pixel_format,
      (dxgi_ctx->audio_loopback_enabled_and_configured && audio_format_out)
          ? "Yes"
          : "No/Not Requested");

  return MINIAV_SUCCESS;
}

static MiniAVResultCode
dxgi_configure_display(MiniAVScreenContext *ctx, const char *display_id_utf8,
                       const MiniAVVideoInfo *format, bool *audio_enabled) {
  if (!ctx || !ctx->platform_ctx || !display_id_utf8 || !format)
    return MINIAV_ERROR_INVALID_ARG;
  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)ctx->platform_ctx;

  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "DXGI: Configuring display ID: %s, Target FPS: %u/%u, OutputPref: %d",
      display_id_utf8, format->frame_rate_numerator,
      format->frame_rate_denominator, format->output_preference);

  // Parse display_id_utf8 (e.g., "AdapterX_OutputY")
  unsigned int adapter_idx = 0, output_idx = 0;
  if (sscanf_s(display_id_utf8, "Adapter%u_Output%u", &adapter_idx,
               &output_idx) != 2) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "DXGI: Invalid display_id format: %s. Expected AdapterX_OutputY.",
        display_id_utf8);
    return MINIAV_ERROR_INVALID_ARG;
  }

  EnterCriticalSection(&dxgi_ctx->critical_section);
  if (dxgi_ctx->is_streaming) {
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Cannot configure while streaming.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }

  // Clean up previous audio context if any
  if (dxgi_ctx->loopback_audio_ctx) {
    MiniAV_Loopback_DestroyContext(dxgi_ctx->loopback_audio_ctx);
    dxgi_ctx->loopback_audio_ctx = NULL;
    dxgi_ctx->audio_loopback_enabled_and_configured = FALSE;
  }

  MiniAVResultCode res =
      dxgi_init_d3d_and_duplication(dxgi_ctx, adapter_idx, output_idx);
  if (res != MINIAV_SUCCESS) {
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    return res;
  }

  dxgi_ctx->adapter_index_internal = adapter_idx;
  dxgi_ctx->output_index_internal = output_idx;
  strncpy_s(dxgi_ctx->selected_device_id, MINIAV_DEVICE_ID_MAX_LEN,
            display_id_utf8, _TRUNCATE);

  dxgi_ctx->configured_video_format =
      *format; // Store the requested format including output_preference
  if (format->frame_rate_denominator > 0 && format->frame_rate_numerator > 0) {
    dxgi_ctx->target_fps =
        format->frame_rate_numerator / format->frame_rate_denominator;
  } else {
    dxgi_ctx->target_fps = 30; // Default FPS if not specified or invalid
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "DXGI: Invalid target FPS in format, defaulting to %u FPS.",
               dxgi_ctx->target_fps);
  }
  if (dxgi_ctx->target_fps == 0)
    dxgi_ctx->target_fps = 1; // Ensure at least 1 FPS to avoid division by zero

  // Actual width, height, and pixel format are determined by DXGI, stored
  // during init_d3d_and_duplication
  ctx->configured_video_format.width = dxgi_ctx->frame_width;
  ctx->configured_video_format.height = dxgi_ctx->frame_height;
  ctx->configured_video_format.pixel_format =
      dxgi_ctx->pixel_format; // Should be BGRA32
  ctx->configured_video_format.frame_rate_numerator = dxgi_ctx->target_fps;
  ctx->configured_video_format.frame_rate_denominator = 1;
  ctx->configured_video_format.output_preference =
      dxgi_ctx->configured_video_format
          .output_preference; // Ensure parent context also has it

  // --- Configure Audio Loopback ---
  dxgi_ctx->audio_loopback_enabled_and_configured = FALSE; // Default to false
  if (dxgi_ctx->parent_ctx->capture_audio_requested) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI: Attempting to configure audio loopback.");
    res = MiniAV_Loopback_CreateContext(&dxgi_ctx->loopback_audio_ctx);
    if (res == MINIAV_SUCCESS) {
      MiniAVAudioInfo desired_audio_format;
      memset(&desired_audio_format, 0, sizeof(MiniAVAudioInfo));
      desired_audio_format.format =
          MINIAV_AUDIO_FORMAT_F32;              // Request float 32-bit
      desired_audio_format.channels = 2;        // Stereo
      desired_audio_format.sample_rate = 48000; // 48kHz

      // Configure for default system audio output loopback
      res = MiniAV_Loopback_Configure(dxgi_ctx->loopback_audio_ctx, NULL,
                                      &desired_audio_format);
      if (res == MINIAV_SUCCESS) {
        res = MiniAV_Loopback_GetConfiguredFormat(
            dxgi_ctx->loopback_audio_ctx, &dxgi_ctx->configured_audio_format);
        if (res == MINIAV_SUCCESS) {
          dxgi_ctx->audio_loopback_enabled_and_configured = TRUE;
          miniav_log(
              MINIAV_LOG_LEVEL_INFO,
              "DXGI: Audio loopback configured successfully. Format: %d, "
              "Channels: %u, Rate: %u",
              dxgi_ctx->configured_audio_format.format,
              dxgi_ctx->configured_audio_format.channels,
              dxgi_ctx->configured_audio_format.sample_rate);
        } else {
          miniav_log(
              MINIAV_LOG_LEVEL_WARN,
              "DXGI: Failed to get configured audio loopback format: %s. "
              "Audio disabled.",
              MiniAV_GetErrorString(res));
          MiniAV_Loopback_DestroyContext(dxgi_ctx->loopback_audio_ctx);
          dxgi_ctx->loopback_audio_ctx = NULL;
        }
      } else {
        miniav_log(
            MINIAV_LOG_LEVEL_WARN,
            "DXGI: Failed to configure audio loopback: %s. Audio disabled.",
            MiniAV_GetErrorString(res));
        MiniAV_Loopback_DestroyContext(dxgi_ctx->loopback_audio_ctx);
        dxgi_ctx->loopback_audio_ctx = NULL;
      }
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "DXGI: Failed to create audio loopback context: %s. Audio disabled.",
          MiniAV_GetErrorString(res));
      // loopback_audio_ctx is already NULL or will be set to NULL
    }
  }
  // --- End Audio Loopback Configuration ---

  LeaveCriticalSection(&dxgi_ctx->critical_section);
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "DXGI: Configured for display %s. Actual resolution: %ux%u, "
             "Target FPS: %u. Audio Loopback: %s",
             display_id_utf8, dxgi_ctx->frame_width, dxgi_ctx->frame_height,
             dxgi_ctx->target_fps,
             dxgi_ctx->audio_loopback_enabled_and_configured ? "Enabled"
                                                             : "Disabled");
  return MINIAV_SUCCESS; // Return success even if audio loopback failed, video
                         // can still work
}

static MiniAVResultCode
dxgi_configure_window(MiniAVScreenContext *ctx, const char *window_id_utf8,
                      const MiniAVVideoInfo *format) {
  MINIAV_UNUSED(ctx);
  MINIAV_UNUSED(window_id_utf8);
  MINIAV_UNUSED(format);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "DXGI: ConfigureWindow is not supported by DXGI backend.");
  return MINIAV_ERROR_NOT_SUPPORTED;
}

static MiniAVResultCode
dxgi_configure_region(MiniAVScreenContext *ctx, const char *display_id_utf8,
                      int x, int y, int width, int height,
                      const MiniAVVideoInfo *format) {
  MINIAV_UNUSED(ctx);
  MINIAV_UNUSED(display_id_utf8);
  MINIAV_UNUSED(x);
  MINIAV_UNUSED(y);
  MINIAV_UNUSED(width);
  MINIAV_UNUSED(height);
  MINIAV_UNUSED(format);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "DXGI: ConfigureRegion is not supported by DXGI backend (full "
             "display capture only).");
  return MINIAV_ERROR_NOT_SUPPORTED;
}

static MiniAVResultCode dxgi_start_capture(MiniAVScreenContext *ctx,
                                           MiniAVBufferCallback callback,
                                           void *user_data) {
  if (!ctx || !ctx->platform_ctx || !callback)
    return MINIAV_ERROR_INVALID_ARG;
  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)ctx->platform_ctx;
  MiniAVResultCode res = MINIAV_SUCCESS;

  EnterCriticalSection(&dxgi_ctx->critical_section);
  if (dxgi_ctx->is_streaming) {
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_WARN, "DXGI: Capture already started.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  if (!dxgi_ctx->output_duplication || !dxgi_ctx->staging_texture) {
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Not configured. Call ConfigureDisplay first.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  dxgi_ctx->app_callback_internal = callback;
  dxgi_ctx->app_callback_user_data_internal = user_data;
  dxgi_ctx->parent_ctx->app_callback = callback;
  dxgi_ctx->parent_ctx->app_callback_user_data = user_data;

  // --- Start Audio Loopback Capture ---
  if (dxgi_ctx->loopback_audio_ctx &&
      dxgi_ctx->audio_loopback_enabled_and_configured) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI: Starting audio loopback capture.");
    res = MiniAV_Loopback_StartCapture(
        dxgi_ctx->loopback_audio_ctx,
        dxgi_ctx->app_callback_internal, // Use the same callback
        dxgi_ctx->app_callback_user_data_internal);
    if (res != MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "DXGI: Failed to start audio loopback capture: %s. Proceeding "
                 "with video only.",
                 MiniAV_GetErrorString(res));
      // Optionally, you might want to disable
      // audio_loopback_enabled_and_configured here or allow video to continue.
      // For now, just log and continue.
    } else {
      miniav_log(MINIAV_LOG_LEVEL_INFO,
                 "DXGI: Audio loopback capture started.");
    }
  }
  // --- End Audio Loopback Capture ---

  ResetEvent(dxgi_ctx->stop_event_handle); // Ensure stop event is not signaled
  dxgi_ctx->is_streaming =
      TRUE; // Set after potential audio start failure, before video thread

  dxgi_ctx->capture_thread_handle =
      CreateThread(NULL, 0, dxgi_capture_thread_proc, dxgi_ctx, 0, NULL);
  if (dxgi_ctx->capture_thread_handle == NULL) {
    dxgi_ctx->is_streaming = FALSE; // Video thread failed
    // If audio started, stop it
    if (dxgi_ctx->loopback_audio_ctx &&
        dxgi_ctx->audio_loopback_enabled_and_configured) {
      // Check if audio is actually running (MiniAV_Loopback_StartCapture was
      // successful) This requires the loopback API to correctly manage its
      // is_running state. For simplicity, we'll call stop if it was configured
      // and we attempted to start.
      MiniAV_Loopback_StopCapture(dxgi_ctx->loopback_audio_ctx);
    }
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "DXGI: Failed to create video capture thread.");
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  LeaveCriticalSection(&dxgi_ctx->critical_section);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Video capture thread started.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode dxgi_stop_capture(MiniAVScreenContext *ctx) {
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;
  DXGIScreenPlatformContext *dxgi_ctx =
      (DXGIScreenPlatformContext *)ctx->platform_ctx;

  EnterCriticalSection(&dxgi_ctx->critical_section);
  if (!dxgi_ctx->is_streaming) {
    LeaveCriticalSection(&dxgi_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "DXGI: Capture not started or already stopped.");
    return MINIAV_SUCCESS;
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Stopping capture.");
  SetEvent(dxgi_ctx->stop_event_handle); // Signal video thread to stop
  BOOL was_streaming = dxgi_ctx->is_streaming;
  dxgi_ctx->is_streaming = FALSE; // Set flag early
  LeaveCriticalSection(
      &dxgi_ctx->critical_section); // Release lock before waiting

  if (dxgi_ctx->capture_thread_handle) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI: Waiting for video capture thread to exit...");
    WaitForSingleObject(dxgi_ctx->capture_thread_handle, INFINITE);
    CloseHandle(dxgi_ctx->capture_thread_handle);
    dxgi_ctx->capture_thread_handle = NULL;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Video capture thread exited.");
  }

  // --- Stop Audio Loopback Capture ---
  // Check if audio was successfully started and needs stopping
  // This check relies on audio_loopback_enabled_and_configured and potentially
  // an is_running state from loopback API For now, if it was configured and we
  // attempted to start, we attempt to stop.
  if (dxgi_ctx->loopback_audio_ctx &&
      dxgi_ctx->audio_loopback_enabled_and_configured && was_streaming) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "DXGI: Stopping audio loopback capture.");
    MiniAVResultCode audio_stop_res =
        MiniAV_Loopback_StopCapture(dxgi_ctx->loopback_audio_ctx);
    if (audio_stop_res == MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_INFO,
                 "DXGI: Audio loopback capture stopped.");
    } else {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "DXGI: Failed to stop audio loopback capture cleanly: %s",
                 MiniAV_GetErrorString(audio_stop_res));
    }
  }
  // --- End Audio Loopback Capture ---

  miniav_log(MINIAV_LOG_LEVEL_INFO, "DXGI: Capture stopped.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
dxgi_release_buffer(MiniAVScreenContext *ctx,
                    void *native_buffer_payload_resource_ptr) {
  MINIAV_UNUSED(ctx);
  if (!native_buffer_payload_resource_ptr) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "DXGI: native_buffer_payload_resource_ptr is NULL in release_buffer.");
    return MINIAV_ERROR_INVALID_ARG;
  }

  DXGIFrameReleasePayload *frame_payload =
      (DXGIFrameReleasePayload *)native_buffer_payload_resource_ptr;

  if (frame_payload->type == DXGI_PAYLOAD_TYPE_CPU) {
    if (frame_payload->cpu.d3d_context_for_unmap &&
        frame_payload->cpu.staging_texture_for_frame) {
      ID3D11DeviceContext_Unmap(
          frame_payload->cpu.d3d_context_for_unmap,
          (ID3D11Resource *)frame_payload->cpu.staging_texture_for_frame,
          frame_payload->cpu.subresource_for_unmap);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI: Unmapped CPU staging texture for frame.");
    }
    if (frame_payload->cpu.staging_texture_for_frame) {
      ULONG ref_count =
          ID3D11Texture2D_Release(frame_payload->cpu.staging_texture_for_frame);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI: Released CPU per-frame staging texture. Ref count: %lu",
                 ref_count);
    }
  } else if (frame_payload->type == DXGI_PAYLOAD_TYPE_GPU) {
    if (frame_payload->gpu.shared_gpu_texture) {
      ULONG ref_count =
          ID3D11Texture2D_Release(frame_payload->gpu.shared_gpu_texture);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "DXGI: Released shared GPU texture. Ref count: %lu",
                 ref_count);
    }
    // The application is responsible for calling CloseHandle on the
    // native_gpu_shared_handle it received.
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "DXGI: Unknown payload type in release_buffer: %d",
               frame_payload->type);
  }

  miniav_free(frame_payload);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Freed DXGIFrameReleasePayload.");

  return MINIAV_SUCCESS;
}

static DWORD WINAPI dxgi_capture_thread_proc(LPVOID param) {
  DXGIScreenPlatformContext *dxgi_ctx = (DXGIScreenPlatformContext *)param;
  if (!dxgi_ctx)
    return 1;

  HRESULT hr;
  IDXGIResource *desktop_resource_handle =
      NULL; // Renamed to avoid confusion with ID3D11Resource
  DXGI_OUTDUPL_FRAME_INFO frame_info;
  ID3D11Texture2D *acquired_texture = NULL;

  UINT frame_timeout_ms = 1000 / dxgi_ctx->target_fps;
  if (frame_timeout_ms == 0)
    frame_timeout_ms = 16;

  MiniAVOutputPreference desired_output_pref =
      dxgi_ctx->configured_video_format.output_preference;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "DXGI: Capture thread started. Target FPS: %u, Frame Timeout: %u "
             "ms, OutputPref: %d",
             dxgi_ctx->target_fps, frame_timeout_ms, desired_output_pref);

  while (dxgi_ctx->is_streaming) {
    if (WaitForSingleObject(dxgi_ctx->stop_event_handle, 0) == WAIT_OBJECT_0) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Stop event signaled.");
      break;
    }

    if (acquired_texture) {
      ID3D11Texture2D_Release(acquired_texture);
      acquired_texture = NULL;
    }
    if (dxgi_ctx->output_duplication) {
      IDXGIOutputDuplication_ReleaseFrame(dxgi_ctx->output_duplication);
    }

    hr = IDXGIOutputDuplication_AcquireNextFrame(dxgi_ctx->output_duplication,
                                                 500, &frame_info,
                                                 &desktop_resource_handle);

    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
      Sleep(1);
      continue;
    }
    if (hr == DXGI_ERROR_ACCESS_LOST) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "DXGI: Access lost. Attempting reinitialization.");
      EnterCriticalSection(&dxgi_ctx->critical_section);
      dxgi_cleanup_d3d_and_duplication(dxgi_ctx);
      MiniAVResultCode reinit_res = dxgi_init_d3d_and_duplication(
          dxgi_ctx, dxgi_ctx->adapter_index_internal,
          dxgi_ctx->output_index_internal);
      if (reinit_res != MINIAV_SUCCESS) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "DXGI: Failed to reinitialize. Stopping stream.");
        dxgi_ctx->is_streaming = FALSE;
      }
      LeaveCriticalSection(&dxgi_ctx->critical_section);
      if (!dxgi_ctx->is_streaming)
        break;
      continue;
    }
    if (FAILED(hr) || !desktop_resource_handle) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR, "DXGI: AcquireNextFrame failed: 0x%X",
                 hr);
      Sleep(frame_timeout_ms);
      continue;
    }

    if (frame_info.LastPresentTime.QuadPart == 0) {
      if (desktop_resource_handle)
        IDXGIResource_Release(desktop_resource_handle);
      desktop_resource_handle = NULL;
      Sleep(1);
      continue;
    }

    hr = IDXGIResource_QueryInterface(desktop_resource_handle,
                                      &IID_ID3D11Texture2D,
                                      (void **)&acquired_texture);
    IDXGIResource_Release(desktop_resource_handle);
    desktop_resource_handle = NULL;

    if (FAILED(hr) || !acquired_texture) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "DXGI: Failed to query ID3D11Texture2D: 0x%X", hr);
      continue;
    }

    MiniAVBuffer buffer;
    memset(&buffer, 0, sizeof(MiniAVBuffer));
    buffer.type = MINIAV_BUFFER_TYPE_VIDEO;
    buffer.timestamp_us = miniav_qpc_to_microseconds(frame_info.LastPresentTime,
                                                     dxgi_ctx->qpc_frequency);
    buffer.data.video.width = dxgi_ctx->frame_width;
    buffer.data.video.height = dxgi_ctx->frame_height;
    buffer.data.video.pixel_format = dxgi_ctx->pixel_format;
    buffer.user_data = dxgi_ctx->app_callback_user_data_internal;

    BOOL processed_as_gpu = FALSE;
    ID3D11Texture2D *texture_for_payload_ref =
        NULL; // This will be AddRef'd for the payload
    HANDLE shared_handle_for_app = NULL;

    // Attempt GPU Path if preferred
    if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE &&
        dxgi_ctx->d3d_device) {
      D3D11_TEXTURE2D_DESC acquired_desc;
      ID3D11Texture2D_GetDesc(acquired_texture, &acquired_desc);
      ID3D11Texture2D *texture_to_share =
          acquired_texture; // Start with the acquired one
      BOOL needs_copy_for_sharing =
          !(acquired_desc.MiscFlags & D3D11_RESOURCE_MISC_SHARED);
      ID3D11Texture2D *shareable_copy_temp = NULL; // Temp holder for copy

      if (needs_copy_for_sharing) {
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "DXGI: Acquired texture not shareable, creating a shareable copy.");
        D3D11_TEXTURE2D_DESC shareable_desc;
        ZeroMemory(&shareable_desc,
                   sizeof(shareable_desc)); // Start with a clean slate

        // Copy essential properties from the acquired texture
        shareable_desc.Width = acquired_desc.Width;
        shareable_desc.Height = acquired_desc.Height;
        shareable_desc.Format = acquired_desc.Format;

        // Set properties required for a shareable texture
        shareable_desc.MipLevels = 1;
        shareable_desc.ArraySize = 1;
        shareable_desc.SampleDesc.Count = 1;
        shareable_desc.SampleDesc.Quality = 0;
        shareable_desc.Usage = D3D11_USAGE_DEFAULT;
        shareable_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
        shareable_desc.CPUAccessFlags = 0;
        shareable_desc.MiscFlags =
            D3D11_RESOURCE_MISC_SHARED | D3D11_RESOURCE_MISC_SHARED_NTHANDLE;

        hr = ID3D11Device_CreateTexture2D(dxgi_ctx->d3d_device, &shareable_desc,
                                          NULL, &shareable_copy_temp);
        if (SUCCEEDED(hr)) {
          ID3D11DeviceContext_CopyResource(
              dxgi_ctx->d3d_context, (ID3D11Resource *)shareable_copy_temp,
              (ID3D11Resource *)acquired_texture);
          texture_to_share = shareable_copy_temp; // Now use the copy
        } else {
          miniav_log(
              MINIAV_LOG_LEVEL_ERROR,
              "DXGI: Failed to create shareable copy: 0x%X. Fallback to CPU.",
              hr);
          needs_copy_for_sharing = TRUE; // Force CPU path if copy failed
        }
      }

      if (SUCCEEDED(hr)) { // SUCCEEDED(hr) means either original was shareable
                           // or copy was successful
        IDXGIResource1 *dxgi_resource_to_share = NULL;
        hr = ID3D11Texture2D_QueryInterface(texture_to_share,
                                            &IID_IDXGIResource1,
                                            (void **)&dxgi_resource_to_share);
        if (SUCCEEDED(hr)) {
          hr = IDXGIResource1_CreateSharedHandle(dxgi_resource_to_share, NULL,
                                                 DXGI_SHARED_RESOURCE_READ,
                                                 NULL, &shared_handle_for_app);
          if (SUCCEEDED(hr)) {
            ID3D11Texture2D_AddRef(texture_to_share); // AddRef for payload
            texture_for_payload_ref = texture_to_share;
            processed_as_gpu = TRUE;
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "DXGI: GPU shared handle created: %p",
                       shared_handle_for_app);
          } else {
            miniav_log(
                MINIAV_LOG_LEVEL_ERROR,
                "DXGI: CreateSharedHandle failed: 0x%X. Fallback to CPU.", hr);
          }
          IDXGIResource1_Release(dxgi_resource_to_share);
        } else {
          miniav_log(
              MINIAV_LOG_LEVEL_ERROR,
              "DXGI: QI for IDXGIResource1 failed: 0x%X. Fallback to CPU.", hr);
        }
      }

      if (shareable_copy_temp &&
          texture_for_payload_ref != shareable_copy_temp) {
        ID3D11Texture2D_Release(shareable_copy_temp);
      }
    }

    // CPU Path (or fallback from GPU)
    if (!processed_as_gpu) {
      if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "DXGI: GPU path failed or not preferred, using CPU path.");
      }
      ID3D11Texture2D *per_frame_staging_texture = NULL;
      D3D11_TEXTURE2D_DESC staging_desc_cpu;
      ID3D11Texture2D_GetDesc(
          dxgi_ctx->staging_texture,
          &staging_desc_cpu); // Use desc from main staging texture

      hr = ID3D11Device_CreateTexture2D(dxgi_ctx->d3d_device, &staging_desc_cpu,
                                        NULL, &per_frame_staging_texture);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "DXGI: Failed to create per-frame CPU staging texture: 0x%X",
                   hr);
        continue;
      }

      ID3D11DeviceContext_CopyResource(
          dxgi_ctx->d3d_context, (ID3D11Resource *)per_frame_staging_texture,
          (ID3D11Resource *)acquired_texture);

      D3D11_MAPPED_SUBRESOURCE mapped_rect_cpu;
      hr = ID3D11DeviceContext_Map(dxgi_ctx->d3d_context,
                                   (ID3D11Resource *)per_frame_staging_texture,
                                   0, D3D11_MAP_READ, 0, &mapped_rect_cpu);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "DXGI: Failed to map per-frame CPU staging texture: 0x%X",
                   hr);
        ID3D11Texture2D_Release(per_frame_staging_texture);
        continue;
      }

      buffer.content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
      buffer.data.video.planes[0] = mapped_rect_cpu.pData;
      buffer.data.video.stride_bytes[0] = mapped_rect_cpu.RowPitch;
      buffer.data_size_bytes =
          mapped_rect_cpu.RowPitch * dxgi_ctx->frame_height;
      texture_for_payload_ref =
          per_frame_staging_texture; // This texture will be managed by the
                                     // payload
    } else {                         // GPU Path successful
      buffer.content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE;
      buffer.data.video.native_gpu_shared_handle = shared_handle_for_app;
      buffer.data.video.native_gpu_texture_ptr =
          texture_for_payload_ref; // The AddRef'd texture
      buffer.data.video.planes[0] = NULL;
      buffer.data.video.stride_bytes[0] = 0;
      buffer.data_size_bytes = 0;
    }

    MiniAVNativeBufferInternalPayload *internal_payload =
        (MiniAVNativeBufferInternalPayload *)miniav_calloc(
            1, sizeof(MiniAVNativeBufferInternalPayload));
    DXGIFrameReleasePayload *frame_release_payload_app =
        (DXGIFrameReleasePayload *)miniav_calloc(
            1, sizeof(DXGIFrameReleasePayload));

    if (!internal_payload || !frame_release_payload_app) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "DXGI: Failed to allocate payload structures.");
      if (processed_as_gpu) {
        if (shared_handle_for_app)
          CloseHandle(shared_handle_for_app);
        if (texture_for_payload_ref)
          ID3D11Texture2D_Release(
              texture_for_payload_ref); // Release the AddRef for payload
      } else {                          // CPU
        if (texture_for_payload_ref) {  // This is the per_frame_staging_texture
          ID3D11DeviceContext_Unmap(dxgi_ctx->d3d_context,
                                    (ID3D11Resource *)texture_for_payload_ref,
                                    0);
          ID3D11Texture2D_Release(texture_for_payload_ref);
        }
      }
      miniav_free(internal_payload);
      miniav_free(frame_release_payload_app);
      continue;
    }

    if (processed_as_gpu) {
      frame_release_payload_app->type = DXGI_PAYLOAD_TYPE_GPU;
      frame_release_payload_app->gpu.shared_gpu_texture =
          texture_for_payload_ref; // Already AddRef'd for this purpose
    } else {                       // CPU
      frame_release_payload_app->type = DXGI_PAYLOAD_TYPE_CPU;
      frame_release_payload_app->cpu.staging_texture_for_frame =
          texture_for_payload_ref; // This is the per_frame_staging_texture
      frame_release_payload_app->cpu.d3d_context_for_unmap =
          dxgi_ctx->d3d_context;
      frame_release_payload_app->cpu.subresource_for_unmap = 0;
    }

    internal_payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
    internal_payload->context_owner = dxgi_ctx->parent_ctx;
    internal_payload->native_resource_ptr = frame_release_payload_app;
    buffer.internal_handle = internal_payload;

    if (dxgi_ctx->app_callback_internal) {
      dxgi_ctx->app_callback_internal(
          &buffer, dxgi_ctx->app_callback_user_data_internal);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "DXGI: No app callback. Releasing frame internally.");
      if (processed_as_gpu) {
        if (shared_handle_for_app)
          CloseHandle(shared_handle_for_app);
        ID3D11Texture2D_Release(
            frame_release_payload_app->gpu.shared_gpu_texture);
      } else {
        ID3D11DeviceContext_Unmap(
            frame_release_payload_app->cpu.d3d_context_for_unmap,
            (ID3D11Resource *)
                frame_release_payload_app->cpu.staging_texture_for_frame,
            frame_release_payload_app->cpu.subresource_for_unmap);
        ID3D11Texture2D_Release(
            frame_release_payload_app->cpu.staging_texture_for_frame);
      }
      miniav_free(frame_release_payload_app);
      miniav_free(internal_payload);
    }

    Sleep(frame_timeout_ms > 0 ? frame_timeout_ms
                               : 1); // Use frame_timeout_ms here
  }

  if (acquired_texture) {
    ID3D11Texture2D_Release(acquired_texture);
    acquired_texture = NULL;
  }
  if (dxgi_ctx->output_duplication) {
    IDXGIOutputDuplication_ReleaseFrame(dxgi_ctx->output_duplication);
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Capture thread finished.");
  return 0;
}

// Define the actual ops struct for DXGI Screen Capture
const ScreenContextInternalOps g_screen_ops_win_dxgi = {
    .init_platform = dxgi_init_platform,
    .destroy_platform = dxgi_destroy_platform,
    .enumerate_displays = dxgi_enumerate_displays,
    .enumerate_windows = dxgi_enumerate_windows, // Not supported
    .configure_display = dxgi_configure_display,
    .configure_window = dxgi_configure_window, // Not supported
    .configure_region = dxgi_configure_region, // Not supported
    .start_capture = dxgi_start_capture,
    .stop_capture = dxgi_stop_capture,
    .release_buffer = dxgi_release_buffer,
    .get_default_formats = dxgi_get_default_formats,
    .get_configured_video_formats = dxgi_get_configured_video_formats
};

MiniAVResultCode
miniav_screen_context_platform_init_windows_dxgi(MiniAVScreenContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;
  ctx->ops = &g_screen_ops_win_dxgi;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Assigned Windows DXGI screen ops.");
  // The caller (e.g., MiniAV_Screen_CreateContext) will call
  // ctx->ops->init_platform()
  return MINIAV_SUCCESS;
}
