#include "miniav_screen_windows_strict.h"
#include <stdbool.h>
#include <string.h>
#if defined(_WIN32) && defined(MINIAV_BACKEND_WIN_WGC_ENABLED) && \
    (defined(_M_X64) || defined(__x86_64__))
#include "windows/screen_context_win_wgc_strict.h"
#define MINIAV_HAS_STRICT_WGC 1
#endif

/* Optional strict provider; other platforms retain the fail-closed ABI. */
static bool strict_v1(const void *record, uint32_t size) {
  const uint32_t *header = (const uint32_t *)record;
  return header && header[0] == size && header[1] == 1;
}

static void strict_zero(void *record, uint32_t size) {
  if (record) {
    const uint32_t declared = *(const uint32_t *)record;
    const uint32_t writable = declared < size ? declared : size;
    if (writable) memset(record, 0, writable);
  }
}

MiniAVResultCode MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(
    MiniAVWindowsStrictOwnerStorageProfileV1 *profile_out) {
  if (!profile_out || profile_out->struct_size < sizeof(*profile_out) ||
      profile_out->abi_version != 1) return MINIAV_ERROR_INVALID_ARG;
  MiniAVWindowsStrictOwnerStorageProfileV1 result = {0};
#ifdef MINIAV_HAS_STRICT_WGC
  const MiniAVResultCode status = miniav_wgc_strict_owner_storage_profile(&result);
#else
  const MiniAVResultCode status = MINIAV_ERROR_NOT_SUPPORTED;
#endif
  if (status == MINIAV_SUCCESS) *profile_out = result;
  else memset(profile_out, 0, sizeof(*profile_out));
  return status;
}

MiniAVResultCode MiniAV_Screen_Windows_GetStrictControlStorageProfileV1(
    MiniAVWindowsStrictControlStorageProfileV1 *out) {
  if (!out || out->struct_size < sizeof(*out) || out->abi_version != 1)
    return MINIAV_ERROR_INVALID_ARG;
  MiniAVWindowsStrictControlStorageProfileV1 result = {0};
#ifdef MINIAV_HAS_STRICT_WGC
  const MiniAVResultCode status = miniav_wgc_strict_control_storage_profile(&result);
#else
  const MiniAVResultCode status = MINIAV_ERROR_NOT_SUPPORTED;
#endif
  if (status == MINIAV_SUCCESS) *out = result;
  else memset(out, 0, sizeof(*out));
  return status;
}

MiniAVResultCode MiniAV_Screen_Windows_CreateFundedControlV1(
    const MiniAVWindowsStrictControlStorageAuthorityV1 *authority,
    MiniAVWindowsStrictControlStorageOutcomeV1 *out) {
  if (!out || out->struct_size < sizeof(*out) || out->abi_version != 1)
    return MINIAV_ERROR_INVALID_ARG;
  memset(out, 0, sizeof(*out));
  out->struct_size = sizeof(*out); out->abi_version = 1; out->flags = 1;
#ifdef MINIAV_HAS_STRICT_WGC
  const MiniAVResultCode result = miniav_wgc_strict_control_create(authority, out);
#else
  (void)authority;
  const MiniAVResultCode result = MINIAV_ERROR_NOT_SUPPORTED;
#endif
  out->result = result;
  return result;
}

