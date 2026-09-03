#ifdef _WIN32
#include <initguid.h>

#include <Audioclient.h>
#include <mmdeviceapi.h> // For IID_IMMDeviceEnumerator, CLSID_MMDeviceEnumerator, IMMDevice
#include <windows.h> // Base Windows types
// For PKEY_Device_FriendlyName, IPropertyStore. propsys.h includes objidl.h
// which might also declare GUIDs.
#include <audiopolicy.h> // For IAudioSessionManager2, IAudioSessionControl, IAudioSessionControl2
#include <functiondiscoverykeys_devpkey.h> // Often needed for PKEY definitions
#include <propsys.h>
// ksmedia.h was for KSDATAFORMAT_... GUIDs, which seem resolved now, but good
// to keep if used.
#include <ksmedia.h>

// Per-process loopback activation parameters. The SDK gates this header on
// NTDDI_VERSION >= NTDDI_WIN10_FE (0x0A00000A, the Windows 10 build 20348 /
// Server 2022 wave) *and* on the APP partition, so simply #including it is not
// enough to know the types arrived. Rather than guess, gate on the same
// condition the SDK uses and provide a byte-identical fallback declaration
// otherwise — the layout is an OS ABI contract read by mmdevapi.dll, so the
// fallback is not a guess, and it keeps this file buildable against an SDK
// older than 10.0.20348 (where the runtime call will simply fail and be
// reported honestly).
#if defined(NTDDI_VERSION) && (NTDDI_VERSION >= 0x0A00000A) &&                 \
    WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_APP)
#include <audioclientactivationparams.h>
#define MINIAV_WASAPI_SDK_ACTIVATION_PARAMS 1
#else
#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VAD\\Process_Loopback"
typedef enum {
  PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE = 0,
  PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE = 1
} PROCESS_LOOPBACK_MODE;
typedef struct AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
  DWORD TargetProcessId;
  PROCESS_LOOPBACK_MODE ProcessLoopbackMode;
} AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS;
typedef enum {
  AUDIOCLIENT_ACTIVATION_TYPE_DEFAULT = 0,
  AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK = 1
} AUDIOCLIENT_ACTIVATION_TYPE;
typedef struct AUDIOCLIENT_ACTIVATION_PARAMS {
  AUDIOCLIENT_ACTIVATION_TYPE ActivationType;
  union {
    AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS ProcessLoopbackParams;
  } DUMMYUNIONNAME;
} AUDIOCLIENT_ACTIVATION_PARAMS;
#endif

// The SDK declares the params union with the DUMMYUNIONNAME macro, which
// expands to NOTHING unless NONAMELESSUNION is defined — i.e. the union is
// normally anonymous and `params.DUMMYUNIONNAME.X` is a syntax error, not the
// portable spelling it looks like.
#if defined(NONAMELESSUNION)
#define MINIAV_PROC_LOOPBACK_PARAMS(p) ((p).DUMMYUNIONNAME.ProcessLoopbackParams)
#else
#define MINIAV_PROC_LOOPBACK_PARAMS(p) ((p).ProcessLoopbackParams)
#endif
#endif

// Step 3: Include your project's headers
#include "../../common/miniav_com_win.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h"
#include "../../common/miniav_utils.h" // For miniav_calloc, miniav_free, miniav_strdup, MINIAV_UNUSED
#include "loopback_context_win_wasapi.h" // This header should declare types but not try to define these system GUIDs
#include <stdio.h> // For swprintf_s
#include <stdlib.h> // For getenv (test-only stress flags)

#ifdef _WIN32

const IID IID_IAudioCaptureClient = {
    0xc8adbd64,
    0xe71e,
    0x48a0,
    {0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17}};

// Add these:
const IID IID_IAudioSessionManager2 = {

    0x77AA99A0,
    0x1BD6,
    0x484F,
    {0x8B, 0xC7, 0x2C, 0x65, 0x4C, 0x9A, 0x9B, 0x6F}};

const IID IID_IAudioSessionControl2 = {
    0xbfb7ff88,
    0x7239,
    0x4fc9,
    {0x8f, 0xa2, 0x07, 0xc9, 0x50, 0xbe, 0x9c, 0x6d}};

// IID for the IAudioSessionEnumerator interface
const IID IID_IAudioSessionEnumerator = {
    0xe2f5bb11,
    0x0570,
    0x40ca,
    {0xac, 0xdd, 0x3a, 0xa0, 0x12, 0x77, 0xde, 0xe8}};

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

const IID IID_IAudioSessionManager = {
    0xA37CF45F,
    0x692C,
    0x4A3D,
    {0x95, 0x6A, 0x26, 0x10, 0x44, 0x4F, 0x74, 0xCC}};

// {41D949AB-9862-444A-80F6-C261334DA5EB}
static const IID MiniAV_IID_IActivateAudioInterfaceCompletionHandler = {
    0x41d949ab,
    0x9862,
    0x444a,
    {0x80, 0xf6, 0xc2, 0x61, 0x33, 0x4d, 0xa5, 0xeb}};

// {00000000-0000-0000-C000-000000000046}
static const IID MiniAV_IID_IUnknown = {
    0x00000000,
    0x0000,
    0x0000,
    {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

// {00000003-0000-0000-C000-000000000046}
static const IID MiniAV_IID_IMarshal = {
    0x00000003,
    0x0000,
    0x0000,
    {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

// {94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90}
static const IID MiniAV_IID_IAgileObject = {
    0x94ea2b94,
    0xe9cc,
    0x49e0,
    {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};

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
  UINT64 device_position; // Not used for timestamping in this context
  UINT64 qpc_position;    // This is the key timestamp from WASAPI

  HANDLE wait_array[2] = {platform_ctx->stop_event_handle,
                          platform_ctx->buffer_event_handle};
  DWORD wait_count = platform_ctx->event_driven_capture ? 2 : 1;
  BOOL device_invalidated = FALSE;

  // Join the MTA explicitly for the life of THIS thread.
  //
  // This thread calls IAudioCaptureClient/IAudioClient methods, and until now
  // it never joined an apartment at all. It worked only because the process
  // holds a permanent MTA usage reference (see miniav_com_win.h), which makes
  // an uninitialized thread an implicit MTA member, and because these are
  // direct in-process vtable calls with no marshalling. That is an accident of
  // the current design, not a contract: COM's rule is that a thread using COM
  // must be an apartment member.
  //
  // A DEDICATED thread is the one place the CoInitializeEx/CoUninitialize pair
  // is actually correct — we create it, we join it, and both calls happen on
  // the SAME thread with balanced lifetime. That is precisely what is NOT true
  // of per-FFI-call COM (the Dart VM hands an isolate's consecutive calls to
  // different pool threads), which is the bug miniav_com_win.c exists to fix.
  // The process-lifetime MTA reference also guarantees the CoUninitialize
  // below can never be the last one out and tear the MTA down.
  //
  // RPC_E_CHANGED_MODE would mean someone already put this thread in an STA;
  // impossible for a thread we just created, but if it ever happens we must
  // NOT call CoUninitialize (we would be unbalancing someone else's init).
  const HRESULT co_hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  const BOOL co_owned = SUCCEEDED(co_hr);
  if (!co_owned) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WASAPI: capture thread CoInitializeEx returned 0x%lx; "
               "continuing on the process MTA reference.",
               (unsigned long)co_hr);
  }
  miniav_com_trace("wasapi_capture_thread_proc", (unsigned long)co_hr);

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI: Capture thread started (mode: %s).",
             platform_ctx->event_driven_capture ? "event-driven" : "polling");

  while (TRUE) {
    DWORD wait_result;
    if (platform_ctx->event_driven_capture) {
      wait_result = WaitForMultipleObjects(wait_count, wait_array, FALSE,
                                           2000); // 2s safety timeout
    } else {
      wait_result = WaitForSingleObject(platform_ctx->stop_event_handle,
                                        5); // Poll every 5ms
    }

    if (wait_result == WAIT_OBJECT_0) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI: Capture thread received stop event.");
      break;
    } else if (wait_result == WAIT_OBJECT_0 + 1 ||
               wait_result == WAIT_TIMEOUT) {
      // Buffer event signaled or timeout — drain available packets
    } else if (wait_result == WAIT_FAILED) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI: Capture thread wait failed: %lu",
                 GetLastError());
      break;
    }

    hr = platform_ctx->capture_client->lpVtbl->GetNextPacketSize(
        platform_ctx->capture_client, &packet_length);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI: GetNextPacketSize failed: 0x%lx", hr);
      if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
        device_invalidated = TRUE;
        break;   // Device lost, exit thread
      }
      Sleep(20); // Wait a bit before retrying on other errors
      continue;
    }

    while (packet_length != 0) {
      hr = platform_ctx->capture_client->lpVtbl->GetBuffer(
          platform_ctx->capture_client, &data_ptr, &num_frames_available,
          &flags, &device_position, &qpc_position);

      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI: GetBuffer failed: 0x%lx",
                   hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
          device_invalidated = TRUE;
          goto cleanup_thread; // Device lost, exit thread
        }
        break; // Break from inner loop, outer loop will retry GetNextPacketSize
      }

      if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI: Silent packet received (frames: %u). QPC: %llu",
                   num_frames_available, qpc_position);
        // If you need to generate silence, do it here.
        // For now, if data_ptr is NULL, we might skip, or the app callback
        // handles it.
      }

      // Only allocate + dispatch if callbacks are currently enabled.  This
      // avoids leaking the heap buffer/PCM copy when MiniAV_Dispose has been
      // called (e.g. during Flutter hot restart) and the dispatch would be
      // a no-op.  We hold the dispatch guard for the whole window so the Dart
      // NativeCallable cannot be torn down between alloc and post.
      if (num_frames_available > 0 && ctx->app_callback &&
          miniav_dispatch_guard_acquire_if_enabled()) {
        // IMPORTANT: app_callback is a Dart NativeCallable.listener — it posts
        // to the Dart event queue and returns immediately.  By the time Dart
        // processes the event, the WASAPI data_ptr will already have been
        // released via IAudioCaptureClient::ReleaseBuffer below, and the
        // stack-allocated MiniAVBuffer will have been overwritten by the next
        // loop iteration.  We must heap-allocate both the buffer struct and a
        // copy of the audio data so they remain valid until Dart calls
        // MiniAV_ReleaseBuffer.
        const size_t audio_bytes =
            (flags & AUDCLNT_BUFFERFLAGS_SILENT)
                ? 0
                : (size_t)num_frames_available *
                      platform_ctx->capture_format->nBlockAlign;

        MiniAVNativeBufferInternalPayload *payload =
            (MiniAVNativeBufferInternalPayload *)miniav_calloc(
                1, sizeof(MiniAVNativeBufferInternalPayload));
        MiniAVBuffer *heap_buf =
            (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
        void *audio_copy = NULL;
        if (audio_bytes > 0) {
          audio_copy = miniav_calloc(audio_bytes, 1);
        }

        if (!payload || !heap_buf || (audio_bytes > 0 && !audio_copy)) {
          miniav_free(payload);
          miniav_free(heap_buf);
          miniav_free(audio_copy);
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WASAPI: OOM allocating audio buffer payload.");
          miniav_dispatch_guard_release();
          goto release_wasapi_buffer;
        }

        if (audio_bytes > 0) {
          memcpy(audio_copy, data_ptr, audio_bytes);
        }

        // Compute timestamp.
        uint64_t ts_us;
        if (platform_ctx->qpc_frequency.QuadPart != 0) {
          ts_us =
              (qpc_position * 1000000) / platform_ctx->qpc_frequency.QuadPart;
        } else {
          ts_us = miniav_get_time_us();
        }

        heap_buf->type = MINIAV_BUFFER_TYPE_AUDIO;
        heap_buf->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
        heap_buf->timestamp_us = ts_us;
        heap_buf->data.audio.data = audio_copy; // NULL for silent packets
        heap_buf->data_size_bytes = audio_bytes;
        heap_buf->data.audio.info = ctx->configured_video_format;
        heap_buf->data.audio.info.num_frames = num_frames_available;
        heap_buf->data.audio.frame_count = num_frames_available;

        // MiniAV_ReleaseBuffer will free audio_copy + heap_buf via the payload.
        payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO;
        payload->native_singular_resource_ptr = audio_copy;
        payload->parent_miniav_buffer_ptr = heap_buf;
        heap_buf->internal_handle = payload;

        ctx->app_callback(heap_buf, ctx->app_callback_user_data);
        miniav_dispatch_guard_release();
      }

release_wasapi_buffer:

      hr = platform_ctx->capture_client->lpVtbl->ReleaseBuffer(
          platform_ctx->capture_client, num_frames_available);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI: ReleaseBuffer failed: 0x%lx", hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
          device_invalidated = TRUE;
          goto cleanup_thread; // Device lost, exit thread
        }
      }

      // Get the next packet size for the loop condition
      hr = platform_ctx->capture_client->lpVtbl->GetNextPacketSize(
          platform_ctx->capture_client, &packet_length);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI: GetNextPacketSize (in loop) failed: 0x%lx", hr);
        if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
          device_invalidated = TRUE;
          goto cleanup_thread; // Device lost, exit thread
        }
        packet_length = 0;     // Ensure loop terminates on error
      }
    }
  }

