// ABI size probe.
//
// Every struct here is allocated on ONE side of the FFI boundary and read or
// copied on the other. A binding generator that has not been re-run since a
// field was appended produces a Dart struct that is SMALLER than the C one;
// `calloc<T>()` then under-allocates and the first `*dst = *src;` in C reads
// past the end of the allocation. That is exactly how MiniAVInputConfig's
// motion fields (appended in 0.7.x) turned into a garbage function pointer in
// MiniAVInputContext::config.
//
// "ABI-additive" only ever meant OFFSETS are stable. sizeof() is NOT, and
// sizeof() is what calloc and struct assignment use.
//
// Dart asserts sizeOf<T>() == MiniAV_ABI_StructSize("T") for every name below
// (test/abi_struct_size_test.dart). Add a struct here the moment it starts
// crossing the boundary; unknown names return 0 so a typo fails loudly.

#include "../include/miniav_buffer.h"
#include "../include/miniav_capture.h"
#include "../include/miniav_types.h"

#include <stddef.h>
#include <string.h>

typedef struct {
  const char *name;
  uint32_t size;
} MiniAVAbiEntry;

#define MINIAV_ABI_ENTRY(T)                                                    \
  { #T, (uint32_t)sizeof(T) }

// MiniAVBuffer's payload union / fence are ANONYMOUS in C, so ffigen names
// them UnnamedUnion2 / UnnamedStruct1 / ... and the fence is hand-written in
// the Dart bindings (it carries an explicit pad0). Size them individually:
// a compensating pair of errors inside the union would otherwise leave
// sizeof(MiniAVBuffer) matching while a member is misaligned.
#define MINIAV_ABI_MEMBER(Name, T, Member)                                     \
  { Name, (uint32_t)sizeof(((T *)0)->Member) }

static const MiniAVAbiEntry k_abi_table[] = {
    MINIAV_ABI_ENTRY(MiniAVDeviceInfo),
    MINIAV_ABI_ENTRY(MiniAVVideoInfo),
    MINIAV_ABI_ENTRY(MiniAVAudioInfo),
    MINIAV_ABI_ENTRY(MiniAVLoopbackTargetInfo),
    MINIAV_ABI_ENTRY(MiniAVKeyboardEvent),
    MINIAV_ABI_ENTRY(MiniAVMouseEvent),
    MINIAV_ABI_ENTRY(MiniAVGamepadEvent),
    MINIAV_ABI_ENTRY(MiniAVVec3),
    MINIAV_ABI_ENTRY(MiniAVQuat),
    MINIAV_ABI_ENTRY(MiniAVMotionEvent),
    MINIAV_ABI_ENTRY(MiniAVInputConfig),
    MINIAV_ABI_ENTRY(MiniAVVideoPlane),
    MINIAV_ABI_ENTRY(MiniAVBuffer),
    MINIAV_ABI_ENTRY(MiniAVNativeBufferInternalPayload),
    MINIAV_ABI_MEMBER("MiniAVLoopbackTargetInfo.TARGETHANDLE",
                      MiniAVLoopbackTargetInfo, TARGETHANDLE),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data", MiniAVBuffer, data),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data.video", MiniAVBuffer, data.video),
    MINIAV_ABI_MEMBER("MiniAVBuffer.data.audio", MiniAVBuffer, data.audio),
    MINIAV_ABI_ENTRY(MiniAVWindowsAppAdmissionV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsSelectionNonceV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsScreenCandidateV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictCaptureOptionsV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictWindowWitnessV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictRetirementV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictResourceProfileV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictOwnerStorageExtentV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictOwnerStorageProfileV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageProfileV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageEventV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageOpsV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageExtentV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageAuthorityV1),
    MINIAV_ABI_ENTRY(MiniAVWindowsStrictControlStorageOutcomeV1),
};

#if defined(_WIN32) && (defined(_M_X64) || defined(__x86_64__))
/* Pin native size/offsets independently of Dart's view; no packing. */
#define STRICT_SIZE(T, N) typedef char strict_size_##T[(sizeof(T) == (N)) ? 1 : -1]
#define STRICT_OFFSET(T, F, N) \
  typedef char strict_offset_##T##_##F[(offsetof(T, F) == (N)) ? 1 : -1]