MiniAVResultCode MiniAV_Screen_Windows_ReleaseFundedControlV1(
    MiniAVScreenContextHandle context) {
#ifdef MINIAV_HAS_STRICT_WGC
  return miniav_wgc_strict_control_release(context);
#else
  (void)context;
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_StrictCapabilitiesV1(
    uint32_t *capabilities_out, uint64_t *now_tick_ms_out) {
  if (capabilities_out) *capabilities_out = 0;
  if (now_tick_ms_out) *now_tick_ms_out = 0;
  if (!capabilities_out || !now_tick_ms_out) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  return miniav_wgc_strict_capabilities(capabilities_out, now_tick_ms_out);
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1(
    uint32_t *maximum_out) {
  if (!maximum_out) return MINIAV_ERROR_INVALID_ARG;
  *maximum_out = 0;
#ifdef MINIAV_HAS_STRICT_WGC
  return miniav_wgc_strict_max_outstanding_buffers(maximum_out);
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_GetStrictResourceProfileV1(
    MiniAVScreenContextHandle context,
    MiniAVWindowsStrictResourceProfileV1 *profile_out) {
  const bool valid = context && strict_v1(profile_out, sizeof(*profile_out));
  strict_zero(profile_out, sizeof(*profile_out));
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_resource_profile(holder, profile_out)
                : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_BeginStrictSelectionV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce_out,
    MiniAVWindowsScreenCandidateV1 **candidates_out, uint32_t *count_out) {
  const bool valid = context && strict_v1(admission, sizeof(*admission)) &&
                     admission->reserved0 == 0 &&
                     strict_v1(nonce_out, sizeof(*nonce_out)) &&
                     candidates_out && count_out;
  strict_zero(nonce_out, sizeof(*nonce_out));
  if (candidates_out) *candidates_out = NULL;
  if (count_out) *count_out = 0;
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_begin(holder, admission, nonce_out,
      candidates_out, count_out) : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_BeginStrictSelectionV2(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce_out, uint32_t *count_out) {
  const bool valid = context && strict_v1(admission, sizeof(*admission)) &&
                     admission->reserved0 == 0 &&
                     strict_v1(nonce_out, sizeof(*nonce_out)) && count_out;
  strict_zero(nonce_out, sizeof(*nonce_out));
  if (count_out) *count_out = 0;
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_begin(holder, admission, nonce_out,
      NULL, count_out) : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint32_t index,
    MiniAVWindowsScreenCandidateV1 *candidate_out) {
  const bool valid = context && strict_v1(nonce, sizeof(*nonce)) &&
                     strict_v1(candidate_out, sizeof(*candidate_out));
  strict_zero(candidate_out, sizeof(*candidate_out));
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_copy_candidate(holder, nonce, index,
      candidate_out) : MINIAV_ERROR_NOT_SUPPORTED;
#else
  (void)index;
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_ConfigureStrictWindowV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint64_t candidate_id,
    const MiniAVVideoInfo *format,
    const MiniAVWindowsStrictCaptureOptionsV1 *options,
    MiniAVWindowsStrictWindowWitnessV1 *witness_out) {
  const bool valid = context && strict_v1(nonce, sizeof(*nonce)) &&
                     candidate_id && format &&
                     strict_v1(options, sizeof(*options)) &&
                     options->strict_gpu_only == 1 && options->reserved0 == 0 &&
                     strict_v1(witness_out, sizeof(*witness_out));
  strict_zero(witness_out, sizeof(*witness_out));
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_configure(holder, nonce, candidate_id,
      format, witness_out) : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_RequestStrictStopV1(
    MiniAVScreenContextHandle context, int32_t terminal_reason) {
  if (!context) return MINIAV_ERROR_INVALID_ARG;
  if (terminal_reason != 0 && terminal_reason != MINIAV_ERROR_PERMISSION_DENIED &&
      terminal_reason != MINIAV_ERROR_DEVICE_LOST &&
      terminal_reason != MINIAV_ERROR_FORMAT_NOT_SUPPORTED)
    return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_request_stop(holder, terminal_reason)
                : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}

MiniAVResultCode MiniAV_Screen_Windows_GetStrictRetirementV1(
    MiniAVScreenContextHandle context,
    MiniAVWindowsStrictRetirementV1 *receipt_out) {
  const bool valid = context && strict_v1(receipt_out, sizeof(*receipt_out));
  strict_zero(receipt_out, sizeof(*receipt_out));
  if (!valid) return MINIAV_ERROR_INVALID_ARG;
#ifdef MINIAV_HAS_STRICT_WGC
  void *holder = miniav_wgc_strict_holder(context);
  return holder ? miniav_wgc_strict_retirement(holder, receipt_out)
                : MINIAV_ERROR_NOT_SUPPORTED;
#else
  return MINIAV_ERROR_NOT_SUPPORTED;
#endif
}