cleanup_thread:
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Capture thread exiting.");
  if (device_invalidated) {
    // Mark capture as no longer running so subsequent stop/destroy is a no-op
    // on the WASAPI side, then notify the application.
    ctx->is_running = false;
    if (ctx->lost_cb) {
      ctx->lost_cb((int)MINIAV_ERROR_DEVICE_LOST, ctx->lost_cb_user_data);
    }
  }
  // Balances the CoInitializeEx at the top, on the SAME thread. Deliberately
  // after lost_cb: the app's handler may itself touch COM, and it should run
  // while this thread is still an apartment member. Every exit path in this
  // function reaches this label, so the pair cannot be skipped.
  if (co_owned) {
    CoUninitialize();
  }
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

  // Initialize QPC Frequency
  if (!QueryPerformanceFrequency(&platform_ctx->qpc_frequency)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI: QueryPerformanceFrequency failed: %lu", GetLastError());
    miniav_free(platform_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  if (platform_ctx->qpc_frequency.QuadPart == 0) { // Should not happen
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI: QPC frequency is zero.");
    miniav_free(platform_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Create the stop event
  platform_ctx->stop_event_handle = CreateEvent(
      NULL, TRUE, FALSE, NULL); // Manual reset, initially non-signaled
  if (platform_ctx->stop_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI: CreateEvent for stop_event failed: %lu",
               GetLastError());
    miniav_free(platform_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  platform_ctx->buffer_event_handle = CreateEvent(
      NULL, FALSE, FALSE, NULL); // Auto-reset, initially non-signaled
  if (platform_ctx->buffer_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI: CreateEvent for buffer_event failed: %lu",
               GetLastError());
    CloseHandle(platform_ctx->stop_event_handle);
    miniav_free(platform_ctx);
    ctx->platform_ctx = NULL;
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!miniav_com_legacy_percall()) {
    // Apartment membership is process-lifetime and library-owned — see
    // miniav_com_win.h. Notably this also covers wasapi_capture_thread_proc,
    // which never called CoInitializeEx at all.
    miniav_com_ensure_mta();
    miniav_com_trace("wasapi_init_platform", 0);
  } else {
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    miniav_com_trace("legacy CoInitializeEx/wasapi_init_platform",
                     (unsigned long)hr);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR, "WASAPI: CoInitializeEx failed: 0x%lx",
                 hr);
      CloseHandle(platform_ctx->stop_event_handle); // Clean up created event
      miniav_free(platform_ctx);
      ctx->platform_ctx = NULL;
      return hresult_to_miniavresult(hr);
    }
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
  if (platform_ctx->capture_thread_handle) {
    // Stop timed out (or was never run) and the capture thread is still
    // alive — it dereferences platform_ctx, so retry the join and, failing
    // that, deliberately LEAK the platform context rather than free memory
    // a live thread uses.
    if (WaitForSingleObject(platform_ctx->capture_thread_handle, 7000) !=
        WAIT_OBJECT_0) {
      // The capture thread was created with the PARENT ctx as its parameter
      // and dereferences it on every iteration — MINIAV_ERROR_TIMEOUT tells
      // MiniAV_Loopback_DestroyContext to leak that too.
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Destroy: capture thread still alive — leaking the "
                 "context to avoid a use-after-free.");
      ctx->platform_ctx = NULL;
      return MINIAV_ERROR_TIMEOUT;
    }
    CloseHandle(platform_ctx->capture_thread_handle);
    platform_ctx->capture_thread_handle = NULL;
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
  if (platform_ctx->buffer_event_handle) {
    CloseHandle(platform_ctx->buffer_event_handle);
    platform_ctx->buffer_event_handle = NULL;
  }

  miniav_free(platform_ctx);
  ctx->platform_ctx = NULL;

  if (miniav_com_legacy_percall()) {
    // Unbalanced by construction: the matching CoInitializeEx may have run on
    // a different pool thread, or on a thread another isolate still relies on.
    CoUninitialize();
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

static BOOL get_process_name_by_pid(DWORD pid, char *name_buffer,
                                    DWORD buffer_size) {
  HANDLE process_handle =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process_handle == NULL) {
    // Try with PROCESS_QUERY_INFORMATION | PROCESS_VM_READ for older systems or
    // if more rights are needed
    process_handle =
        OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (process_handle == NULL)
      return FALSE;
  }

  BOOL result = FALSE;
  WCHAR image_path[MAX_PATH];
  if (QueryFullProcessImageNameW(process_handle, 0, image_path,
                                 &((DWORD){MAX_PATH}))) {
    LPCWSTR exe_name = wcsrchr(image_path, L'\\');
    exe_name = exe_name ? exe_name + 1 : image_path;
    char *utf8_exe_name = lpwstr_to_utf8(exe_name);
    if (utf8_exe_name) {
      strncpy(name_buffer, utf8_exe_name, buffer_size - 1);
      name_buffer[buffer_size - 1] = '\0';
      miniav_free(utf8_exe_name);
      result = TRUE;
    }
  }
  CloseHandle(process_handle);
  return result;
}

typedef struct EnumWindowsCallbackData {
  MiniAVDeviceInfo *devices;
  uint32_t current_count;
  uint32_t max_count;
} EnumWindowsCallbackData;

static BOOL CALLBACK enum_windows_proc(HWND hwnd, LPARAM lParam) {
  EnumWindowsCallbackData *data = (EnumWindowsCallbackData *)lParam;
  if (data->current_count >= data->max_count) {
    return FALSE; // Stop enumeration if buffer is full
  }

  if (!IsWindowVisible(hwnd)) {
    return TRUE; // Skip non-visible windows
  }

  int length = GetWindowTextLengthW(hwnd);
  if (length == 0) {
    return TRUE; // Skip windows with no title
  }

  WCHAR title_wstr[MINIAV_DEVICE_NAME_MAX_LEN]; // Assuming similar max length
                                                // for names
  GetWindowTextW(hwnd, title_wstr, MINIAV_DEVICE_NAME_MAX_LEN);

  char *title_utf8 = lpwstr_to_utf8(title_wstr);
  if (title_utf8) {
    // Use HWND as a string for device_id. Format: "hwnd:0xADDRESS"
    snprintf(data->devices[data->current_count].device_id,
             MINIAV_DEVICE_ID_MAX_LEN, "hwnd:%p", hwnd);
    strncpy(data->devices[data->current_count].name, title_utf8,
            MINIAV_DEVICE_NAME_MAX_LEN - 1);
    data->devices[data->current_count].name[MINIAV_DEVICE_NAME_MAX_LEN - 1] =
        '\0';
    data->devices[data->current_count].is_default =
        FALSE; // Windows are not "default" targets
    data->current_count++;
    miniav_free(title_utf8);
  }
  return TRUE;
}

MiniAVResultCode
waspi_enumerate_targets(MiniAVLoopbackTargetType target_type_filter,
                        MiniAVDeviceInfo **targets_out, uint32_t *count_out) {
  if (!targets_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *targets_out = NULL;
  *count_out = 0;

  HRESULT hr;
  MiniAVDeviceInfo *temp_devices_list = NULL;
  uint32_t found_count = 0;
  const uint32_t MAX_POTENTIAL_TARGETS =
      256; // Max devices/processes/windows to list
  MiniAVResultCode result_code = MINIAV_SUCCESS;

  BOOL com_initialized_here = FALSE;
  if (!miniav_com_legacy_percall()) {
    miniav_com_ensure_mta();
    miniav_com_trace("wasapi_enumerate_targets", 0);
    hr = S_OK;
  } else {
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    miniav_com_trace("legacy CoInitializeEx/wasapi_enumerate_targets",
                     (unsigned long)hr);
    if (SUCCEEDED(hr)) {
      com_initialized_here = TRUE;
      if (hr == S_FALSE)
        com_initialized_here = FALSE; // Already initialized
    } else if (hr != RPC_E_CHANGED_MODE) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Enum: CoInitializeEx failed: 0x%lx", hr);
      return hresult_to_miniavresult(hr);
    }
  }

  temp_devices_list = (MiniAVDeviceInfo *)miniav_calloc(
      MAX_POTENTIAL_TARGETS, sizeof(MiniAVDeviceInfo));
  if (!temp_devices_list) {
    result_code = MINIAV_ERROR_OUT_OF_MEMORY;
    goto cleanup_enum;
  }

  if (target_type_filter == MINIAV_LOOPBACK_TARGET_PROCESS) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI Enum: Enumerating process targets across all active "
               "render devices.");
    IMMDeviceEnumerator *all_device_enumerator = NULL;
    IMMDeviceCollection *device_collection = NULL;
    // session_manager, session_enum, etc. will be obtained per-device in the
    // loop

    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                          &IID_IMMDeviceEnumerator,
                          (void **)&all_device_enumerator);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Enum Process: CoCreateInstance for "
                 "IMMDeviceEnumerator failed: 0x%lx",
                 hr);
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_proc_enum_all_devices; // New cleanup label
    }

    hr = all_device_enumerator->lpVtbl->EnumAudioEndpoints(
        all_device_enumerator, eRender, DEVICE_STATE_ACTIVE,
        &device_collection);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Enum Process: EnumAudioEndpoints failed: 0x%lx", hr);
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_proc_enum_all_devices;
    }

    UINT device_count = 0;
    hr = device_collection->lpVtbl->GetCount(device_collection, &device_count);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Enum Process: DeviceCollection GetCount failed: 0x%lx",
                 hr);
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_proc_enum_all_devices;
    }

    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI Enum Process: Found %u active render devices to check.",
               device_count);

    for (UINT i = 0; i < device_count; ++i) {
      IMMDevice *current_device = NULL;
      IAudioSessionManager2 *session_manager = NULL;
      IAudioSessionEnumerator *session_enum = NULL;

      hr = device_collection->lpVtbl->Item(device_collection, i,
                                           &current_device);
      if (FAILED(hr) || !current_device) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WASAPI Enum Process: Failed to get device item %u: 0x%lx",
                   i, hr);
        continue;
      }

      // Attempt to activate IAudioSessionManager2 on the current_device
      hr = current_device->lpVtbl->Activate(
          current_device, &IID_IAudioSessionManager2, CLSCTX_ALL, NULL,
          (void **)&session_manager);

      if (FAILED(hr)) {
        if (hr == E_NOINTERFACE) {
          // Log that this specific device doesn't support it, but continue to
          // the next device
          LPWSTR dbg_dev_id_wstr = NULL;
          current_device->lpVtbl->GetId(current_device, &dbg_dev_id_wstr);
          char *dbg_dev_id_utf8 = dbg_dev_id_wstr
                                      ? lpwstr_to_utf8(dbg_dev_id_wstr)
                                      : miniav_strdup("(unknown ID)");
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WASAPI Enum Process: Device %s does not support "
                     "IAudioSessionManager2 (0x%lx). Skipping.",
                     dbg_dev_id_utf8 ? dbg_dev_id_utf8 : "(conversion failed)",
                     hr);
          if (dbg_dev_id_wstr)
            CoTaskMemFree(dbg_dev_id_wstr);
          if (dbg_dev_id_utf8)
            miniav_free(dbg_dev_id_utf8);
        } else {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WASAPI Enum Process: Failed to activate "
                     "IAudioSessionManager2 on device %u: 0x%lx. Skipping.",
                     i, hr);
        }
        if (session_manager)
          session_manager->lpVtbl->Release(
              session_manager); // Should be NULL if Activate failed
        current_device->lpVtbl->Release(current_device);
        continue; // Try next device
      }
      miniav_log(
          MINIAV_LOG_LEVEL_DEBUG,
          "WASAPI Enum Process: IAudioSessionManager2 activated for device %u.",
          i);

      hr = session_manager->lpVtbl->GetSessionEnumerator(session_manager,
                                                         &session_enum);
      if (FAILED(hr) || !session_enum) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WASAPI Enum Process: GetSessionEnumerator failed for "
                   "device %u: 0x%lx. Skipping.",
                   i, hr);
        if (session_enum)
          session_enum->lpVtbl->Release(session_enum);
        session_manager->lpVtbl->Release(session_manager);
        current_device->lpVtbl->Release(current_device);
        continue;
      }

      int session_count = 0;
      hr = session_enum->lpVtbl->GetCount(session_enum, &session_count);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WASAPI Enum Process: SessionEnumerator GetCount failed for "
                   "device %u: 0x%lx. Skipping.",
                   i, hr);
        session_enum->lpVtbl->Release(session_enum);
        session_manager->lpVtbl->Release(session_manager);
        current_device->lpVtbl->Release(current_device);
        continue;
      }
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Enum Process: Device %u has %d audio sessions.", i,
                 session_count);

      for (int j = 0; j < session_count && found_count < MAX_POTENTIAL_TARGETS;
           ++j) {
        IAudioSessionControl *session_control = NULL;
        IAudioSessionControl2 *session_control2 = NULL;
        DWORD process_id = 0;

        hr =
            session_enum->lpVtbl->GetSession(session_enum, j, &session_control);
        if (FAILED(hr) || !session_control) {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WASAPI Enum Process: GetSession failed for session %d on "
                     "device %u: 0x%lx",
                     j, i, hr);
          continue;
        }

        hr = session_control->lpVtbl->QueryInterface(
            session_control, &IID_IAudioSessionControl2,
            (void **)&session_control2);
        if (SUCCEEDED(hr) && session_control2) {
          hr = session_control2->lpVtbl->GetProcessId(session_control2,
                                                      &process_id);
          if (SUCCEEDED(hr) && process_id != 0 &&
              process_id != GetCurrentProcessId()) {
            char process_name[MINIAV_DEVICE_NAME_MAX_LEN] = "Unknown Process";
            get_process_name_by_pid(process_id, process_name,
                                    MINIAV_DEVICE_NAME_MAX_LEN);

            BOOL already_added = FALSE;
            char pid_str_check[MINIAV_DEVICE_ID_MAX_LEN];
            snprintf(pid_str_check, MINIAV_DEVICE_ID_MAX_LEN, "pid:%lu",
                     process_id);
            for (uint32_t k = 0; k < found_count; ++k) {
              if (strcmp(temp_devices_list[k].device_id, pid_str_check) == 0) {
                already_added = TRUE;
                break;
              }
            }

            if (!already_added) {
              strncpy(temp_devices_list[found_count].name, process_name,
                      MINIAV_DEVICE_NAME_MAX_LEN - 1);
              temp_devices_list[found_count]
                  .name[MINIAV_DEVICE_NAME_MAX_LEN - 1] = '\0';
              snprintf(temp_devices_list[found_count].device_id,
                       MINIAV_DEVICE_ID_MAX_LEN, "pid:%lu", process_id);
              temp_devices_list[found_count].is_default =
                  FALSE; // Individual processes are not "default" targets
              found_count++;
            }
          } else if (FAILED(hr) && hr != AUDCLNT_E_ENDPOINT_CREATE_FAILED) {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "WASAPI Enum Process: GetProcessId failed for session "
                       "%d on device %u: 0x%lx",
                       j, i, hr);
          }
          session_control2->lpVtbl->Release(session_control2);
        } else if (FAILED(hr)) {
          miniav_log(
              MINIAV_LOG_LEVEL_WARN,
              "WASAPI Enum Process: QueryInterface for IAudioSessionControl2 "
              "failed for session %d on device %u: 0x%lx",
              j, i, hr);
        }
        session_control->lpVtbl->Release(session_control);
      } // end for each session

      if (session_enum)
        session_enum->lpVtbl->Release(session_enum);
      if (session_manager)
        session_manager->lpVtbl->Release(session_manager);
      if (current_device)
        current_device->lpVtbl->Release(current_device);
    } // end for each device

  cleanup_proc_enum_all_devices: // New cleanup label
    if (device_collection)
      device_collection->lpVtbl->Release(device_collection);
    if (all_device_enumerator)
      all_device_enumerator->lpVtbl->Release(all_device_enumerator);
    // result_code should be set if an error occurred before this point that
    // warrants aborting. If we successfully iterated all devices, result_code
    // remains MINIAV_SUCCESS.

  } else if (target_type_filter == MINIAV_LOOPBACK_TARGET_WINDOW) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI Enum: Enumerating window targets.");
    EnumWindowsCallbackData callback_data = {temp_devices_list, 0,
                                             MAX_POTENTIAL_TARGETS};
    EnumWindows(enum_windows_proc, (LPARAM)&callback_data);
    found_count = callback_data.current_count;
  } else if (target_type_filter == MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO ||
             target_type_filter == MINIAV_LOOPBACK_TARGET_NONE) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI Enum: Enumerating system audio render devices.");
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDeviceCollection *collection = NULL;
    uint32_t system_device_count = 0;

    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                          &IID_IMMDeviceEnumerator, (void **)&enumerator);
    if (FAILED(hr)) {
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_sys_enum;
    }

    hr = enumerator->lpVtbl->EnumAudioEndpoints(
        enumerator, eRender, DEVICE_STATE_ACTIVE, &collection);
    if (FAILED(hr)) {
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_sys_enum;
    }

    hr = collection->lpVtbl->GetCount(collection, &system_device_count);
    if (FAILED(hr)) {
      result_code = hresult_to_miniavresult(hr);
      goto cleanup_sys_enum;
    }

    if (system_device_count > 0) {
      LPWSTR actual_default_device_id_wstr =
          NULL; // Store the true default device ID once
      IMMDevice *default_render_device_for_check = NULL;

      // Get the actual default device ID once before the loop
      if (SUCCEEDED(enumerator->lpVtbl->GetDefaultAudioEndpoint(
              enumerator, eRender, eConsole,
              &default_render_device_for_check))) {
        if (FAILED(default_render_device_for_check->lpVtbl->GetId(
                default_render_device_for_check,
                &actual_default_device_id_wstr))) {
          actual_default_device_id_wstr =
              NULL; // Ensure it's NULL if GetId failed
        }
        default_render_device_for_check->lpVtbl->Release(
            default_render_device_for_check);
      }

      for (UINT i = 0;
           i < system_device_count && found_count < MAX_POTENTIAL_TARGETS;
           ++i) {
        IMMDevice *device = NULL;
        LPWSTR current_device_id_wstr = NULL; // Renamed for clarity
        IPropertyStore *props = NULL;
        PROPVARIANT var_name;
        PropVariantInit(&var_name);

        hr = collection->lpVtbl->Item(collection, i, &device);
        if (FAILED(hr)) {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WASAPI Enum: Failed to get device item %u: 0x%lx", i, hr);
          continue;
        }

        hr = device->lpVtbl->GetId(device, &current_device_id_wstr);
        if (FAILED(hr) ||
            !current_device_id_wstr) { // Check if current_device_id_wstr is
                                       // NULL
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WASAPI Enum: Failed to get ID for device item %u: 0x%lx",
                     i, hr);
          if (current_device_id_wstr)
            CoTaskMemFree(
                current_device_id_wstr); // Free if allocated but hr FAILED
          device->lpVtbl->Release(device);
          continue;
        }
        // Successfully got current_device_id_wstr

        char *device_id_utf8 = lpwstr_to_utf8(current_device_id_wstr);
        if (device_id_utf8) {
          strncpy(temp_devices_list[found_count].device_id, device_id_utf8,
                  MINIAV_DEVICE_ID_MAX_LEN - 1);
          temp_devices_list[found_count]
              .device_id[MINIAV_DEVICE_ID_MAX_LEN - 1] = '\0';
          miniav_free(device_id_utf8);
        } else {
          // Handle error or set a default ID string
          strncpy(temp_devices_list[found_count].device_id, "(error_id)",
                  MINIAV_DEVICE_ID_MAX_LEN - 1);
        }

        hr = device->lpVtbl->OpenPropertyStore(device, STGM_READ, &props);
        if (SUCCEEDED(hr)) {
          hr = props->lpVtbl->GetValue(props, &PKEY_Device_FriendlyName,
                                       &var_name);
          if (SUCCEEDED(hr) && var_name.vt == VT_LPWSTR) {
            char *friendly_name_utf8 = lpwstr_to_utf8(var_name.pwszVal);
            if (friendly_name_utf8) {
              strncpy(temp_devices_list[found_count].name, friendly_name_utf8,
                      MINIAV_DEVICE_NAME_MAX_LEN - 1);
              temp_devices_list[found_count]
                  .name[MINIAV_DEVICE_NAME_MAX_LEN - 1] = '\0';
              miniav_free(friendly_name_utf8);
            } else {
              strncpy(temp_devices_list[found_count].name, "(error_name)",
                      MINIAV_DEVICE_NAME_MAX_LEN - 1);
            }
          } else {
            strncpy(temp_devices_list[found_count].name, "(no_name)",
                    MINIAV_DEVICE_NAME_MAX_LEN - 1);
          }
          PropVariantClear(&var_name);
          props->lpVtbl->Release(props);
        } else {
          strncpy(temp_devices_list[found_count].name, "(no_props)",
                  MINIAV_DEVICE_NAME_MAX_LEN - 1);
        }

        // Check if this is the default device using the pre-fetched
        // actual_default_device_id_wstr
        if (actual_default_device_id_wstr &&
            current_device_id_wstr) { // Ensure both are valid
          if (wcscmp(current_device_id_wstr, actual_default_device_id_wstr) ==
              0) {
            temp_devices_list[found_count].is_default = TRUE;
          } else {
            temp_devices_list[found_count].is_default = FALSE;
          }
        } else {
          temp_devices_list[found_count].is_default = FALSE;
        }

        // Now it's safe to free current_device_id_wstr
        if (current_device_id_wstr) {
          CoTaskMemFree(current_device_id_wstr);
        }

        device->lpVtbl->Release(device);
        found_count++;
      }

      if (actual_default_device_id_wstr) { // Free the default ID string
                                           // obtained before the loop
        CoTaskMemFree(actual_default_device_id_wstr);
      }
    }
  cleanup_sys_enum:
    if (collection)
      collection->lpVtbl->Release(collection);
    if (enumerator)
      enumerator->lpVtbl->Release(enumerator);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WASAPI Enum: Unsupported target_type_filter: %d",
               target_type_filter);
    result_code = MINIAV_ERROR_INVALID_ARG;
  }

  if (result_code == MINIAV_SUCCESS && found_count > 0) {
    *targets_out = (MiniAVDeviceInfo *)miniav_calloc(found_count,
                                                     sizeof(MiniAVDeviceInfo));
    if (*targets_out) {
      memcpy(*targets_out, temp_devices_list,
             found_count * sizeof(MiniAVDeviceInfo));
      *count_out = found_count;
    } else {
      result_code = MINIAV_ERROR_OUT_OF_MEMORY;
      *count_out = 0;
    }
  } else if (result_code == MINIAV_SUCCESS && found_count == 0) {
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "WASAPI Enum: No targets found for filter type %d.",
               target_type_filter);
    // Still success, just no devices.
  }