STRICT_SIZE(MiniAVWindowsAppAdmissionV1, 96);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, host_epoch, 8);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, grant_generation, 16);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, runtime_source_generation, 24);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, valid_until_tick_ms, 32);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, admitted_process_handle, 40);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, process_creation_filetime, 48);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, process_id, 56);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, reserved0, 60);
STRICT_OFFSET(MiniAVWindowsAppAdmissionV1, executable_sha256, 64);
STRICT_SIZE(MiniAVWindowsSelectionNonceV1, 24);
STRICT_OFFSET(MiniAVWindowsSelectionNonceV1, nonce, 8);
STRICT_SIZE(MiniAVWindowsScreenCandidateV1, 296);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, candidate_id, 8);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, hwnd_value, 16);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, process_id, 24);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, reserved0, 28);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, process_creation_filetime, 32);
STRICT_OFFSET(MiniAVWindowsScreenCandidateV1, title_utf8, 40);
STRICT_SIZE(MiniAVWindowsStrictCaptureOptionsV1, 16);
STRICT_OFFSET(MiniAVWindowsStrictCaptureOptionsV1, strict_gpu_only, 8);
STRICT_OFFSET(MiniAVWindowsStrictCaptureOptionsV1, reserved0, 12);
STRICT_SIZE(MiniAVWindowsStrictWindowWitnessV1, 128);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, selection_nonce, 8);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, capture_id, 24);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, window_incarnation, 32);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, hwnd_value, 40);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, process_id, 48);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, reserved0, 52);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, process_creation_filetime, 56);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, host_epoch, 64);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, grant_generation, 72);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, runtime_source_generation, 80);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, valid_until_tick_ms, 88);
STRICT_OFFSET(MiniAVWindowsStrictWindowWitnessV1, executable_sha256, 96);
STRICT_SIZE(MiniAVWindowsStrictRetirementV1, 56);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, capture_id, 8);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, state, 16);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, terminal_reason, 20);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, cleanup_error, 24);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, flags, 28);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, callbacks_in_flight, 32);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, buffers_outstanding, 36);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, frames_posted, 40);
STRICT_OFFSET(MiniAVWindowsStrictRetirementV1, frames_released, 48);
STRICT_SIZE(MiniAVWindowsStrictOwnerStorageExtentV1, 24);
STRICT_SIZE(MiniAVWindowsStrictOwnerStorageProfileV1, 128);
STRICT_OFFSET(MiniAVWindowsStrictOwnerStorageProfileV1, roles, 80);
STRICT_SIZE(MiniAVWindowsStrictControlStorageProfileV1, 176);
STRICT_OFFSET(MiniAVWindowsStrictControlStorageProfileV1, roles, 80);
STRICT_SIZE(MiniAVWindowsStrictControlStorageEventV1, 56);
STRICT_OFFSET(MiniAVWindowsStrictControlStorageEventV1, source_epoch, 24);
STRICT_OFFSET(MiniAVWindowsStrictControlStorageEventV1, address, 40);
STRICT_SIZE(MiniAVWindowsStrictControlStorageOpsV1, 24);
STRICT_SIZE(MiniAVWindowsStrictControlStorageExtentV1, 16);
STRICT_SIZE(MiniAVWindowsStrictControlStorageAuthorityV1, 120);
STRICT_OFFSET(MiniAVWindowsStrictControlStorageAuthorityV1, roles, 56);
STRICT_SIZE(MiniAVWindowsStrictControlStorageOutcomeV1, 64);
STRICT_OFFSET(MiniAVWindowsStrictControlStorageOutcomeV1, context_value, 48);
STRICT_SIZE(MiniAVWindowsStrictResourceProfileV1, 64);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, capture_id, 8);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, window_incarnation, 16);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, width, 24);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, pool_slots, 36);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, flags, 44);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, frame_bytes, 48);
STRICT_OFFSET(MiniAVWindowsStrictResourceProfileV1, reserved0, 56);
/* Producer callback layouts are consumed independently of the public app ABI. */
STRICT_SIZE(MiniAVVideoInfo, 24);
STRICT_SIZE(MiniAVAudioInfo, 16);
STRICT_SIZE(MiniAVVideoPlane, 40);
STRICT_OFFSET(MiniAVVideoInfo, pixel_format, 8);
STRICT_OFFSET(MiniAVVideoInfo, output_preference, 20);
STRICT_OFFSET(MiniAVAudioInfo, channels, 8);
STRICT_OFFSET(MiniAVAudioInfo, num_frames, 12);
STRICT_OFFSET(MiniAVVideoPlane, width, 8);
STRICT_OFFSET(MiniAVVideoPlane, stride_bytes, 16);
STRICT_OFFSET(MiniAVVideoPlane, dmabuf_fd, 28);
STRICT_OFFSET(MiniAVVideoPlane, drm_format_modifier, 32);
STRICT_SIZE(MiniAVBuffer, 264);
STRICT_OFFSET(MiniAVBuffer, type, 0);
STRICT_OFFSET(MiniAVBuffer, content_type, 4);
STRICT_OFFSET(MiniAVBuffer, timestamp_us, 8);
STRICT_OFFSET(MiniAVBuffer, data, 16);
STRICT_OFFSET(MiniAVBuffer, data_size_bytes, 208);
STRICT_OFFSET(MiniAVBuffer, user_data, 216);
STRICT_OFFSET(MiniAVBuffer, internal_handle, 224);
STRICT_OFFSET(MiniAVBuffer, native_fence, 232);
#define FRAME_OFFSET(Name, Field, N) \
  typedef char frame_offset_##Name[(offsetof(MiniAVBuffer, Field) == (N)) ? 1 : -1]
