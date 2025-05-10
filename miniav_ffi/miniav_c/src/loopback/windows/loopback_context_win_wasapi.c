#ifdef _WIN32
#include <initguid.h>


#include <Audioclient.h>
#include <mmdeviceapi.h> // For IID_IMMDeviceEnumerator, CLSID_MMDeviceEnumerator, IMMDevice
#include <windows.h> // Base Windows types
// For PKEY_Device_FriendlyName, IPropertyStore. propsys.h includes objidl.h
// which might also declare GUIDs.
#include <functiondiscoverykeys_devpkey.h> // Often needed for PKEY definitions
#include <propsys.h>
// ksmedia.h was for KSDATAFORMAT_... GUIDs, which seem resolved now, but good
// to keep if used.
#include <ksmedia.h>
#endif

// Step 3: Include your project's headers
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h"
#include "../../common/miniav_utils.h" // For miniav_calloc, miniav_free, miniav_strdup, MINIAV_UNUSED
#include "loopback_context_win_wasapi.h" // This header should declare types but not try to define these system GUIDs
#include <stdio.h> // For swprintf_s

#ifdef _WIN32

const CLSID CLSID_MMDeviceEnumerator = {
    0xbcde0395,
    0xe52f,
    0x467c,
    {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};

const IID IID_IMMDeviceEnumerator = {
    0xa95664d2,
    0x9614,
    0x4f35,
    {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};

const IID IID_IAudioClient = {0x1cb9ad4c,
                              0xdbfa,
                              0x4c32,
                              {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2}};

const IID IID_IAudioClient3 = {
    0x7ed4ee07,
    0x8e67,
    0x4cd4,
    {0x8c, 0x1a, 0x2b, 0x7a, 0x59, 0x87, 0xad, 0x42}};

const IID IID_IAudioCaptureClient = {
    0xc8adbd64,
    0xe71e,
    0x48a0,
    {0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17}};

// --- Helper Functions ---

// Converts UTF-8 string to WCHAR string. Caller must free the returned string.
static LPWSTR utf8_to_lpwstr(const char *utf8_str) {
  if (!utf8_str)
    return NULL;
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, NULL, 0);
  if (size_needed == 0)
    return NULL;
  LPWSTR wstr = (LPWSTR)miniav_calloc(size_needed, sizeof(WCHAR));
  if (!wstr)
    return NULL;
  MultiByteToWideChar(CP_UTF8, 0, utf8_str, -1, wstr, size_needed);
  return wstr;
}

// Converts WCHAR string to UTF-8 string. Caller must free the returned string.
static char *lpwstr_to_utf8(LPCWSTR wstr) {
  if (!wstr)
    return NULL;
  int size_needed =
      WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
  if (size_needed == 0)
    return NULL;
  char *utf8_str = (char *)miniav_calloc(size_needed, sizeof(char));
  if (!utf8_str)
    return NULL;
  WideCharToMultiByte(CP_UTF8, 0, wstr, -1, utf8_str, size_needed, NULL, NULL);
  return utf8_str;
}

static MiniAVResultCode hresult_to_miniavresult(HRESULT hr) {
  if (SUCCEEDED(hr))
    return MINIAV_SUCCESS;
  // Basic mapping, can be expanded
  switch (hr) {
  case E_POINTER:
    return MINIAV_ERROR_INVALID_ARG;
  case E_INVALIDARG:
    return MINIAV_ERROR_INVALID_ARG;
  case E_OUTOFMEMORY:
    return MINIAV_ERROR_OUT_OF_MEMORY;
  case AUDCLNT_E_DEVICE_INVALIDATED:
    return MINIAV_ERROR_DEVICE_LOST;
  case AUDCLNT_E_SERVICE_NOT_RUNNING:
    return MINIAV_ERROR_SYSTEM_CALL_FAILED; // Or a more specific error
  case AUDCLNT_E_UNSUPPORTED_FORMAT:
    return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
  // Add more specific mappings as needed
  default:
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
}

static void miniav_audio_format_to_waveformat(const MiniAVAudioInfo *miniav_fmt,
                                              WAVEFORMATEX *wfex) {
  memset(wfex, 0, sizeof(WAVEFORMATEX));
  if (miniav_fmt->format == MINIAV_AUDIO_FORMAT_F32) { // Corrected from format
    wfex->wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
  } else if (miniav_fmt->format ==
             MINIAV_AUDIO_FORMAT_S16) { // Corrected from format
    wfex->wFormatTag = WAVE_FORMAT_PCM;
  } // Add other formats as needed (S32, U8 etc.)

  wfex->nChannels = (WORD)miniav_fmt->channels;
  wfex->nSamplesPerSec = miniav_fmt->sample_rate;
  wfex->wBitsPerSample =
      (WORD)miniav_audio_format_get_bytes_per_sample(miniav_fmt->format) *
      8; // Corrected from format
  wfex->nBlockAlign = (wfex->nChannels * wfex->wBitsPerSample) / 8;
  wfex->nAvgBytesPerSec = wfex->nSamplesPerSec * wfex->nBlockAlign;
  wfex->cbSize = 0;
}

static void waveformat_to_miniav_audio_format(const WAVEFORMATEX *wfex,
                                              MiniAVAudioInfo *miniav_fmt) {
  memset(miniav_fmt, 0, sizeof(MiniAVAudioInfo));
  miniav_fmt->channels = wfex->nChannels;
  miniav_fmt->sample_rate = wfex->nSamplesPerSec;

  if (wfex->wFormatTag == WAVE_FORMAT_IEEE_FLOAT &&
      wfex->wBitsPerSample == 32) {
    miniav_fmt->format = MINIAV_AUDIO_FORMAT_F32; // Corrected from format
  } else if (wfex->wFormatTag == WAVE_FORMAT_PCM &&
             wfex->wBitsPerSample == 16) {
    miniav_fmt->format = MINIAV_AUDIO_FORMAT_S16; // Corrected from format
  } else if (wfex->wFormatTag == WAVE_FORMAT_PCM &&
             wfex->wBitsPerSample == 32) {
    miniav_fmt->format = MINIAV_AUDIO_FORMAT_S32; // Corrected from format
  } else if (wfex->wFormatTag == WAVE_FORMAT_PCM && wfex->wBitsPerSample == 8) {
    miniav_fmt->format = MINIAV_AUDIO_FORMAT_U8; // Corrected from format
  } else if (wfex->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
    WAVEFORMATEXTENSIBLE *wfex_ext = (WAVEFORMATEXTENSIBLE *)wfex;
    if (IsEqualGUID(&wfex_ext->SubFormat, &KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) &&
        wfex->wBitsPerSample == 32) {
      miniav_fmt->format = MINIAV_AUDIO_FORMAT_F32; // Corrected from format
    } else if (IsEqualGUID(&wfex_ext->SubFormat, &KSDATAFORMAT_SUBTYPE_PCM) &&
               wfex->wBitsPerSample == 16) {
      miniav_fmt->format = MINIAV_AUDIO_FORMAT_S16; // Corrected from format
    } else {
      miniav_fmt->format = MINIAV_AUDIO_FORMAT_UNKNOWN; // Corrected from format
    }
  } else {
    miniav_fmt->format = MINIAV_AUDIO_FORMAT_UNKNOWN; // Corrected from format
  }
}

// --- Capture Thread ---
static DWORD WINAPI wasapi_capture_thread_proc(LPVOID param) {
  MiniAVLoopbackContext *ctx = (MiniAVLoopbackContext *)param;
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;
  HRESULT hr;
  UINT32 packet_length = 0;
  UINT32 num_frames_available;
  BYTE *data_ptr = NULL;
  DWORD flags;
  UINT64 device_position;
  UINT64 qpc_position;

  HANDLE wait_array[2] = {platform_ctx->stop_event_handle, NULL};
  DWORD wait_count = 1;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Capture thread started.");

  while (TRUE) {
    DWORD wait_result =
        WaitForMultipleObjects(wait_count, wait_array, FALSE, 100);

    if (wait_result == WAIT_OBJECT_0) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI: Capture thread received stop event.");
      break;
    } else if (wait_result == WAIT_TIMEOUT) {
      // Polling interval expired
    } else if (wait_result == WAIT_FAILED) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI: Capture thread WaitForMultipleObjects failed: %lu",
                 GetLastError());
      break;
    }

    hr = platform_ctx->capture_client->lpVtbl->GetNextPacketSize(
        platform_ctx->capture_client, &packet_length);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI: GetNextPacketSize failed: 0x%lx", hr);
      if (hr == AUDCLNT_E_DEVICE_INVALIDATED)
        break;
      Sleep(20);
      continue;
    }

    while (packet_length != 0) {
      hr = platform_ctx->capture_client->lpVtbl->GetBuffer(
          platform_ctx->capture_client, &data_ptr, &num_frames_available,
          &flags, &device_position, &qpc_position);

      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI: GetBuffer failed: 0x%lx",
                   hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED)
          goto cleanup_thread;
        break;
      }

      if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
        // For silent packets, data_ptr might be NULL or point to silence.
        // If data_ptr is NULL and num_frames_available > 0, we might need to
        // provide our own silent buffer. For now, we assume if
        // num_frames_available > 0, data_ptr is valid (even if it's silence).
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI: Silent packet received (frames: %u).",
                   num_frames_available);
      }

      if (num_frames_available > 0 && ctx->app_callback) {
        MiniAVBuffer buffer;
        memset(&buffer, 0, sizeof(MiniAVBuffer));
        buffer.type = MINIAV_BUFFER_TYPE_AUDIO;
        buffer.content_type =
            MINIAV_BUFFER_CONTENT_TYPE_CPU; // WASAPI gives CPU buffer
        buffer.timestamp_us = miniav_get_time_us();

        buffer.data.audio.data = data_ptr;
        buffer.data_size_bytes =
            num_frames_available * platform_ctx->capture_format->nBlockAlign;

        // Populate the format information within the audio_buffer part of the
        // union
        buffer.data.audio.info = ctx->configured_format; // Copy the base format
        buffer.data.audio.info.num_frames =
            num_frames_available; // Update with actual frames

        ctx->app_callback(ctx, &buffer, ctx->app_callback_user_data);
      }

      hr = platform_ctx->capture_client->lpVtbl->ReleaseBuffer(
          platform_ctx->capture_client, num_frames_available);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI: ReleaseBuffer failed: 0x%lx", hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED)
          goto cleanup_thread;
      }

      hr = platform_ctx->capture_client->lpVtbl->GetNextPacketSize(
          platform_ctx->capture_client, &packet_length);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI: GetNextPacketSize (in loop) failed: 0x%lx", hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED)
          goto cleanup_thread;
        packet_length = 0;
      }
    }
  }