cleanup_enum:
  if (temp_devices_list)
    miniav_free(temp_devices_list);
  if (com_initialized_here)
    CoUninitialize();
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI Enum: Enumerated %u targets.",
             *count_out);
  return result_code;
}

// ===========================================================================
// Per-process loopback (ActivateAudioInterfaceAsync)
// ===========================================================================
//
// The ONLY Windows mechanism that scopes loopback capture to a process is
// ActivateAudioInterfaceAsync() against the pseudo-endpoint
// VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, with AUDIOCLIENT_ACTIVATION_PARAMS
// carrying the target PID. Minimum: Windows 10 build 20348 (Server 2022) /
// Windows 11 (verified against the AUDIOCLIENT_ACTIVATION_PARAMS reference).
//
// WHAT THIS REPLACES. The previous code called
//     IAudioClient3::InitializeSharedAudioStream(flags, <PID>, fmt, NULL)
// with the target PID in the third argument, commented "this non-zero PID
// enables process-specific capture". That argument is PeriodInFrames — a
// period, in frames. A PID is never a legal period, so the call ALWAYS failed
// with AUDCLNT_E_INVALID_DEVICE_PERIOD (0x88890021) and the backend fell back
// to whole-system loopback. Per-process loopback had therefore never worked
// once: every caller asking for one process's audio silently received the
// entire system's audio — right format, wrong content, no error, no log above
// DEBUG. IAudioClient3 has nothing to do with process loopback and is gone.
//
// TRAP 1 — THE HANDLER MUST BE AGILE. ActivateAudioInterfaceAsync returns
//   E_ILLEGAL_METHOD_CALL (0x8000000E) — before it ever looks at the
//   activation params — if the completion handler is not agile. A plain C
//   vtable object that answers QueryInterface for IUnknown and the handler
//   interface only is NOT enough: it must also answer IAgileObject and
//   delegate IMarshal to a free-threaded marshaler. The C++ samples inherit
//   this from WRL's FtmBase, which is why the requirement is invisible in the
//   documentation. Measured here: without IAgileObject the call fails 100% of
//   the time; with it, 100% success.
//
// TRAP 2 — THERE IS NO MIX FORMAT. IAudioClient::GetMixFormat() returns
//   E_NOTIMPL (0x80004001) on a process-loopback client. Unlike endpoint
//   loopback, the CALLER picks the format and the capture engine converts into
//   it (48000, 44100 and 16000 Hz were each accepted for the same target on
//   this machine). So process loopback genuinely negotiates, and whatever we
//   set here is what MiniAV_Loopback_GetConfiguredFormat and every delivered
//   buffer must report.
//
// TRAP 3 — A DEAD PID IS SILENT, NOT FAILED. Activating for a PID that does
//   not exist SUCCEEDS and then delivers an endless stream of zeroed frames.
//   Nothing in WASAPI will ever say the target is not there. The PID is
//   therefore validated with OpenProcess() before activation, so "that process
//   is gone" is an error instead of indistinguishable silence.
//
// INCLUDE_TARGET_PROCESS_TREE vs EXCLUDE: include-tree. "Capture this app"
// means the app as the user sees it, and browsers, Electron shells and game
// launchers routinely render audio from a child process — excluding the tree
// would make those targets silent, which is the same class of lie this change
// exists to remove. EXCLUDE_TARGET_PROCESS_TREE answers the opposite question
// ("everything except me") and is not what any MiniAV caller asks for.

