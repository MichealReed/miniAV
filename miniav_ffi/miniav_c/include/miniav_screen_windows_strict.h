#ifndef MINIAV_SCREEN_WINDOWS_STRICT_H
#define MINIAV_SCREEN_WINDOWS_STRICT_H

#include "export.h"
#include "miniav_types.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Optional trusted-host Windows x64 API. These values describe an original
 * admitted process; a PID/title/digest or a deserialized record is not capture
 * permission. The native host must retain the original query/wait process
 * HANDLE through Begin's duplication and fence the context on source revoke.
 * No generic capture fallback is allowed. All V1 headers require exact size,
 * abi_version=1 and zero reserved fields; no packing or pointer-sized fields. */
typedef struct MiniAVWindowsAppAdmissionV1 {
  uint32_t struct_size, abi_version;
  uint64_t host_epoch, grant_generation, runtime_source_generation;
  uint64_t valid_until_tick_ms, admitted_process_handle;
  uint64_t process_creation_filetime;
  uint32_t process_id, reserved0;
  uint8_t executable_sha256[32];
} MiniAVWindowsAppAdmissionV1;

typedef struct MiniAVWindowsSelectionNonceV1 {
  uint32_t struct_size, abi_version;
  uint8_t nonce[16];
} MiniAVWindowsSelectionNonceV1;

typedef struct MiniAVWindowsScreenCandidateV1 {
  uint32_t struct_size, abi_version;
  uint64_t candidate_id, hwnd_value;
  uint32_t process_id, reserved0;
  uint64_t process_creation_filetime;
  char title_utf8[256];
} MiniAVWindowsScreenCandidateV1;

typedef struct MiniAVWindowsStrictCaptureOptionsV1 {
  uint32_t struct_size, abi_version;
  uint32_t strict_gpu_only, reserved0; /* strict_gpu_only must be exactly1 */
} MiniAVWindowsStrictCaptureOptionsV1;

typedef struct MiniAVWindowsStrictWindowWitnessV1 {
  uint32_t struct_size, abi_version;
  uint8_t selection_nonce[16];
  uint64_t capture_id, window_incarnation, hwnd_value;
  uint32_t process_id, reserved0;
  uint64_t process_creation_filetime, host_epoch, grant_generation;
  uint64_t runtime_source_generation, valid_until_tick_ms;
  uint8_t executable_sha256[32];
} MiniAVWindowsStrictWindowWitnessV1;

typedef struct MiniAVWindowsStrictRetirementV1 {
  uint32_t struct_size, abi_version;
  uint64_t capture_id;
  uint32_t state;
  int32_t terminal_reason, cleanup_error;
  uint32_t flags, callbacks_in_flight, buffers_outstanding;
  uint64_t frames_posted, frames_released;
} MiniAVWindowsStrictRetirementV1;

/* Exact configured geometry enforced before pool/snapshot allocation. This is
 * a producer bound, not a host budget or driver-memory measurement. flags=1
 * denotes fixed-size BGRA, two pool slots, at most three outstanding snapshots.
 * Width/height changes terminally stop this strict source; no pool Recreate.
 * The ordinary non-strict capture route retains its existing resize behavior. */
typedef struct MiniAVWindowsStrictResourceProfileV1 {
  uint32_t struct_size, abi_version;
  uint64_t capture_id, window_incarnation;
  uint32_t width, height, pixel_format, pool_slots;
  uint32_t max_outstanding_buffers, flags;
  uint64_t frame_bytes, reserved0;
} MiniAVWindowsStrictResourceProfileV1; /* V1: 64 bytes, no packing. */

/* Two strict-owner allocations, ADDITIONAL to the base screen/platform pair.
 * Metadata only: this does not claim full control/platform/physical coverage or
 * that the ordinary context-creation path selects funded storage. flags3 means
 * exact requested layouts1 plus a staged internal funded factory2. The trusted
 * bridge must still provide its original budget, consent and module identity.
 * build_identity: schema, compiler-full, STL version/update, iterator-debug,
 * C++ language, build flags, pointer bytes, default-new alignment, reserved0.
 * Build flags: NDEBUG1, DEBUG2, MT4, DLL8, Windows16, x64=32.
 * Only the exact qualified Release configuration reports known shared storage. */