cleanup_thread:
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Capture thread exiting.");
  return 0;
}

// --- Platform Ops Implementation ---

MiniAVResultCode wasapi_init_platform(MiniAVLoopbackContext *ctx) {
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)miniav_calloc(
          1, sizeof(LoopbackPlatformContextWinWasapi));
  if (!platform_ctx) {
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }
  ctx->platform_ctx = platform_ctx;
  platform_ctx->parent_ctx = ctx;

  HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI: CoInitializeEx failed: 0x%lx",
               hr);
    if (hr != S_FALSE) {
      miniav_free(platform_ctx);
      ctx->platform_ctx = NULL;
      return hresult_to_miniavresult(hr);
    }
  }

  platform_ctx->stop_event_handle = CreateEvent(NULL, TRUE, FALSE, NULL);
  if (platform_ctx->stop_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI: Failed to create stop event: %lu", GetLastError());
    CoUninitialize();
    miniav_free(platform_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Platform context initialized.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode wasapi_destroy_platform(MiniAVLoopbackContext *ctx) {
  if (!ctx || !ctx->platform_ctx) {
    return MINIAV_SUCCESS;
  }
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;

  if (ctx->is_running) {
    wasapi_stop_capture(ctx);
  }

  if (platform_ctx->capture_format) {
    CoTaskMemFree(platform_ctx->capture_format);
    platform_ctx->capture_format = NULL;
  }
  if (platform_ctx->mix_format) {
    CoTaskMemFree(platform_ctx->mix_format);
    platform_ctx->mix_format = NULL;
  }
  if (platform_ctx->capture_client) {
    platform_ctx->capture_client->lpVtbl->Release(platform_ctx->capture_client);
    platform_ctx->capture_client = NULL;
  }
  if (platform_ctx->audio_client) {
    platform_ctx->audio_client->lpVtbl->Release(platform_ctx->audio_client);
    platform_ctx->audio_client = NULL;
  }
  if (platform_ctx->audio_device) {
    platform_ctx->audio_device->lpVtbl->Release(platform_ctx->audio_device);
    platform_ctx->audio_device = NULL;
  }
  if (platform_ctx->device_enumerator) {
    platform_ctx->device_enumerator->lpVtbl->Release(
        platform_ctx->device_enumerator);
    platform_ctx->device_enumerator = NULL;
  }
  if (platform_ctx->stop_event_handle) {
    CloseHandle(platform_ctx->stop_event_handle);
    platform_ctx->stop_event_handle = NULL;
  }

  miniav_free(platform_ctx);
  ctx->platform_ctx = NULL;

  CoUninitialize();
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_loopback_enumerate_targets_win(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets_out,
    uint32_t *count_out) {
  if (!targets_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *targets_out = NULL;
  *count_out = 0;

  HRESULT hr;
  IMMDeviceEnumerator *enumerator = NULL;
  IMMDeviceCollection *collection = NULL;
  MiniAVDeviceInfo *devices = NULL;
  uint32_t device_count = 0;

  // Ensure COM is initialized for this thread/function
  BOOL com_initialized_here = FALSE;
  hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (SUCCEEDED(hr)) {
    com_initialized_here = TRUE;
    if (hr == S_FALSE) { // Already initialized, but we don't own it
      com_initialized_here = FALSE;
    }
  } else if (hr != RPC_E_CHANGED_MODE) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Enum: CoInitializeEx failed: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  if (target_type_filter == MINIAV_LOOPBACK_TARGET_PROCESS ||
      target_type_filter == MINIAV_LOOPBACK_TARGET_WINDOW) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WASAPI: Enumerating specific process/window audio targets is "
               "not fully implemented, returning system devices.");
  }

  hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                        &IID_IMMDeviceEnumerator, (void **)&enumerator);
  if (FAILED(hr)) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "WASAPI Enum: CoCreateInstance for MMDeviceEnumerator failed: 0x%lx",
        hr);
    if (com_initialized_here)
      CoUninitialize();
    return hresult_to_miniavresult(hr);
  }

  hr = enumerator->lpVtbl->EnumAudioEndpoints(enumerator, eRender,
                                              DEVICE_STATE_ACTIVE, &collection);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Enum: EnumAudioEndpoints failed: 0x%lx", hr);
    enumerator->lpVtbl->Release(enumerator);
    if (com_initialized_here)
      CoUninitialize();
    return hresult_to_miniavresult(hr);
  }

  hr = collection->lpVtbl->GetCount(collection, &device_count);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI Enum: GetCount failed: 0x%lx",
               hr);
    collection->lpVtbl->Release(collection);
    enumerator->lpVtbl->Release(enumerator);
    if (com_initialized_here)
      CoUninitialize();
    return hresult_to_miniavresult(hr);
  }

  if (device_count == 0) {
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "WASAPI Enum: No active audio render devices found.");
    collection->lpVtbl->Release(collection);
    enumerator->lpVtbl->Release(enumerator);
    if (com_initialized_here)
      CoUninitialize();
    return MINIAV_SUCCESS;
  }

  devices =
      (MiniAVDeviceInfo *)miniav_calloc(device_count, sizeof(MiniAVDeviceInfo));
  if (!devices) {
    collection->lpVtbl->Release(collection);
    enumerator->lpVtbl->Release(enumerator);
    if (com_initialized_here)
      CoUninitialize();
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  for (UINT i = 0; i < device_count; ++i) {
    IMMDevice *device = NULL;
    LPWSTR device_id_wstr = NULL;
    IPropertyStore *props = NULL;
    PROPVARIANT var_name;
    PropVariantInit(&var_name);

    hr = collection->lpVtbl->Item(collection, i, &device);
    if (FAILED(hr))
      continue;

    hr = device->lpVtbl->GetId(device, &device_id_wstr);
    if (FAILED(hr)) {
      device->lpVtbl->Release(device);
      continue;
    }

    char *device_id_utf8 = lpwstr_to_utf8(device_id_wstr);
    if (device_id_utf8) {
      strncpy(devices[i].device_id, device_id_utf8,
              MINIAV_DEVICE_ID_MAX_LEN - 1);
      devices[i].device_id[MINIAV_DEVICE_ID_MAX_LEN - 1] = '\0';
      miniav_free(device_id_utf8);
    }
    CoTaskMemFree(device_id_wstr);

    hr = device->lpVtbl->OpenPropertyStore(device, STGM_READ, &props);
    if (SUCCEEDED(hr)) {
      hr = props->lpVtbl->GetValue(props, &PKEY_Device_FriendlyName, &var_name);
      if (SUCCEEDED(hr) && var_name.vt == VT_LPWSTR) {
        char *friendly_name_utf8 = lpwstr_to_utf8(var_name.pwszVal);
        if (friendly_name_utf8) {
          strncpy(devices[i].name, friendly_name_utf8,
                  MINIAV_DEVICE_NAME_MAX_LEN - 1);
          devices[i].name[MINIAV_DEVICE_NAME_MAX_LEN - 1] = '\0';
          miniav_free(friendly_name_utf8);
        }
      }
      PropVariantClear(&var_name);
      props->lpVtbl->Release(props);
    }
    device->lpVtbl->Release(device);
  }

  *targets_out = devices;
  *count_out = device_count;

  collection->lpVtbl->Release(collection);
  enumerator->lpVtbl->Release(enumerator);
  if (com_initialized_here)
    CoUninitialize();
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI Enum: Enumerated %u loopback target devices.",
             device_count);
  return MINIAV_SUCCESS;
}