typedef struct WasapiActivateHandler {
  IActivateAudioInterfaceCompletionHandlerVtbl *lpVtbl;
  LONG ref_count;
  HANDLE completed_event;
  IUnknown *ftm; // free-threaded marshaler; see TRAP 1
} WasapiActivateHandler;

static HRESULT STDMETHODCALLTYPE wasapi_activate_handler_qi(
    IActivateAudioInterfaceCompletionHandler *This, REFIID riid, void **ppv) {
  WasapiActivateHandler *self = (WasapiActivateHandler *)This;
  if (!ppv)
    return E_POINTER;
  if (IsEqualGUID(riid, &MiniAV_IID_IUnknown) ||
      IsEqualGUID(riid,
                  &MiniAV_IID_IActivateAudioInterfaceCompletionHandler) ||
      IsEqualGUID(riid, &MiniAV_IID_IAgileObject)) {
    *ppv = This;
    This->lpVtbl->AddRef(This);
    return S_OK;
  }
  if (IsEqualGUID(riid, &MiniAV_IID_IMarshal) && self->ftm) {
    return self->ftm->lpVtbl->QueryInterface(self->ftm, riid, ppv);
  }
  *ppv = NULL;
  return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE wasapi_activate_handler_addref(
    IActivateAudioInterfaceCompletionHandler *This) {
  return (ULONG)InterlockedIncrement(
      &((WasapiActivateHandler *)This)->ref_count);
}

static ULONG STDMETHODCALLTYPE wasapi_activate_handler_release(
    IActivateAudioInterfaceCompletionHandler *This) {
  WasapiActivateHandler *self = (WasapiActivateHandler *)This;
  LONG n = InterlockedDecrement(&self->ref_count);
  if (n == 0) {
    // The OS may still hold a reference when we give ours up (e.g. after a
    // wait timeout), so the object frees ITSELF at zero rather than being
    // freed by the caller. A stack object here would be a use-after-free.
    if (self->ftm)
      self->ftm->lpVtbl->Release(self->ftm);
    if (self->completed_event)
      CloseHandle(self->completed_event);
    miniav_free(self);
  }
  return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE wasapi_activate_handler_completed(
    IActivateAudioInterfaceCompletionHandler *This,
    IActivateAudioInterfaceAsyncOperation *op) {
  MINIAV_UNUSED(op);
  SetEvent(((WasapiActivateHandler *)This)->completed_event);
  return S_OK;
}

static IActivateAudioInterfaceCompletionHandlerVtbl
    g_wasapi_activate_handler_vtbl = {
        wasapi_activate_handler_qi, wasapi_activate_handler_addref,
        wasapi_activate_handler_release, wasapi_activate_handler_completed};

// TEST-ONLY: MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK=1 skips the real
// per-process activation entirely, restoring the pre-fix situation in which a
// per-process request cannot be honoured. Combined with
// MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1 it reproduces the exact old bug
// (whole-system audio handed back as if it were one process's), which is the
// positive control for src/loopback/test/test_loopback_process_isolation.c.
// Never set in production.
static int wasapi_stress_no_process_loopback(void) {
  static int cached = -1;
  if (cached < 0) {
    const char *v = getenv("MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK");
    cached = (v && v[0] == '1') ? 1 : 0;
    if (cached) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI: MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK=1 — real "
                 "per-process loopback disabled (test-only).");
    }
  }
  return cached;
}