typedef struct MiniAVWindowsStrictOwnerStorageExtentV1 {
  uint32_t kind, alignment; /* holder0, shared owner1 */
  uint64_t requested_bytes, reserved0;
} MiniAVWindowsStrictOwnerStorageExtentV1;
typedef struct MiniAVWindowsStrictOwnerStorageProfileV1 {
  uint32_t struct_size, abi_version, factory_revision, flags;
  uint32_t build_identity[10];
  uint32_t role_count, additional_resources;
  uint64_t total_requested_bytes, reserved0;
  MiniAVWindowsStrictOwnerStorageExtentV1 roles[2];
} MiniAVWindowsStrictOwnerStorageProfileV1; /* 128 bytes, no packing. */

/* Non-initializing, no heap/COM/GPU/capture. Requires readable size/version and
 * at least128 writable bytes. Invalid headers leave output unchanged; other
 * refusal clears only the known prefix. Success preserves unknown suffixes.
 * No caller-supplied prices, process handle or source authority is accepted. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(
    MiniAVWindowsStrictOwnerStorageProfileV1 *profile_out);

/* Cold storage bootstrap, NOT permission or an activated capture context.
 * The original trusted host reserves ALL four exact extents before entry.
 * Roles: holder0, shared owner1, base context2, WGC platform3. The latter two
 * occupy the existing base/platform positions; only two resources are added.
 * flags=3: exact requested layouts1 and cold funded constructor2. OS, driver,
 * allocator overhead and subsequent activation remain separate admissions. */
typedef struct MiniAVWindowsStrictControlStorageProfileV1 {
  uint32_t struct_size, abi_version, factory_revision, flags;
  uint32_t build_identity[10];
  uint32_t role_count, additional_resources;
  uint64_t total_requested_bytes, reserved0;
  MiniAVWindowsStrictOwnerStorageExtentV1 roles[4];
} MiniAVWindowsStrictControlStorageProfileV1; /* 176 bytes. */

/* Ledger-only callbacks: allocation-free, nonthrowing, no foreign/source
 * reentry. The host pins callback code and retains the ORIGINAL budget through
 * every callback reference. Record events: begin-allocation0, allocated1,
 * constructed2, disposed3, begin-free4, free-returned5, allocation-failed6,
 * cancel-unallocated7, quarantine8, cold-scope-closed9. Event9 proves only that
 * this cold entry never activated a source; it is NOT any SDK worker join.
 * Its acknowledgement is independent of a shared-owner weak allocation tail.
 * A callback returns exactly1 on acceptance, otherwise0. */
typedef struct MiniAVWindowsStrictControlStorageEventV1 {
  uint32_t size, version, event, role;
  uint64_t generation, source_epoch;
  uint32_t row, alignment;
  uint64_t address, bytes;
} MiniAVWindowsStrictControlStorageEventV1; /* 56 bytes. */
typedef struct MiniAVWindowsStrictControlStorageOpsV1 {
  void (*retain)(void *context);
  void (*release)(void *context);
  uint32_t (*event)(void *context,
      const MiniAVWindowsStrictControlStorageEventV1 *record);
} MiniAVWindowsStrictControlStorageOpsV1; /* 24 bytes on Windows x64. */
typedef struct MiniAVWindowsStrictControlStorageExtentV1 {
  uint64_t requested_bytes;
  uint32_t alignment, reserved0;
} MiniAVWindowsStrictControlStorageExtentV1;
typedef struct MiniAVWindowsStrictControlStorageAuthorityV1 {
  uint32_t struct_size, abi_version;
  void *context;
  const MiniAVWindowsStrictControlStorageOpsV1 *ops;
  uint64_t generation, source_epoch;
  uint32_t row, role_count;
  uint64_t reserved0;
  MiniAVWindowsStrictControlStorageExtentV1 roles[4];
} MiniAVWindowsStrictControlStorageAuthorityV1; /* 120 bytes on Windows x64. */
typedef struct MiniAVWindowsStrictControlStorageOutcomeV1 {
  uint32_t struct_size, abi_version, disposition, flags;
  int32_t result;
  uint32_t reserved0;
  uint64_t generation, source_epoch;
  uint32_t row, reserved1;
  uint64_t context_value, reserved2;
} MiniAVWindowsStrictControlStorageOutcomeV1; /* 64 bytes. */

