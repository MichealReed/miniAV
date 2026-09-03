#ifndef MINIAV_COM_WIN_H
#define MINIAV_COM_WIN_H

#if defined(_WIN32)

#include "../../include/export.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---- Process-lifetime COM / Media Foundation ownership -------------------------
//
// WHY THIS EXISTS
//
// COM apartment membership (CoInitializeEx/CoUninitialize) is PER-THREAD, and
// Media Foundation's MFStartup/MFShutdown pair is PROCESS-GLOBAL and
// reference-counted.  Neither may be driven from individual FFI entry points,
// because the Dart VM runs isolate code on threads borrowed from a
// process-wide pool:
//
//   * one isolate's consecutive FFI calls can execute on DIFFERENT OS threads,
//     so a CoInitializeEx in call #1 and the matching CoUninitialize in call #2
//     land on different threads — one over-initialized, one under; and
//   * two isolates can be handed the SAME pool thread at different times, so
//     isolate B's CoUninitialize can evict a thread that isolate A believes it
//     still owns.
//
// When the last thread leaves the MTA, the MTA is destroyed and every COM
// object living in it is torn down.  Other threads still holding IMMDevice /
// IAudioClient / IMFSourceReader pointers then call through freed vtables —
// which is the 0xC0000005 with a garbage instruction pointer.
//
// THE CONTRACT
//
// The library takes ONE process-lifetime reference on the MTA (CoIncrementMTAUsage,
// or a dedicated holder thread on pre-Win8) and performs ONE MFStartup.  Neither
// is ever released:
//
//   * A held MTA usage reference keeps the MTA alive no matter how many stray
//     CoUninitialize calls other components (miniaudio, host app, Flutter) make,
//     and makes any thread that never called CoInitializeEx an implicit MTA
//     member — including WASAPI/MF worker threads.
//   * Releasing on a refcount edge would reintroduce the identical race: the
//     count can reach zero on one isolate while another isolate's objects are
//     alive but has not yet incremented.  Monotonic init is the only shape that
//     is safe for N isolates entering concurrently.
//   * Nothing is leaked in the resource sense: both are process-scoped
//     registrations reclaimed by process teardown.  MFShutdown at DLL-unload
//     time is unsafe anyway (loader lock).
//
// MiniAV_Dispose() is unaffected — it quiesces callback dispatch and never
// touched COM or MF.

// Joins the process to the COM MTA, once, for the lifetime of the process.
// Idempotent and safe for N concurrent callers.  Does not change the CALLING
// thread's apartment: an STA host (Flutter/WinUI) keeps its STA and still works,
// because in-process COM objects are called directly.
void miniav_com_ensure_mta(void);

// miniav_com_ensure_mta() + exactly one MFStartup(MF_VERSION, MFSTARTUP_FULL).
// Returns 1 on success, 0 if MFStartup failed.  Idempotent, never shut down.
int miniav_mf_ensure(void);

// POSITIVE CONTROL ONLY.  Returns 1 when MINIAV_LEGACY_COM=1 is set in the
// environment, which restores the old per-FFI-call CoInitializeEx/CoUninitialize
// + MFStartup/MFShutdown pattern so the abort it causes can be reproduced on
// demand.  Never enable this in production.
int miniav_com_legacy_percall(void);

// POSITIVE CONTROL ONLY. Returns 1 when MINIAV_LEGACY_MFCB=1, which restores
// the old "free the IMFSourceReaderCallback in mf_destroy_platform" behaviour
// so its use-after-free can be reproduced on demand.
int miniav_mf_legacy_callback_free(void);

// Emits an INFO line with the current thread id when MINIAV_COM_TRACE=1.
// No-op otherwise.
void miniav_com_trace(const char *where, unsigned long hr);

// Exported so a loaded DLL can be asked which COM ownership model it was built
// with: 1 = process-lifetime (default), 0 = legacy per-call (MINIAV_LEGACY_COM=1).
// Doubles as the build-freshness canary for this change.
MINIAV_API int MiniAV_Win_ComOwnershipMode(void);

#ifdef __cplusplus
}
#endif

#define MINIAV_COM_ENSURE_MTA() miniav_com_ensure_mta()

#else // !_WIN32

// Portable spelling so cross-platform sources can include this header and
// state the requirement once; a no-op everywhere but Windows.
#define MINIAV_COM_ENSURE_MTA() ((void)0)

#endif // _WIN32
#endif // MINIAV_COM_WIN_H