MiniAVResultCode
wasapi_configure_loopback(MiniAVLoopbackContext *ctx,
                          const MiniAVLoopbackTargetInfo *target_info,
                          const char *target_device_id_utf8,
                          const MiniAVAudioInfo *requested_format) {
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;
  HRESULT hr;

  if (platform_ctx->capture_format)
    CoTaskMemFree(platform_ctx->capture_format);
  platform_ctx->capture_format = NULL;
  if (platform_ctx->mix_format)
    CoTaskMemFree(platform_ctx->mix_format);
  platform_ctx->mix_format = NULL;
  if (platform_ctx->capture_client) {
    platform_ctx->capture_client->lpVtbl->Release(platform_ctx->capture_client);
    platform_ctx->capture_client = NULL;
  }
  if (platform_ctx->audio_client) {
    platform_ctx->audio_client->lpVtbl->Release(platform_ctx->audio_client);
    platform_ctx->audio_client = NULL;
  }
  if (platform_ctx->audio_device) {
    platform_ctx->audio_device->lpVtbl->Release(platform_ctx->audio_device);
    platform_ctx->audio_device = NULL;
  }
  if (platform_ctx->device_enumerator) {
    platform_ctx->device_enumerator->lpVtbl->Release(
        platform_ctx->device_enumerator);
    platform_ctx->device_enumerator = NULL;
  }

  platform_ctx->attempt_process_specific_capture = FALSE;
  platform_ctx->target_process_id = 0;

  hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                        &IID_IMMDeviceEnumerator,
                        (void **)&platform_ctx->device_enumerator);
  if (FAILED(hr)) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "WASAPI Cfg: CoCreateInstance for MMDeviceEnumerator failed: 0x%lx",
        hr);
    return hresult_to_miniavresult(hr);
  }

  if (target_info && target_info->type == MINIAV_LOOPBACK_TARGET_PROCESS) {
    platform_ctx->target_process_id = target_info->TARGETHANDLE.process_id;
    platform_ctx->attempt_process_specific_capture = TRUE;
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "WASAPI Cfg: Attempting process-specific loopback for PID: %lu",
               platform_ctx->target_process_id);
    hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
        platform_ctx->device_enumerator, eRender, eConsole,
        &platform_ctx->audio_device);
  } else if (target_device_id_utf8 && strlen(target_device_id_utf8) > 0) {
    LPWSTR device_id_wstr = utf8_to_lpwstr(target_device_id_utf8);
    if (!device_id_wstr)
      return MINIAV_ERROR_OUT_OF_MEMORY;
    hr = platform_ctx->device_enumerator->lpVtbl->GetDevice(
        platform_ctx->device_enumerator, device_id_wstr,
        &platform_ctx->audio_device);
    miniav_free(device_id_wstr);
  } else {
    hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
        platform_ctx->device_enumerator, eRender, eConsole,
        &platform_ctx->audio_device);
  }

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to get audio device: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  hr = platform_ctx->audio_device->lpVtbl->Activate(
      platform_ctx->audio_device, &IID_IAudioClient, CLSCTX_ALL, NULL,
      (void **)&platform_ctx->audio_client);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to activate audio client: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  hr = platform_ctx->audio_client->lpVtbl->GetMixFormat(
      platform_ctx->audio_client, &platform_ctx->mix_format);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to get mix format: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  platform_ctx->capture_format = (WAVEFORMATEX *)CoTaskMemAlloc(
      sizeof(WAVEFORMATEX) + platform_ctx->mix_format->cbSize);
  if (!platform_ctx->capture_format)
    return MINIAV_ERROR_OUT_OF_MEMORY;
  memcpy(platform_ctx->capture_format, platform_ctx->mix_format,
         sizeof(WAVEFORMATEX) + platform_ctx->mix_format->cbSize);

  waveformat_to_miniav_audio_format(platform_ctx->capture_format,
                                    &ctx->configured_format);

  DWORD stream_flags = AUDCLNT_STREAMFLAGS_LOOPBACK;

  if (platform_ctx->attempt_process_specific_capture &&
      platform_ctx->target_process_id != 0) {
    IAudioClient3 *audio_client3 = NULL;
    hr = platform_ctx->audio_client->lpVtbl->QueryInterface(
        platform_ctx->audio_client, &IID_IAudioClient3,
        (void **)&audio_client3);
    if (SUCCEEDED(hr) && audio_client3) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Cfg: IAudioClient3 available. Process-specific "
                 "capture might be possible via InitializeSharedAudioStream.");
      // The AUDCLNT_STREAMFLAGS_LOOPBACK_PROCESS_ID_ONLY flag is used with
      // IAudioClient3::InitializeSharedAudioStream.
      // This simplified example uses IAudioClient::Initialize, which doesn't
      // support that flag. A full implementation would need to use the
      // IAudioClient3 path here.
      miniav_log(
          MINIAV_LOG_LEVEL_WARN,
          "WASAPI Cfg: Process-specific capture requested, but this example "
          "uses IAudioClient::Initialize. True process isolation requires "
          "IAudioClient3::InitializeSharedAudioStream.");
      audio_client3->lpVtbl->Release(audio_client3);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WASAPI Cfg: IAudioClient3 not available. Process-specific "
                 "capture may not work as intended.");
    }
  }

  REFERENCE_TIME hns_requested_duration = 0;
  hr = platform_ctx->audio_client->lpVtbl->Initialize(
      platform_ctx->audio_client, AUDCLNT_SHAREMODE_SHARED, stream_flags,
      hns_requested_duration, 0, platform_ctx->capture_format, NULL);

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to initialize audio client: 0x%lx", hr);
    if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Cfg: Requested format not supported by endpoint.");
    }
    return hresult_to_miniavresult(hr);
  }

  hr = platform_ctx->audio_client->lpVtbl->GetBufferSize(
      platform_ctx->audio_client, &platform_ctx->buffer_frame_count);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to get buffer size: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  hr = platform_ctx->audio_client->lpVtbl->GetService(
      platform_ctx->audio_client, &IID_IAudioCaptureClient,
      (void **)&platform_ctx->capture_client);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to get capture client service: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI Cfg: Loopback configured. Buffer frame count: %u",
             platform_ctx->buffer_frame_count);
  ctx->is_configured = true;
  return MINIAV_SUCCESS;
}