FRAME_OFFSET(video_planes, data.video.planes, 48);
FRAME_OFFSET(video_plane_count, data.video.num_planes, 40);
FRAME_OFFSET(audio_info, data.audio.info, 20);
FRAME_OFFSET(audio_data, data.audio.data, 40);
FRAME_OFFSET(fence_d3d, native_fence.d3d11_fence, 240);
FRAME_OFFSET(fence_metal, native_fence.metal_shared_event, 248);
FRAME_OFFSET(fence_value, native_fence.metal_fence_value, 256);
typedef char frame_union_size[(sizeof(((MiniAVBuffer *)0)->data) == 192) ? 1 : -1];
typedef char frame_video_size[(sizeof(((MiniAVBuffer *)0)->data.video) == 192) ? 1 : -1];
typedef char frame_audio_size[(sizeof(((MiniAVBuffer *)0)->data.audio) == 32) ? 1 : -1];
typedef char frame_fence_size[(sizeof(((MiniAVBuffer *)0)->native_fence) == 32) ? 1 : -1];
typedef char frame_tags[(MINIAV_BUFFER_TYPE_VIDEO == 1 &&
    MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE == 1 &&
    MINIAV_PIXEL_FORMAT_BGRA32 == 4) ? 1 : -1];
#undef FRAME_OFFSET
#undef STRICT_SIZE
#undef STRICT_OFFSET
#endif

MINIAV_API uint32_t MiniAV_ABI_StructSize(const char *struct_name) {
  if (!struct_name) {
    return 0;
  }
  for (size_t i = 0; i < sizeof(k_abi_table) / sizeof(k_abi_table[0]); ++i) {
    if (strcmp(k_abi_table[i].name, struct_name) == 0) {
      return k_abi_table[i].size;
    }
  }
  return 0;
}

MINIAV_API uint32_t MiniAV_ABI_StructCount(void) {
  return (uint32_t)(sizeof(k_abi_table) / sizeof(k_abi_table[0]));
}

MINIAV_API const char *MiniAV_ABI_StructNameAt(uint32_t index) {
  if (index >= sizeof(k_abi_table) / sizeof(k_abi_table[0])) {
    return NULL;
  }
  return k_abi_table[index].name;
}
