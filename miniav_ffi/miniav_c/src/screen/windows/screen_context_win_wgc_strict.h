#pragma once

// Private, C-compatible seams. The constructed WGC context stores only the
// holder pointer. All mutexes, delegates and shared ownership are constructed
// in the separate C++ implementation; no public buffer layout is extended.
#include "screen_context_win_wgc.h"
#include "../../../include/miniav_screen_windows_strict.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef MiniAVResultCode (*MiniAVWgcTakeDevice)(
    void *platform, void **device, void **immediate, void **winrt_device);

void *miniav_wgc_strict_create(MiniAVScreenContext *parent, void *platform,
                               MiniAVWgcTakeDevice take_device);
// Exclusive checked disposal. Non-OK retains a readable owner; post-free OK
// consumes it, even when the metadata receipt is uncertain.
MiniAVResultCode miniav_wgc_strict_delete(void *holder);
MiniAVResultCode miniav_wgc_strict_owner_storage_profile(
    MiniAVWindowsStrictOwnerStorageProfileV1 *profile);
MiniAVResultCode miniav_wgc_strict_control_storage_profile(
    MiniAVWindowsStrictControlStorageProfileV1 *profile);
MiniAVResultCode miniav_wgc_strict_control_create(
    const MiniAVWindowsStrictControlStorageAuthorityV1 *authority,
    MiniAVWindowsStrictControlStorageOutcomeV1 *outcome);
MiniAVResultCode miniav_wgc_strict_control_release(MiniAVScreenContext *context);
bool miniav_wgc_strict_claimed(void *holder);
MiniAVResultCode miniav_wgc_strict_claim_generic(void *holder);
MiniAVResultCode miniav_wgc_strict_prepare_destroy(void *holder);
void miniav_wgc_strict_cleanup_failed(void *holder, MiniAVResultCode error);
MiniAVResultCode miniav_wgc_strict_start(void *holder,
    MiniAVBufferCallback callback, void *user_data, bool *handled);
MiniAVResultCode miniav_wgc_strict_stop(void *holder, bool *handled);
MiniAVResultCode miniav_wgc_strict_set_lost(void *holder,
    MiniAVContextLostCallback callback, void *user_data);
MiniAVResultCode miniav_wgc_strict_set_cursor(void *holder, bool enabled);
MiniAVResultCode miniav_wgc_strict_formats(void *holder,
    MiniAVVideoInfo *video, MiniAVAudioInfo *audio);
MiniAVResultCode miniav_wgc_strict_release(void *holder,
    MiniAVNativeBufferInternalPayload *payload);

MiniAVResultCode miniav_wgc_strict_capabilities(uint32_t *bits, uint64_t *tick);
MiniAVResultCode miniav_wgc_strict_max_outstanding_buffers(uint32_t *maximum);
MiniAVResultCode miniav_wgc_strict_resource_profile(void *holder,
    MiniAVWindowsStrictResourceProfileV1 *profile);
MiniAVResultCode miniav_wgc_strict_begin(void *holder,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce,
    MiniAVWindowsScreenCandidateV1 **candidates, uint32_t *count);
MiniAVResultCode miniav_wgc_strict_copy_candidate(void *holder,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint32_t index,
    MiniAVWindowsScreenCandidateV1 *candidate);
MiniAVResultCode miniav_wgc_strict_configure(void *holder,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint64_t candidate_id,
    const MiniAVVideoInfo *format,
    MiniAVWindowsStrictWindowWitnessV1 *witness);
MiniAVResultCode miniav_wgc_strict_request_stop(void *holder, int32_t reason);
MiniAVResultCode miniav_wgc_strict_retirement(void *holder,
    MiniAVWindowsStrictRetirementV1 *receipt);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
#include "wgc_owner_storage.h"
// Staged private factory only. Caller reserves both original-budget roles and
// pins callback code before entry; no generic context path selects this yet.
MiniAVResultCode miniav_wgc_strict_create_funded(
    MiniAVScreenContext *parent, void *platform, MiniAVWgcTakeDevice take_device,
    const miniav::wgc_owner_storage::Ticket &holder_ticket,
    const miniav::wgc_owner_storage::Ticket &owner_ticket, void **out) noexcept;
#endif