MiniAVResultCode wasapi_start_capture(MiniAVLoopbackContext *ctx,
                                      MiniAVBufferCallback callback,
                                      void *user_data) {
  MINIAV_UNUSED(callback);
  MINIAV_UNUSED(user_data);
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;
  HRESULT hr;

  if (!platform_ctx->audio_client || !platform_ctx->capture_client) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  hr = platform_ctx->audio_client->lpVtbl->Start(platform_ctx->audio_client);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Start: Failed to start audio client: 0x%lx", hr);
    return hresult_to_miniavresult(hr);
  }

  ResetEvent(platform_ctx->stop_event_handle);
  platform_ctx->capture_thread_handle =
      CreateThread(NULL, 0, wasapi_capture_thread_proc, ctx, 0, NULL);
  if (platform_ctx->capture_thread_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Start: Failed to create capture thread: %lu",
               GetLastError());
    platform_ctx->audio_client->lpVtbl->Stop(platform_ctx->audio_client);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "WASAPI: Capture started.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode wasapi_stop_capture(MiniAVLoopbackContext *ctx) {
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;

  if (platform_ctx->stop_event_handle) {
    SetEvent(platform_ctx->stop_event_handle);
  }

  if (platform_ctx->capture_thread_handle) {
    WaitForSingleObject(platform_ctx->capture_thread_handle, INFINITE);
    CloseHandle(platform_ctx->capture_thread_handle);
    platform_ctx->capture_thread_handle = NULL;
  }

  if (platform_ctx->audio_client) {
    HRESULT hr =
        platform_ctx->audio_client->lpVtbl->Stop(platform_ctx->audio_client);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WASAPI Stop: Failed to stop audio client: 0x%lx", hr);
    }
  }
  miniav_log(MINIAV_LOG_LEVEL_INFO, "WASAPI: Capture stopped.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode
wasapi_release_buffer_platform(MiniAVLoopbackContext *ctx,
                               void *native_buffer_payload_resource_ptr) {
  MINIAV_UNUSED(ctx);
  MINIAV_UNUSED(native_buffer_payload_resource_ptr);
  return MINIAV_SUCCESS;
}

MiniAVResultCode wasapi_get_configured_format(MiniAVLoopbackContext *ctx,
                                              MiniAVAudioInfo *format_out) {
  if (!ctx->is_configured || !ctx->platform_ctx) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  *format_out = ctx->configured_format;
  return MINIAV_SUCCESS;
}

// --- Ops Table ---
static const LoopbackContextInternalOps g_wasapi_loopback_ops = {
    .init_platform = wasapi_init_platform,
    .destroy_platform = wasapi_destroy_platform,
    .enumerate_targets_platform = NULL,
    .configure_loopback = wasapi_configure_loopback,
    .start_capture = wasapi_start_capture,
    .stop_capture = wasapi_stop_capture,
    .release_buffer_platform = wasapi_release_buffer_platform,
    .get_configured_format = wasapi_get_configured_format};

const LoopbackContextInternalOps *miniav_loopback_get_win_ops(void) {
  return &g_wasapi_loopback_ops;
}

#endif // _WIN32