// OPT-IN: MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1 permits a per-process
// request that cannot be honoured to degrade to whole-system loopback. It is
// OFF by default: substituting the whole system's audio for one process's is
// exactly the failure this change exists to remove, and a caller cannot tell
// the difference from the PCM. When it is on, the substitution is logged at
// ERROR and MiniAV_Loopback_GetActiveTargetInfo reports SYSTEM_AUDIO, so a
// caller can still tell.
static int wasapi_allow_system_fallback(void) {
  static int cached = -1;
  if (cached < 0) {
    const char *v = getenv("MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK");
    cached = (v && v[0] == '1') ? 1 : 0;
  }
  return cached;
}

// TRAP 3: distinguish "no such process" from "alive but out of reach".
static BOOL wasapi_process_is_alive(DWORD pid) {
  if (pid == 0)
    return FALSE;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!h)
    h = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);
  if (!h) {
    // ERROR_ACCESS_DENIED means the process EXISTS but we may not open it
    // (elevated or protected). Process loopback still works against such a
    // target, so refusing would be its own lie. Anything else — typically
    // ERROR_INVALID_PARAMETER — means there is no such process.
    return GetLastError() == ERROR_ACCESS_DENIED;
  }
  DWORD exit_code = 0;
  BOOL alive = TRUE;
  if (GetExitCodeProcess(h, &exit_code) && exit_code != STILL_ACTIVE)
    alive = FALSE;
  CloseHandle(h);
  return alive;
}

static BOOL miniav_audio_info_to_wfex(const MiniAVAudioInfo *in,
                                      WAVEFORMATEX *out) {
  WORD tag, bits;
  if (!in || in->sample_rate == 0 || in->channels == 0)
    return FALSE;
  switch (in->format) {
  case MINIAV_AUDIO_FORMAT_U8:
    tag = WAVE_FORMAT_PCM;
    bits = 8;
    break;
  case MINIAV_AUDIO_FORMAT_S16:
    tag = WAVE_FORMAT_PCM;
    bits = 16;
    break;
  case MINIAV_AUDIO_FORMAT_S32:
    tag = WAVE_FORMAT_PCM;
    bits = 32;
    break;
  case MINIAV_AUDIO_FORMAT_F32:
    tag = WAVE_FORMAT_IEEE_FLOAT;
    bits = 32;
    break;
  default:
    return FALSE; // F64 / UNKNOWN: WASAPI has no such shared-mode format
  }
  memset(out, 0, sizeof(WAVEFORMATEX));
  out->wFormatTag = tag;
  out->nChannels = (WORD)in->channels;
  out->nSamplesPerSec = in->sample_rate;
  out->wBitsPerSample = bits;
  out->nBlockAlign = (WORD)((out->nChannels * bits) / 8);
  out->nAvgBytesPerSec = out->nSamplesPerSec * out->nBlockAlign;
  out->cbSize = 0;
  return TRUE;
}

// One activation attempt. On success the returned client is INITIALIZED for
// `fmt` with the event handle attached.
static HRESULT wasapi_activate_process_loopback(DWORD pid, HANDLE buffer_event,
                                                const WAVEFORMATEX *fmt,
                                                IAudioClient **client_out) {
  IActivateAudioInterfaceAsyncOperation *async_op = NULL;
  IUnknown *activated = NULL;
  IAudioClient *client = NULL;
  HRESULT hr_activate = E_FAIL;
  HRESULT hr;

  WasapiActivateHandler *handler = (WasapiActivateHandler *)miniav_calloc(
      1, sizeof(WasapiActivateHandler));
  if (!handler)
    return E_OUTOFMEMORY;
  handler->lpVtbl = &g_wasapi_activate_handler_vtbl;
  handler->ref_count = 1;
  handler->completed_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!handler->completed_event) {
    miniav_free(handler);
    return HRESULT_FROM_WIN32(GetLastError());
  }
  // TRAP 1: without this (plus IAgileObject in QueryInterface) the activation
  // below fails with E_ILLEGAL_METHOD_CALL and never reaches the audio stack.
  CoCreateFreeThreadedMarshaler((IUnknown *)handler, &handler->ftm);

  AUDIOCLIENT_ACTIVATION_PARAMS params;
  memset(&params, 0, sizeof(params));
  params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
  MINIAV_PROC_LOOPBACK_PARAMS(params).TargetProcessId = pid;
  MINIAV_PROC_LOOPBACK_PARAMS(params).ProcessLoopbackMode =
      PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

  PROPVARIANT activation_prop;
  PropVariantInit(&activation_prop);
  activation_prop.vt = VT_BLOB;
  activation_prop.blob.cbSize = sizeof(params);
  activation_prop.blob.pBlobData = (BYTE *)&params;

  hr = ActivateAudioInterfaceAsync(
      VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, &IID_IAudioClient,
      &activation_prop, (IActivateAudioInterfaceCompletionHandler *)handler,
      &async_op);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: ActivateAudioInterfaceAsync failed: 0x%lx", hr);
    goto done;
  }

  if (WaitForSingleObject(handler->completed_event, 5000) != WAIT_OBJECT_0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: process-loopback activation did not complete "
               "within 5s.");
    hr = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
    goto done;
  }

  hr = async_op->lpVtbl->GetActivateResult(async_op, &hr_activate, &activated);
  if (SUCCEEDED(hr) && FAILED(hr_activate))
    hr = hr_activate;
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: process-loopback activation for PID %lu failed: "
               "0x%lx",
               pid, hr);
    goto done;
  }

  hr = activated->lpVtbl->QueryInterface(activated, &IID_IAudioClient,
                                         (void **)&client);
  if (FAILED(hr))
    goto done;

  // hnsBufferDuration 0 = the engine's default period (measured ~10 ms here);
  // 20 ms and 200 ms behaved identically. hnsPeriodicity MUST be 0 in shared
  // mode. Event-driven: the event fires ~100x/s, confirmed by measurement, so
  // the shared capture thread never has to fall back on its safety timeout.
  hr = client->lpVtbl->Initialize(
      client, AUDCLNT_SHAREMODE_SHARED,
      AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK, 0, 0,
      fmt, NULL);
  if (FAILED(hr))
    goto done;

  hr = client->lpVtbl->SetEventHandle(client, buffer_event);
  if (FAILED(hr))
    goto done;

  *client_out = client;
  client = NULL;

done:
  if (client)
    client->lpVtbl->Release(client);
  if (activated)
    activated->lpVtbl->Release(activated);
  if (async_op)
    async_op->lpVtbl->Release(async_op);
  handler->lpVtbl->Release(
      (IActivateAudioInterfaceCompletionHandler *)handler);
  return hr;
}

