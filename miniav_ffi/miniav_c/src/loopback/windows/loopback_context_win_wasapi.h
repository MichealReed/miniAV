#ifndef MINIAV_LOOPBACK_CONTEXT_WIN_WASAPI_H
#define MINIAV_LOOPBACK_CONTEXT_WIN_WASAPI_H

#include "../loopback_context.h" // For MiniAVLoopbackContext, LoopbackContextInternalOps, etc.

#ifdef _WIN32

// Windows and WASAPI headers
#include <audioclient.h> // For IAudioClient, IAudioCaptureClient
#include <functiondiscoverykeys_devpkey.h> // For PKEY_Device_FriendlyName etc.
#include <mmdeviceapi.h>                   // For IMMDeviceEnumerator, IMMDevice
#include <windows.h>

// Forward declaration from loopback_api.c (or a common internal header if
// preferred) This is to avoid circular dependencies if loopback_api.c includes
// this for the ops getter. Alternatively, the ops getter could be in a more
// central place or its declaration moved. For now, assume it's okay to declare
// it here as it's tightly coupled.
extern const LoopbackContextInternalOps *miniav_loopback_get_win_ops(void);
extern MiniAVResultCode miniav_loopback_enumerate_targets_win(
    MiniAVLoopbackTargetType target_type_filter, MiniAVDeviceInfo **targets,
    uint32_t *count);

// --- WASAPI Platform-Specific Context ---
typedef struct LoopbackPlatformContextWinWasapi {
  MiniAVLoopbackContext *parent_ctx;
  IMMDeviceEnumerator *device_enumerator;
  IMMDevice *audio_device;
  IAudioClient *audio_client; // Could be IAudioClient or IAudioClient3
  IAudioCaptureClient *capture_client;
  WAVEFORMATEX *capture_format; // Actual format used by WASAPI
  WAVEFORMATEX *mix_format;     // Device's mix format
  UINT32 buffer_frame_count;
  HANDLE capture_thread_handle;
  HANDLE stop_event_handle;
  BOOL attempt_process_specific_capture;
  DWORD target_process_id;     // For logging/debugging if process-specific
  LARGE_INTEGER qpc_frequency;
} LoopbackPlatformContextWinWasapi;

// --- WASAPI Platform-Specific Function Declarations ---
// These functions will implement the LoopbackContextInternalOps

MiniAVResultCode wasapi_init_platform(MiniAVLoopbackContext *ctx);
MiniAVResultCode wasapi_destroy_platform(MiniAVLoopbackContext *ctx);

// Note: wasapi_enumerate_targets_platform is effectively
// miniav_loopback_enumerate_targets_win which is called directly by the API
// layer, not through the ops table of an existing context.

MiniAVResultCode wasapi_configure_loopback(
    MiniAVLoopbackContext *ctx, const MiniAVLoopbackTargetInfo *target_info,
    const char *target_device_id, const MiniAVAudioInfo *requested_format);

MiniAVResultCode wasapi_start_capture(MiniAVLoopbackContext *ctx,
                                      MiniAVBufferCallback callback,
                                      void *user_data);
MiniAVResultCode wasapi_stop_capture(MiniAVLoopbackContext *ctx);
MiniAVResultCode
wasapi_release_buffer_platform(MiniAVLoopbackContext *ctx,
                               void *native_buffer_payload_resource_ptr);
MiniAVResultCode wasapi_get_configured_format(MiniAVLoopbackContext *ctx,
                                              MiniAVAudioInfo *format_out);

#endif // _WIN32

#endif // MINIAV_LOOPBACK_CONTEXT_WIN_WASAPI_H