/* Outcomes: no-entry0, known-closed1, owned-cold2, retained-context3,
 * quarantined-without-handle4. flags=1 means this cold entry never activated.
 * Inspect the outcome EVEN on non-OK. A retained context remains readable and
 * must not be dropped, retried as a fresh create or passed to generic capture.
 * Unknown cleanup keeps the original debt. These handles cannot configure,
 * select or start capture. Destroy is exclusive; OK consumes the context even
 * if a final free receipt is rejected, non-OK retains it. No generic fallback.
 * Invalid output headers are untouched; valid headers preserve unknown suffix.
 * Authority pointers are trusted in-process pointers, not fixture input. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_GetStrictControlStorageProfileV1(
    MiniAVWindowsStrictControlStorageProfileV1 *profile_out);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_CreateFundedControlV1(
    const MiniAVWindowsStrictControlStorageAuthorityV1 *authority,
    MiniAVWindowsStrictControlStorageOutcomeV1 *outcome);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_ReleaseFundedControlV1(
    MiniAVScreenContextHandle context);

/* Bits: retained-item1, admitted-process2, GPU-only4, actual-retirement8.
 * Only complete mask15 is supported. Supported Windows x64 WGC installations
 * return that mask and the monotonic GetTickCount64 clock; all other profiles
 * return NOT_SUPPORTED with zero outputs. Discovery creates no GPU context. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_StrictCapabilitiesV1(
    uint32_t *capabilities_out, uint64_t *now_tick_ms_out);
/* Non-initializing producer bound, including listener-owned buffers after
 * Stop. The same bound gates native publication. Success currently returns3;
 * unsupported profiles return NOT_SUPPORTED and zero. It is not a count of
 * current buffers, a byte budget, or permission to Start. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1(
    uint32_t *maximum_out);
/* Non-initializing query, only after successful strict Configure and before
 * Start. It allocates no pool/texture and does not create permission. Failed
 * calls clear the known output prefix. A live original caller/context remains
 * required; this record does not extend the original consent deadline. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_GetStrictResourceProfileV1(
    MiniAVScreenContextHandle context,
    MiniAVWindowsStrictResourceProfileV1 *profile_out);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_BeginStrictSelectionV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce_out,
    MiniAVWindowsScreenCandidateV1 **candidates_out, uint32_t *count_out);
/* Allocation-free result transport: Begin retains the same bounded selection
 * in its original context and returns only its nonce/count (at most128).
 * Copy reads one caller-owned record, never a borrowed or MiniAV_Free pointer.
 * A copy is valid only before Configure/Stop, with the exact original nonce.
 * Failed calls clear the bounded known output prefix. No new capture authority
 * or extra selection is created; the existing single-use/consent rules apply. */
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_BeginStrictSelectionV2(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce_out, uint32_t *count_out);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint32_t index,
    MiniAVWindowsScreenCandidateV1 *candidate_out);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_ConfigureStrictWindowV1(
    MiniAVScreenContextHandle context,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint64_t candidate_id,
    const MiniAVVideoInfo *format,
    const MiniAVWindowsStrictCaptureOptionsV1 *options,
    MiniAVWindowsStrictWindowWitnessV1 *witness_out);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_RequestStrictStopV1(
    MiniAVScreenContextHandle context, int32_t terminal_reason);
MINIAV_API MiniAVResultCode MiniAV_Screen_Windows_GetStrictRetirementV1(
    MiniAVScreenContextHandle context,
    MiniAVWindowsStrictRetirementV1 *receipt_out);

/* RETIRED requires state2, flags31, real zero callback/buffer counts and equal
 * posted/released counts. API success, timeout and process exit prove none of
 * these. Candidate strings/handles are owner-local and must not enter room data.
 * V1 candidate arrays use the existing MiniAV_Free ownership convention.
 * V2 Begin/Copy return no owned array and must not be passed to MiniAV_Free.
 * Strict contexts are permanently single-use, GPU/BGRA-only and audio-free.
 * RequestStop synchronously fences new delivery; already reserved listener
 * deliveries retain their buffers until actual release. Destroy must be
 * exclusive (no racing public calls or buffer releases), checked, and retried
 * only after PENDING becomes RETIRED; FAILED retains the context in quarantine.
 * Caller/installed-provider authentication and consumer-side last GPU use are
 * separate trusted-host responsibilities, not certified by these records. */

#ifdef __cplusplus
}
#endif
#endif