// Configure real per-process loopback. On success platform_ctx owns an
// initialized audio_client and a capture_format describing exactly what it
// will deliver.
static MiniAVResultCode wasapi_configure_process_loopback(
    LoopbackPlatformContextWinWasapi *platform_ctx, DWORD pid,
    const MiniAVAudioInfo *requested_format,
    const WAVEFORMATEX *endpoint_mix_format) {
  if (!wasapi_process_is_alive(pid)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: per-process loopback requested for PID %lu, which "
               "is not running. Refusing: activation would have succeeded and "
               "then delivered silence forever.",
               pid);
    return MINIAV_ERROR_DEVICE_NOT_FOUND;
  }

  // Candidates, in order of preference. Process loopback really does convert,
  // so the caller's request is tried FIRST and normally wins.
  WAVEFORMATEX candidates[3];
  const char *why[3];
  int n = 0;
  if (requested_format &&
      miniav_audio_info_to_wfex(requested_format, &candidates[n])) {
    why[n] = "requested";
    ++n;
  }
  if (endpoint_mix_format) {
    MiniAVAudioInfo as_info;
    waveformat_to_miniav_audio_format(endpoint_mix_format, &as_info);
    if (miniav_audio_info_to_wfex(&as_info, &candidates[n])) {
      why[n] = "endpoint mix";
      ++n;
    }
  }
  {
    MiniAVAudioInfo fallback;
    memset(&fallback, 0, sizeof(fallback));
    fallback.format = MINIAV_AUDIO_FORMAT_F32;
    fallback.channels = 2;
    fallback.sample_rate = 48000;
    miniav_audio_info_to_wfex(&fallback, &candidates[n]);
    why[n] = "48kHz/2ch/F32 default";
    ++n;
  }

  HRESULT last_hr = E_FAIL;
  for (int i = 0; i < n; ++i) {
    IAudioClient *client = NULL;
    HRESULT hr = wasapi_activate_process_loopback(
        pid, platform_ctx->buffer_event_handle, &candidates[i], &client);
    if (SUCCEEDED(hr) && client) {
      platform_ctx->capture_format =
          (WAVEFORMATEX *)CoTaskMemAlloc(sizeof(WAVEFORMATEX));
      if (!platform_ctx->capture_format) {
        client->lpVtbl->Release(client);
        return MINIAV_ERROR_OUT_OF_MEMORY;
      }
      memcpy(platform_ctx->capture_format, &candidates[i],
             sizeof(WAVEFORMATEX));
      platform_ctx->audio_client = client;
      platform_ctx->event_driven_capture = TRUE;
      platform_ctx->process_loopback_active = TRUE;
      miniav_log(MINIAV_LOG_LEVEL_INFO,
                 "WASAPI Cfg: per-process loopback ACTIVE for PID %lu "
                 "(include process tree) at %lu Hz / %u ch / %u-bit %s [%s].",
                 pid, candidates[i].nSamplesPerSec, candidates[i].nChannels,
                 candidates[i].wBitsPerSample,
                 candidates[i].wFormatTag == WAVE_FORMAT_IEEE_FLOAT ? "float"
                                                                   : "PCM",
                 why[i]);
      return MINIAV_SUCCESS;
    }
    last_hr = hr;
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WASAPI Cfg: process loopback for PID %lu rejected the %s "
               "format (%lu Hz / %u ch / %u-bit): 0x%lx",
               pid, why[i], candidates[i].nSamplesPerSec,
               candidates[i].nChannels, candidates[i].wBitsPerSample, hr);
  }

  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "WASAPI Cfg: per-process loopback for PID %lu unavailable (last "
             "HRESULT 0x%lx). This API needs Windows 10 build 20348 / Windows "
             "11.",
             pid, last_hr);
  return hresult_to_miniavresult(last_hr);
}

MiniAVResultCode wasapi_configure_loopback(
    MiniAVLoopbackContext *ctx,
    const MiniAVLoopbackTargetInfo *target_info, // Primary identifier
    const char *target_device_id_utf8, // Used if target_info is NULL or type
                                       // is SYSTEM_AUDIO for specific device
    const MiniAVAudioInfo
        *requested_format) { // requested_format is for reference, WASAPI uses
                             // mix format
  LoopbackPlatformContextWinWasapi *platform_ctx =
      (LoopbackPlatformContextWinWasapi *)ctx->platform_ctx;
  HRESULT hr;
  MiniAVResultCode mres = MINIAV_SUCCESS;
  IAudioClient *temp_audio_client = NULL;
  IMMDevice *target_imm_device = NULL;
  BOOL process_scope_active = FALSE;

  // For WHOLE-ENDPOINT loopback requested_format is a HINT only: the stream
  // always runs at the endpoint mix format, so it is used only to carry
  // num_frames through and to log loudly when the caller asked for something
  // else. For PER-PROCESS loopback it is a real request — that path has no
  // inherited format and normally honours it verbatim.

  // --- Cleanup existing resources if re-configuring ---
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
  // Keep device_enumerator if already created by init, or create if needed
  if (!platform_ctx->device_enumerator) {
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
  }

  platform_ctx->attempt_process_specific_capture = FALSE;
  platform_ctx->process_loopback_active = FALSE;
  platform_ctx->target_process_id = 0;
  DWORD actual_target_pid_for_init = 0;

  // The scope the backend ACTUALLY achieves, reported by
  // MiniAV_Loopback_GetActiveTargetInfo. Written here, never by the caller's
  // request, so "I asked for a process" and "I am getting a process" cannot be
  // confused. NONE until one of the branches below succeeds.
  memset(&ctx->active_target_info, 0, sizeof(ctx->active_target_info));
  ctx->active_target_info.type = MINIAV_LOOPBACK_TARGET_NONE;

  // --- Determine target IMMDevice and PID for process-specific capture ---
  if (target_info != NULL) {
    if (target_info->type == MINIAV_LOOPBACK_TARGET_PROCESS) {
      actual_target_pid_for_init = target_info->TARGETHANDLE.process_id;
      platform_ctx->attempt_process_specific_capture = TRUE;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Cfg: Target type PROCESS, PID: %lu",
                 actual_target_pid_for_init);
      // For process-specific, loopback is on the default render device,
      // filtered by PID
      hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
          platform_ctx->device_enumerator, eRender, eConsole,
          &target_imm_device);
    } else if (target_info->type == MINIAV_LOOPBACK_TARGET_WINDOW) {
      HWND hwnd = (HWND)target_info->TARGETHANDLE.window_handle;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Cfg: Target type WINDOW, HWND: %p", hwnd);
      if (hwnd != NULL &&
          GetWindowThreadProcessId(hwnd, &actual_target_pid_for_init) &&
          actual_target_pid_for_init != 0) {
        platform_ctx->attempt_process_specific_capture = TRUE;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI Cfg: Resolved HWND to PID: %lu",
                   actual_target_pid_for_init);
      } else {
        // Same honesty rule as the PID path below: a window target that cannot
        // be resolved to a process must not quietly become "the whole system".
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI Cfg: HWND %p does not resolve to a process — "
                   "refusing rather than capturing whole-system audio under a "
                   "window-scoped request.",
                   hwnd);
        mres = MINIAV_ERROR_INVALID_ARG;
        goto config_cleanup;
      }
      // For window (process-specific), loopback is on the default render
      // device, filtered by PID
      hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
          platform_ctx->device_enumerator, eRender, eConsole,
          &target_imm_device);
    } else if (target_info->type == MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO ||
               target_info->type == MINIAV_LOOPBACK_TARGET_NONE) {
      if (target_device_id_utf8 && strlen(target_device_id_utf8) > 0) {
        LPWSTR device_id_wstr = utf8_to_lpwstr(target_device_id_utf8);
        if (!device_id_wstr) {
          mres = MINIAV_ERROR_OUT_OF_MEMORY;
          goto config_cleanup;
        }
        hr = platform_ctx->device_enumerator->lpVtbl->GetDevice(
            platform_ctx->device_enumerator, device_id_wstr,
            &target_imm_device);
        miniav_free(device_id_wstr);
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI Cfg: Target type SYSTEM_AUDIO with specific "
                   "device ID: %s",
                   target_device_id_utf8);
      } else {
        hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
            platform_ctx->device_enumerator, eRender, eConsole,
            &target_imm_device);
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI Cfg: Target type SYSTEM_AUDIO (default device)");
      }
    } else { // Should not happen if public API validates type
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Cfg: Invalid target_info->type: %d",
                 target_info->type);
      mres = MINIAV_ERROR_INVALID_ARG;
      goto config_cleanup;
    }
  } else { // target_info is NULL, rely on target_device_id_utf8 or default
    if (target_device_id_utf8 && strlen(target_device_id_utf8) > 0) {
      LPWSTR device_id_wstr = utf8_to_lpwstr(target_device_id_utf8);
      if (!device_id_wstr) {
        mres = MINIAV_ERROR_OUT_OF_MEMORY;
        goto config_cleanup;
      }
      hr = platform_ctx->device_enumerator->lpVtbl->GetDevice(
          platform_ctx->device_enumerator, device_id_wstr, &target_imm_device);
      miniav_free(device_id_wstr);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Cfg: target_info NULL, using specific device ID: %s",
                 target_device_id_utf8);
    } else {
      hr = platform_ctx->device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
          platform_ctx->device_enumerator, eRender, eConsole,
          &target_imm_device);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WASAPI Cfg: target_info NULL, using default render device.");
    }
  }

  if (FAILED(hr) || !target_imm_device) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to get target IMMDevice: 0x%lx", hr);
    mres = hresult_to_miniavresult(hr);
    goto config_cleanup;
  }
  platform_ctx->audio_device =
      target_imm_device; // Store it, it's now owned by platform_ctx

  // --- Activate IAudioClient from the chosen IMMDevice ---
  hr = platform_ctx->audio_device->lpVtbl->Activate(
      platform_ctx->audio_device, &IID_IAudioClient, CLSCTX_ALL, NULL,
      (void **)&temp_audio_client);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: Failed to activate IAudioClient: 0x%lx", hr);
    mres = hresult_to_miniavresult(hr);
    goto config_cleanup;
  }

  DWORD stream_flags = AUDCLNT_STREAMFLAGS_LOOPBACK;

  // --- Per-process scope: ActivateAudioInterfaceAsync (see the block comment
  // above wasapi_configure_process_loopback) ---
  if (platform_ctx->attempt_process_specific_capture &&
      actual_target_pid_for_init != 0) {
    platform_ctx->target_process_id = actual_target_pid_for_init;

    // Process loopback has no mix format of its own (TRAP 2), but the endpoint
    // mix format is a good second-choice candidate, so read it while we still
    // hold an endpoint client.
    WAVEFORMATEX *endpoint_mix = NULL;
    if (FAILED(temp_audio_client->lpVtbl->GetMixFormat(temp_audio_client,
                                                       &endpoint_mix))) {
      endpoint_mix = NULL;
    }

    MiniAVResultCode pres;
    if (wasapi_stress_no_process_loopback()) {
      pres = MINIAV_ERROR_NOT_SUPPORTED;
    } else {
      pres = wasapi_configure_process_loopback(
          platform_ctx, actual_target_pid_for_init, requested_format,
          endpoint_mix);
    }
    if (endpoint_mix)
      CoTaskMemFree(endpoint_mix);

    if (pres == MINIAV_SUCCESS) {
      process_scope_active = TRUE;
      temp_audio_client->lpVtbl->Release(temp_audio_client);
      temp_audio_client = NULL;
      ctx->active_target_info.type = MINIAV_LOOPBACK_TARGET_PROCESS;
      ctx->active_target_info.TARGETHANDLE.process_id =
          (uint32_t)actual_target_pid_for_init;
    } else if (!wasapi_allow_system_fallback()) {
      // DEGRADE HONESTLY. The old code silently substituted whole-system
      // audio here. A caller cannot tell one process's PCM from the whole
      // machine's by looking at it, so the substitution was undetectable —
      // and every per-process caller had been receiving it since the feature
      // was written. Failing is the only answer that cannot be mistaken for
      // success. Set MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1 to opt back in.
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Cfg: per-process loopback for PID %lu could not be "
                 "established — FAILING the configure rather than silently "
                 "substituting whole-system audio. Set "
                 "MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1 to accept the "
                 "substitution (it is then reported by "
                 "MiniAV_Loopback_GetActiveTargetInfo).",
                 actual_target_pid_for_init);
      mres = pres;
      goto config_cleanup_after_temp_client;
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Cfg: per-process loopback for PID %lu unavailable and "
                 "MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1 — capturing THE "
                 "WHOLE SYSTEM instead. The delivered audio is NOT scoped to "
                 "that process; MiniAV_Loopback_GetActiveTargetInfo reports "
                 "SYSTEM_AUDIO.",
                 actual_target_pid_for_init);
      platform_ctx->attempt_process_specific_capture = FALSE;
    }
  }

  if (!process_scope_active) {
    // Standard whole-endpoint loopback: the common, VERIFIED path. Unchanged.
    platform_ctx->audio_client = temp_audio_client;
    temp_audio_client = NULL;
    ctx->active_target_info.type = MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO;
    ctx->active_target_info.TARGETHANDLE.process_id = 0;
  }

  // --- Common Initialization (if not done by IAudioClient3 or if fallback)
  // ---
  if (!platform_ctx
           ->capture_format) { // If format wasn't set by IAudioClient3 path
    hr = platform_ctx->audio_client->lpVtbl->GetMixFormat(
        platform_ctx->audio_client, &platform_ctx->mix_format);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Cfg: GetMixFormat (standard path) failed: 0x%lx", hr);
      mres = hresult_to_miniavresult(hr);
      goto config_cleanup;
    }
    platform_ctx->capture_format = (WAVEFORMATEX *)CoTaskMemAlloc(
        sizeof(WAVEFORMATEX) + platform_ctx->mix_format->cbSize);
    if (!platform_ctx->capture_format) {
      mres = MINIAV_ERROR_OUT_OF_MEMORY;
      goto config_cleanup;
    }
    memcpy(platform_ctx->capture_format, platform_ctx->mix_format,
           sizeof(WAVEFORMATEX) + platform_ctx->mix_format->cbSize);

    // Log the actual WASAPI mix format to avoid decode mismatches.
    if (platform_ctx->mix_format->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      const WAVEFORMATEXTENSIBLE *ext = (const WAVEFORMATEXTENSIBLE *)platform_ctx->mix_format;
      miniav_log(MINIAV_LOG_LEVEL_INFO,
        "WASAPI Cfg: MixFormat: EXTENSIBLE, %u ch, %lu Hz, wBits=%u, validBits=%u, "
        "float=%s, nBlockAlign=%u, nAvgBps=%lu, cbSize=%u, chMask=0x%08lx",
        platform_ctx->mix_format->nChannels,
        platform_ctx->mix_format->nSamplesPerSec,
        platform_ctx->mix_format->wBitsPerSample,
        ext->Samples.wValidBitsPerSample,
        IsEqualGUID(&ext->SubFormat, &KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) ? "yes" : "no",
        platform_ctx->mix_format->nBlockAlign,
        platform_ctx->mix_format->nAvgBytesPerSec,
        platform_ctx->mix_format->cbSize,
        ext->dwChannelMask);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_INFO,
        "WASAPI Cfg: MixFormat: tag=%u, %u ch, %lu Hz, wBits=%u, nBlockAlign=%u, nAvgBps=%lu",
        platform_ctx->mix_format->wFormatTag,
        platform_ctx->mix_format->nChannels,
        platform_ctx->mix_format->nSamplesPerSec,
        platform_ctx->mix_format->wBitsPerSample,
        platform_ctx->mix_format->nBlockAlign,
        platform_ctx->mix_format->nAvgBytesPerSec);
    }
  }

  // Initialize the endpoint IAudioClient. The per-process path already has an
  // initialized client (Initialize happens inside the activation helper), so
  // this whole block is skipped there.
  if (!process_scope_active && platform_ctx->audio_client) {
    REFERENCE_TIME hns_requested_duration = 0;

    // Try event-driven mode first (LOOPBACK | EVENTCALLBACK)
    DWORD event_flags = stream_flags | AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
    hr = platform_ctx->audio_client->lpVtbl->Initialize(
        platform_ctx->audio_client, AUDCLNT_SHAREMODE_SHARED, event_flags,
        hns_requested_duration, 0, platform_ctx->capture_format, NULL);

    if (SUCCEEDED(hr)) {
      hr = platform_ctx->audio_client->lpVtbl->SetEventHandle(
          platform_ctx->audio_client, platform_ctx->buffer_event_handle);
      if (SUCCEEDED(hr)) {
        platform_ctx->event_driven_capture = TRUE;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI Cfg: Event-driven capture mode enabled.");
      } else {
        // SetEventHandle failed — must re-create client for polling fallback
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WASAPI Cfg: SetEventHandle failed: 0x%lx. "
                   "Re-creating client for polling mode.",
                   hr);
        platform_ctx->audio_client->lpVtbl->Release(
            platform_ctx->audio_client);
        platform_ctx->audio_client = NULL;
        hr = platform_ctx->audio_device->lpVtbl->Activate(
            platform_ctx->audio_device, &IID_IAudioClient, CLSCTX_ALL, NULL,
            (void **)&platform_ctx->audio_client);
        if (FAILED(hr)) {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WASAPI Cfg: Re-Activate IAudioClient failed: 0x%lx",
                     hr);
          mres = hresult_to_miniavresult(hr);
          goto config_cleanup;
        }
        hr = platform_ctx->audio_client->lpVtbl->Initialize(
            platform_ctx->audio_client, AUDCLNT_SHAREMODE_SHARED, stream_flags,
            hns_requested_duration, 0, platform_ctx->capture_format, NULL);
        if (FAILED(hr)) {
          miniav_log(
              MINIAV_LOG_LEVEL_ERROR,
              "WASAPI Cfg: Polling-mode Initialize failed: 0x%lx", hr);
          mres = hresult_to_miniavresult(hr);
          goto config_cleanup;
        }
        platform_ctx->event_driven_capture = FALSE;
      }
    } else {
      // Event-driven Initialize failed — fall back to polling.
      // IAudioClient::Initialize can only be called once, so re-activate.
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WASAPI Cfg: Event-driven Initialize failed: 0x%lx. "
                 "Falling back to polling.",
                 hr);
      platform_ctx->audio_client->lpVtbl->Release(platform_ctx->audio_client);
      platform_ctx->audio_client = NULL;
      hr = platform_ctx->audio_device->lpVtbl->Activate(
          platform_ctx->audio_device, &IID_IAudioClient, CLSCTX_ALL, NULL,
          (void **)&platform_ctx->audio_client);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI Cfg: Re-Activate IAudioClient failed: 0x%lx", hr);
        mres = hresult_to_miniavresult(hr);
        goto config_cleanup;
      }
      hr = platform_ctx->audio_client->lpVtbl->Initialize(
          platform_ctx->audio_client, AUDCLNT_SHAREMODE_SHARED, stream_flags,
          hns_requested_duration, 0, platform_ctx->capture_format, NULL);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WASAPI Cfg: IAudioClient::Initialize failed: 0x%lx", hr);
        if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WASAPI Cfg: Format not supported by endpoint.");
        }
        mres = hresult_to_miniavresult(hr);
        goto config_cleanup;
      }
      platform_ctx->event_driven_capture = FALSE;
    }
  }

  // Publish the format WASAPI actually negotiated. Endpoint (whole-system)
  // loopback has no format negotiation at all: the stream always runs at the
  // endpoint mix format, so `requested_format` is at best a hint there.
  // Per-process loopback DOES convert, so the request is usually honoured
  // verbatim — either way this field is read from the WAVEFORMATEX the stream
  // was actually initialized with. Everything downstream —
  // MiniAV_Loopback_GetConfiguredFormat and the `info` stamped on every
  // delivered PCM buffer (see wasapi_capture_thread_proc) — reads this field,
  // so it MUST describe the bytes we are about to hand out.
  waveformat_to_miniav_audio_format(platform_ctx->capture_format,
                                    &ctx->configured_video_format);
  // num_frames is a caller-side chunk hint, not something WASAPI negotiates,
  // and the conversion above zeroes it. Carry the request through so
  // GetConfiguredFormat still answers with a usable value; per-buffer
  // info.num_frames is overwritten with the real delivered count anyway.
  if (requested_format) {
    ctx->configured_video_format.num_frames = requested_format->num_frames;
    if (ctx->configured_video_format.sample_rate !=
            requested_format->sample_rate ||
        ctx->configured_video_format.channels != requested_format->channels ||
        ctx->configured_video_format.format != requested_format->format) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WASAPI Cfg: requested %uHz/%uch/fmt%d but the stream runs at "
                 "%uHz/%uch/fmt%d. That is what will be delivered and "
                 "reported.",
                 requested_format->sample_rate, requested_format->channels,
                 (int)requested_format->format,
                 ctx->configured_video_format.sample_rate,
                 ctx->configured_video_format.channels,
                 (int)ctx->configured_video_format.format);
    }
  }

  hr = platform_ctx->audio_client->lpVtbl->GetBufferSize(
      platform_ctx->audio_client, &platform_ctx->buffer_frame_count);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: GetBufferSize failed: 0x%lx", hr);
    mres = hresult_to_miniavresult(hr);
    goto config_cleanup;
  }

  hr = platform_ctx->audio_client->lpVtbl->GetService(
      platform_ctx->audio_client, &IID_IAudioCaptureClient,
      (void **)&platform_ctx->capture_client);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI Cfg: GetService for IAudioCaptureClient failed: 0x%lx",
               hr);
    mres = hresult_to_miniavresult(hr);
    goto config_cleanup;
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "WASAPI Cfg: Loopback configured. Buffer frames: %u. Scope: %s",
             platform_ctx->buffer_frame_count,
             platform_ctx->process_loopback_active
                 ? "PER-PROCESS (real, ActivateAudioInterfaceAsync)"
                 : "WHOLE SYSTEM");
  if (platform_ctx->process_loopback_active) {
    miniav_log(MINIAV_LOG_LEVEL_INFO, "WASAPI Cfg:   target PID: %lu",
               platform_ctx->target_process_id);
  }
  ctx->is_configured = true;
  mres = MINIAV_SUCCESS;

config_cleanup_after_temp_client:
  if (temp_audio_client) { // Only release if it wasn't assigned to
                           // platform_ctx->audio_client or superseded
    temp_audio_client->lpVtbl->Release(temp_audio_client);
  }
config_cleanup:
  // platform_ctx->audio_device is released by wasapi_destroy_platform or if
  // it's replaced. platform_ctx->device_enumerator is kept.
  // platform_ctx->audio_client and capture_client are released by destroy or
  // if replaced.
  if (mres != MINIAV_SUCCESS) {
    // Minimal cleanup here, full cleanup in destroy_platform
    if (platform_ctx->capture_client) {
      platform_ctx->capture_client->lpVtbl->Release(
          platform_ctx->capture_client);
      platform_ctx->capture_client = NULL;
    }
    if (platform_ctx->audio_client) {
      platform_ctx->audio_client->lpVtbl->Release(platform_ctx->audio_client);
      platform_ctx->audio_client = NULL;
    }
    // audio_device is tricky, it's owned by platform_ctx now. If config fails
    // early, it might not be set. If it was set and then config failed,
    // destroy_platform will get it.
    if (platform_ctx->capture_format) {
      CoTaskMemFree(platform_ctx->capture_format);
      platform_ctx->capture_format = NULL;
    }
    if (platform_ctx->mix_format) {
      CoTaskMemFree(platform_ctx->mix_format);
      platform_ctx->mix_format = NULL;
    }
    ctx->is_configured = false;
  }
  return mres;
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
    // Bounded join: an INFINITE wait here could hang StopCapture forever if
    // the capture thread is wedged inside a WASAPI call. On timeout, leave
    // the handle set (a later Stop/Destroy retries) and do NOT stop the
    // audio client out from under the still-running thread.
    if (WaitForSingleObject(platform_ctx->capture_thread_handle, 5000) !=
        WAIT_OBJECT_0) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI Stop: capture thread did not exit within 5s — "
                 "deferring (a later Stop/Destroy will retry).");
      return MINIAV_ERROR_TIMEOUT;
    }
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

static MiniAVResultCode
wasapi_get_default_format_platform(const char *target_device_id_utf8,
                                   MiniAVAudioInfo *format_out) {
  if (!format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  memset(format_out, 0, sizeof(MiniAVAudioInfo));

  HRESULT hr;
  MiniAVResultCode mres = MINIAV_SUCCESS;
  IMMDeviceEnumerator *device_enumerator = NULL;
  IMMDevice *audio_device = NULL;
  IAudioClient *audio_client = NULL;
  WAVEFORMATEX *mix_format = NULL;
  BOOL com_initialized_here = FALSE;

  if (!miniav_com_legacy_percall()) {
    miniav_com_ensure_mta();
    miniav_com_trace("wasapi_get_default_format", 0);
  } else {
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    miniav_com_trace("legacy CoInitializeEx/wasapi_get_default_format",
                     (unsigned long)hr);
    if (SUCCEEDED(hr)) {
      com_initialized_here = TRUE;
      if (hr == S_FALSE) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WASAPI GetDefaultFormat: COM already initialized.");
        com_initialized_here = FALSE; // Already initialized by someone else
      }
    } else if (hr != RPC_E_CHANGED_MODE) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI GetDefaultFormat: CoInitializeEx failed: 0x%lx", hr);
      return hresult_to_miniavresult(hr);
    }
  }

  hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                        &IID_IMMDeviceEnumerator, (void **)&device_enumerator);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI GetDefaultFormat: CoCreateInstance for "
               "MMDeviceEnumerator failed: 0x%lx",
               hr);
    mres = hresult_to_miniavresult(hr);
    goto cleanup;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI GetDefaultFormat: MMDeviceEnumerator created.");

  if (target_device_id_utf8 && strlen(target_device_id_utf8) > 0) {
    LPWSTR device_id_wstr = utf8_to_lpwstr(target_device_id_utf8);
    if (!device_id_wstr) {
      mres = MINIAV_ERROR_OUT_OF_MEMORY;
      goto cleanup;
    }
    hr = device_enumerator->lpVtbl->GetDevice(device_enumerator, device_id_wstr,
                                              &audio_device);
    miniav_free(device_id_wstr);
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WASAPI GetDefaultFormat: GetDevice for '%s' failed: 0x%lx",
                 target_device_id_utf8, hr);
      mres = hresult_to_miniavresult(hr);
      goto cleanup;
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI GetDefaultFormat: Using specific device ID: %s. "
               "IMMDevice obtained.",
               target_device_id_utf8);
  } else {
    hr = device_enumerator->lpVtbl->GetDefaultAudioEndpoint(
        device_enumerator, eRender, eConsole, &audio_device);
    if (FAILED(hr)) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "WASAPI GetDefaultFormat: GetDefaultAudioEndpoint failed: 0x%lx", hr);
      mres = hresult_to_miniavresult(hr);
      goto cleanup;
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WASAPI GetDefaultFormat: Using default "
                                       "render device. IMMDevice obtained.");
  }

  hr = audio_device->lpVtbl->Activate(audio_device, &IID_IAudioClient,
                                      CLSCTX_ALL, NULL, (void **)&audio_client);
  if (FAILED(hr)) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "WASAPI GetDefaultFormat: Failed to activate IAudioClient: 0x%lx", hr);
    mres = hresult_to_miniavresult(hr);
    goto cleanup;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI GetDefaultFormat: IAudioClient activated.");

  hr = audio_client->lpVtbl->GetMixFormat(audio_client, &mix_format);
  if (FAILED(hr) || !mix_format) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WASAPI GetDefaultFormat: GetMixFormat failed: 0x%lx", hr);
    mres = hresult_to_miniavresult(
        hr); // This is a likely place for AUDCLNT_E_UNSUPPORTED_FORMAT
    goto cleanup;
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WASAPI GetDefaultFormat: GetMixFormat succeeded.");

  waveformat_to_miniav_audio_format(mix_format, format_out);
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "WASAPI GetDefaultFormat: Default format: %d channels, %lu Hz, "
             "format_tag %u (MiniAV format %d)",
             format_out->channels, format_out->sample_rate,
             mix_format->wFormatTag, format_out->format);

cleanup:
  if (mix_format)
    CoTaskMemFree(mix_format);
  if (audio_client)
    audio_client->lpVtbl->Release(audio_client);
  if (audio_device)
    audio_device->lpVtbl->Release(audio_device);
  if (device_enumerator)
    device_enumerator->lpVtbl->Release(device_enumerator);
  if (com_initialized_here) {
    CoUninitialize();
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WASAPI GetDefaultFormat: COM uninitialized.");
  }
  return mres;
}

MiniAVResultCode wasapi_get_configured_video_format(MiniAVLoopbackContext *ctx,
                                              MiniAVAudioInfo *format_out) {
  if (!ctx->is_configured || !ctx->platform_ctx) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  *format_out = ctx->configured_video_format;
  return MINIAV_SUCCESS;
}

// --- Ops Table ---
const LoopbackContextInternalOps g_loopback_ops_wasapi = {
    .init_platform = wasapi_init_platform,
    .destroy_platform = wasapi_destroy_platform,
    .enumerate_targets_platform = waspi_enumerate_targets,
    .get_default_format_platform = wasapi_get_default_format_platform,
    .configure_loopback = wasapi_configure_loopback,
    .start_capture = wasapi_start_capture,
    .stop_capture = wasapi_stop_capture,
    .release_buffer_platform = wasapi_release_buffer_platform,
    .get_configured_video_format = wasapi_get_configured_video_format};

MiniAVResultCode miniav_loopback_context_platform_init_windows_wasapi(
    MiniAVLoopbackContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;
  ctx->ops = &g_loopback_ops_wasapi;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "DXGI: Assigned Windows DXGI screen ops.");
  // The caller (e.g., MiniAV_Screen_CreateContext) will call
  // ctx->ops->init_platform()
  return MINIAV_SUCCESS;
}

#endif // _WIN32
