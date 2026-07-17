# miniAV Native Layer Audit — Windows / Linux / macOS

**Date:** 2026-07-09 · **Scope:** everything under `miniav_c/src` (~22k lines: screen,
camera, loopback, audio-input, input, common) · **Method:** 75-agent structured audit —
per-platform crawlers → per-module cross-platform gap analysis against the Windows
reference → adversarial verification of every severity ≥3 finding by re-reading the code.
81 findings: **56 CONFIRMED**, 1 refuted, 24 low-severity (unverified, listed last).
Windows screen capture (post absolute-QPC-pacing + fence-before-share fixes, 0.5.11) is
the quality bar the rest is measured against.

**How to read severity:** s5 = crash/corruption/major user-visible gap · s4 = serious
robustness/quality problem · s3 = real but bounded · s2/s1 = minor/polish.

---

## Fix status — 2026-07-09 pass (targets miniav_ffi 0.6.0)

**Shipped (Waves 1+2, plus the MF-GPU items pulled forward from Wave 4):**
camera timestamp rebase on all 3 platforms via new `miniav_rebase_time_us()`
(+ SCK screen PTS); Linux loopback copy+payload (leak + UAF); `miniav_log`
callback delivery with heap-handoff ownership (+ Dart shim frees via
`MiniAV_Free` — the old shim read a dangling stack pointer);
`MiniAV_ReleaseBuffer` wrapper leak + truthful logs; DXGI `is_configured` +
ops-signature UB; MF camera GPU texture leak (success + failure paths) +
Flush-before-share + union-safe cleanup keyed to the path actually taken;
`lost_cb` wired: WGC (item Closed + device-removed), SCK screen
(`didStopWithError`), Linux camera/loopback (PipeWire error states), macOS
camera (AVF notifications), macOS loopback (DeviceIsAlive listener); macOS
teardown drains (camera `videoOutputQueue`, screen `captureQueue`) + bounded
SCK stop; SCK start returns the real async result (10 s bound).
Windows-compiled files verified: 299 recorder tests green incl. real-camera
timestamp cadence (median 32 ms) and real WGC capture. The pass was then
adversarially reviewed (25-agent diff review): 11 confirmed findings — headed
by an SCK start-timeout → context-free → orphaned-async-chain UAF and the
destroy-path fire-and-forget stop — all fixed (generation/abandonment protocol
for the SCK chain, bounded stop in destroy, atomic one-shot lost_cb guards,
same-queue drain reentrancy guards, dispatch-guard-before-alloc in Linux
loopback, self-join detection in POSIX stop paths, formalized lost_cb
threading contract in `miniav_capture.h`). macOS/Linux changes remain
compile-unverified on this box — **CI builds on those platforms should gate
the release.**

**Waves 3+4 shipped (2026-07-09, second pass, same 0.6.0 target):** bounded
joins everywhere (new `miniav_timed_join`, WASAPI 5 s stop wait, watcher
exit-flag poll; destroy paths retry-then-leak instead of freeing under a live
thread); POSIX dispatch guard implemented (`pthread_rwlock` mirror of the
SRWLOCK — `MiniAV_Dispose`'s quiesce guarantee now exists off-Windows);
mic-input `device_inited` lifecycle (Stop/Destroy after device-lost actually
uninitializes) + one-shot lost notification + real miniaudio-backed format
queries; format truth-telling: MF committed-type readback + rational fps
matching, Linux camera negotiated-format write-back + full EnumFormat
enumeration (sync-done completion, was truncated to 1 entry), macOS loopback
negotiated-ASBD readback + guarded division + real `GetDefaultFormat` +
implemented `GetSupportedFormats`, Linux loopback negotiated-format
write-back. Windows re-verified (suite green incl. real-camera configure
through the new MF matching). The wave was adversarially reviewed (18 Opus
agents, 7 confirmed findings, all fixed — headline: the destroy leak paths
returned SUCCESS so the API layer still freed the parent context the wedged
thread dereferences; the protocol is now `MINIAV_ERROR_TIMEOUT` → API leaks
the whole context. Also fixed: spurious DEVICE_LOST on normal mic stop, s24
format-mapping hole, mutex-guarded negotiated-format write-back, enum-loop
hang guard, macOS readback-before-start ordering). Linux/macOS changes remain
compile-unverified — CI gates.

**Waves 5+6 shipped (2026-07-09, final pass, same 0.6.0 target):**
- **Input module** — Windows backend hardened (shared clock, single-active-
  context guard, absolute-QPC gamepad pacing, no more `TerminateThread` on the
  hook thread, uniform destroy-leak protocol); **NEW Linux backend**
  (`input/linux/input_context_linux_evdev.c`, raw evdev, no libudev) and
  **NEW macOS backend** (`input/macos/input_context_macos_cgtap.mm`, CGEventTap
  + GameController) — closing the "input module missing on Linux/macOS" P0
  parity gap. (Both new backends are compile-unverified — CI gates.)
- **macOS planar Metal camera** — NV12/I420 per-plane MTLTextures (was a silent
  CPU downgrade for the common camera formats); `native_fence` populated with a
  signaled `MTLSharedEvent`.
- **macOS SCK-audio loopback tier** — SCStream system-audio path inserted ahead
  of the virtual-device requirement, so stock macOS 13.x captures loopback with
  no BlackHole/third-party driver.
- **macOS screen region capture** — real, via `SCStreamConfiguration.sourceRect`
  (was `NOT_SUPPORTED`); Linux region made honest (logs that it does not crop).
- **Clock-overflow hardening** — QPC→µs and mach→µs use whole/remainder split
  arithmetic (no wrap on weeks-scale uptime).
- **MF terminal-error watchdog** — an undlisted device-lost HRESULT that recurs
  30× with no delivered frame now escalates to `lost_cb` instead of spinning
  the re-arm loop forever.
- **GPU-sync poll** made non-silent — the pre-share `D3D11_QUERY_EVENT` wait
  (DXGI + WGC) is bounded at 16 ms and logs (rate-limited) on timeout.

**Deferred (documented, both "peak" improvements — NOT defects):**
- **Full `native_fence` cross-boundary handoff** — a producer *and* Dart-side
  FFmpeg-encoder consumer change; the current bounded+logged GPU-sync poll is
  correct, and populating a fence no consumer waits on is pure per-frame
  overhead. macOS camera already populates its `MTLSharedEvent` fence.
- **Transparent WASAPI default-device reroute** — the current
  `AUDCLNT_E_DEVICE_INVALIDATED` → `lost_cb` behavior is honest and non-silent;
  transparent in-capture-thread reinit is a risky refactor of a well-tested
  path (a C-COM `IMMNotificationClient` vtable) with modest incremental value.
- **Windows screen region-crop** — DXGI/WGC still return `NOT_SUPPORTED`
  (honest); a GPU-crop hot-path change with no region test harness is deferred.

Waves 5+6 were adversarially reviewed (17 Opus agents, 6 confirmed findings,
all fixed): Linux evdev per-axis mouse-delta coalescing (diagonal Y-drop) +
64-bit stick normalization (LP32 overflow); macOS input non-destructive
config on permission failure + run-loop busy-spin guard + gamepad-rate clamp;
macOS SCK-audio stop draining an abandoned timed-out chain before the
virtual-device fallback; macOS region frame-rate + `display_%u` id parse; the
Windows input rollback routed through the never-`TerminateThread` stop; and the
misleading empty macOS camera fence removed. Windows-compiled work re-verified
green; the new Linux/macOS backends remain compile-unverified — CI gates.

The audit's core defects (Waves 1–4) and the input/parity gaps (Waves 5–6) are
now closed; only the three "peak" items above remain, all documented.

---

## Executive summary

1. **No camera backend produces a usable timestamp.** Windows copies MF's 100 ns
   REFERENCE_TIME into `timestamp_us` (10× too large, wrong epoch); Linux copies
   PipeWire's nanosecond graph-clock value (1000× too large, wrong clock); macOS uses the
   CMSampleBuffer PTS verbatim (wrong epoch, float math). Nothing is rebased onto
   `miniav_get_time_us()`. Downstream A/V sync only works today because the Dart recorder
   stamps arrival time itself — the native contract is broken on all three platforms.
2. **Linux loopback audio is broken by design.** Every delivered buffer leaks (the
   release payload is never attached), and worse, the delivered PCM pointer aliases
   PipeWire's own ring buffer which is requeued immediately after the callback returns —
   use-after-free/tearing for any consumer that holds the buffer across the FFI boundary
   (which the Dart layer always does).
3. **Device-lost notification effectively exists only in DXGI screen + WASAPI loopback +
   mic-input.** WGC screen, macOS screen (SCK), all three camera backends
   (partially on Windows), Linux loopback, and macOS loopback either never call
   `lost_cb` or don't detect loss at all. On those paths a hot-unplug / permission
   revoke / compositor restart is a silent, permanent stall.
4. **Shutdown is unbounded on POSIX.** Linux screen/camera stop paths fall through to
   untimed `pthread_join`s (the camera one even after its own 5 s timeout fires); macOS
   screen/camera free contexts without draining the dispatch queues their callbacks run
   on (shutdown use-after-free). The common callback-dispatch quiesce guard that
   `MiniAV_Dispose` relies on is a **no-op stub on non-Windows**.
5. **The common layer has three cross-platform landmines:** `MiniAV_SetLogCallback`
   stores the callback and never invokes it (all native logs go to stderr only — invisible
   in GUI apps, which is why field logs from VGM contain no `[MiniAV C]` lines);
   `MiniAV_ReleaseBuffer` leaks the payload on unknown handle types while logging that it
   freed it; QPC→µs multiply-before-divide can overflow on ~weeks of uptime.
6. **The input module is Windows-only** — and the Windows implementation is low-level
   hooks + XInput (not RawInput as named), with a callback-hijack global, `TerminateThread`
   fallbacks, and the same relative-`Sleep` pacing bug class that was just eradicated from
   screen capture.
7. **Where we're strong:** Windows screen (both backends) is genuinely reference-grade
   post-0.5.11; macOS screen already uses ScreenCaptureKit (the `_cg` filename is a
   misnomer) with a real IOSurface→Metal zero-copy path; Linux screen has a working
   DMA-BUF zero-copy path and portal integration; WASAPI loopback timestamps
   (QPC-position capture time) are exactly right; the shared mic-input module handles
   device-stop notifications on every platform.

---

## Parity matrix

| Axis | Windows | Linux | macOS |
|---|---|---|---|
| **Screen API** | WGC (preferred) + DXGI fallback | PipeWire + xdg portal | ScreenCaptureKit (12.3+), CGDisplayCreateImage legacy fallback |
| Screen GPU zero-copy | ✅ shared NT handle + pre-share fence | ✅ DMA-BUF fd (⚠ no fence/sync) | ✅ IOSurface→Metal (SCK branch only) |
| Screen pacing | ✅ absolute-QPC + hi-res timer (both backends) | n/a (graph-driven; no bug) | SCK: OS-paced ✅ · legacy: leeway GCD timer ⚠ |
| Screen window capture | WGC ✅ / DXGI ❌ | portal picker ✅ | ✅ |
| Screen region capture | ❌ NOT_SUPPORTED | ❌ (worse: silently ignored) | ❌ (SCK `sourceRect` unused) |
| Screen device-lost → `lost_cb` | DXGI ✅ (reinit-in-place) · WGC ❌ | partial teardown, no `lost_cb` | ❌ (logs only) |
| **Camera API** | Media Foundation (async reader) | PipeWire | AVFoundation |
| Camera timestamps | ❌ 100 ns units, wrong epoch | ❌ ns units, graph clock | ❌ session clock, float math |
| Camera GPU path | ✅ D3D11 shared handle (⚠ no flush/fence, leaks texture ref) | ✅ DMA-BUF | ✅ Metal (RGB only; planar falls back silently) |
| Camera hot-unplug → `lost_cb` | partial (fixed HRESULT allow-list) | ❌ | ❌ (no notifications registered at all) |
| Camera format readback (actual vs requested) | ❌ echoes request | ❌ logs but never stores | ✅ reads back committed format |
| **Loopback API** | WASAPI (+ per-process AudioClient3) | PipeWire | CoreAudio taps (14.2+) / virtual-device fallback |
| Loopback buffer safety | ✅ private copy + payload | ❌ leaks + aliases ring memory | ✅ copy (⚠ malloc on RT thread) |
| Loopback timestamps | ✅ QPC capture-position | ⚠ arrival time | ✅ host-time capture time |
| Loopback device-lost | ✅ AUDCLNT_E_DEVICE_INVALIDATED → `lost_cb` | ❌ | ❌ |
| Loopback format discovery | ✅ real mix format | ❌ hardcoded stub | ❌ hardcoded / NULL op |
| **Mic input** | shared miniaudio backend — one implementation, all platforms; stop-notification → `lost_cb` ✅ everywhere; state races + hardcoded format queries everywhere | ← same | ← same |
| **Input (kbd/mouse/pad)** | LL hooks + XInput (misnamed RawInput) | ❌ **missing entirely** | ❌ **missing entirely** |
| Dispatch quiesce guard (`MiniAV_Dispose`) | ✅ SRWLOCK | ❌ no-op stub | ❌ no-op stub |
| Monotonic µs clock | ✅ QPC (⚠ overflow at high uptime) | ✅ CLOCK_MONOTONIC | ✅ mach time (⚠ same overflow shape) |

---

## P0 — correctness fixes (ship before anything else)

### Camera timestamps are wrong on every platform
- **[s5·win]** `camera_context_win_mf.c:218` — `timestamp_us = llTimestamp` stores MF's
  100 ns REFERENCE_TIME with no `/10` and no epoch rebase onto `miniav_get_time_us()`.
- **[s5·linux]** `camera_context_linux_pipewire.c:374` — `timestamp_us = pw_buf->time`
  stores PipeWire's ns graph-clock value: no ns→µs, wrong clock, file never includes
  `miniav_time.h`.
- **[s2·macos]** `camera_context_macos_avf.mm:438` — CMSampleBuffer PTS via
  double-precision seconds×1e6; session-clock epoch, precision loss at large uptimes.
- **Fix:** one shared helper (`miniav_rebase_timestamp_us`) that converts device units and
  applies a first-frame offset against `miniav_get_time_us()`; use it in all three
  backends so the fix and its tests aren't triplicated.

### Linux loopback delivers unsafe, leaking buffers
- **[s5]** `loopback_context_linux_pipewire.c:921` — `internal_handle` never set: every
  buffer's payload contract is broken; `MiniAV_ReleaseBuffer` can free nothing → leak per
  callback (~50–100/s).
- **[s5]** `loopback_context_linux_pipewire.c:937` — `data.audio.data` points into
  PipeWire's own buffer, which is requeued via `pw_stream_queue_buffer` immediately after
  the callback returns → use-after-free for any async consumer.
- **Fix:** mirror the WASAPI pattern exactly (`loopback_context_win_wasapi.c:298-314`):
  memcpy PCM to a heap copy, attach a `MINIAV_NATIVE_HANDLE_TYPE_AUDIO` payload.

### macOS teardown races (shutdown use-after-free)
- **[s5]** `camera_context_macos_avf.mm:502` — `destroy_platform` never drains
  `videoOutputQueue`; an in-flight delegate frame can invoke `app_callback` on a freed
  context. **[s4]** same class in `stop_capture` (`camera_api.c:436` clears callbacks
  while the delegate thread still reads them).
- **[s3]** `screen_context_macos_cg.mm:577` — `cg_destroy_platform` releases the capture
  queue + frees the context with no `dispatch_sync` drain; stop uses
  `stopCaptureWithCompletionHandler:nil` (fire-and-forget).
- **Fix:** `dispatch_sync(queue, ^{})` drain barriers before free, and a
  semaphore-signaled stop completion handler (bounded wait).

### macOS screen start reports success before it can fail
- **[s5]** `screen_context_macos_cg.mm:730-847` — the whole SCK setup chain is async;
  `cg_start_capture` returns `MINIAV_SUCCESS` unconditionally. Permission/setup failures
  are invisible: `is_running=true`, zero frames forever.
- **Fix:** block on a dispatch_group/semaphore until the async chain resolves (bounded),
  or wire failures through `lost_cb`.

### Windows camera GPU path: leak + missing fence
- **[s4]** `camera_context_win_mf.c:321` — texture `AddRef`'d for the payload is never
  stored (`gpu_texture_ptr` explicitly set NULL at :565) → leaked COM object + GPU memory
  **per GPU frame**. The release code that would free it already exists (:1939) — it's
  just never populated.
- **[s4]** `camera_context_win_mf.c:230-336` — `CreateSharedHandle` with **no Flush and
  no fence** — the exact producer-side race screen capture fixed. **[s3·:1930]** the
  shared HANDLE itself is never closed by `release_buffer` (undocumented app burden).

### Common layer
- **[s4]** `miniav_logging.c:49` — `MiniAV_SetLogCallback` stores and never invokes;
  `miniav_log` is stderr-only. GUI apps (Flutter) get **no native logs at all** — this
  hid the WGC pacing warnings from every VGM field log. Fix: invoke the callback when
  set, stderr as fallback only.
- **[s4]** `miniav_utils.c:86` — the dispatch quiesce guard behind `MiniAV_Dispose` is
  `return 1`/no-op on non-Windows → the documented teardown-safety guarantee (Dart hot
  restart!) doesn't exist there. Fix: `pthread_rwlock_t` mirror of the SRWLOCK semantics.
- **[s3]** `miniav.c:136` — unknown `handle_type` in `MiniAV_ReleaseBuffer` leaks the
  payload while the epilogue logs "Freeing internal payload anyway".
- **[s3]** DXGI `screen_context_win_dxgi.c:627` — `is_configured` never set →
  `GetConfiguredFormats` permanently broken on the DXGI backend (WGC sets it correctly).
- **[s3]** `screen_context_win_dxgi.c:668` — `dxgi_configure_display` has a 4th
  `bool *audio_enabled` param but is assigned into a 3-param ops slot: formally UB,
  works by calling-convention luck. Remove the vestigial param.

---

## P1 — parity: bring Linux/macOS to the Windows bar

**Device-lost / `lost_cb` wiring** (the single biggest cross-platform robustness gap):
- WGC screen: no recovery at all — add `GetDeviceRemovedReason` + in-place session
  re-create mirroring DXGI's ACCESS_LOST handler; wire `lost_cb`
  (`screen_context_win_wgc.cpp:1493`, s5).
- macOS screen: `stream:didStopWithError:` logs only — set `is_streaming=false`, call
  `lost_cb` (`screen_context_macos_cg.mm:341`, s4).
- Linux camera (`…linux_pipewire.c:602`, s4), macOS camera (register
  `AVCaptureSessionRuntimeError`/`WasDisconnected`/`WasInterrupted`, `…avf.mm:1`, s4),
  Linux loopback (`…linux_pipewire.c:835`, s4), macOS loopback (property listeners for
  device-alive/default-changed, `…coreaudio.mm:552`, s3).

**Bounded shutdown everywhere:**
- Linux screen `pthread_join` untimed (`…linux_pipewire.c:2019`, s4); Linux camera
  timeout that falls through to an unconditional join anyway (`…linux_pipewire.c:1568`,
  s3); WASAPI join INFINITE (`…wasapi.c:1538`, s2); device-watcher join can hang on a
  wedged `enumerate()` (`miniav_device_watcher.c:246`, s3).

**Format truth-telling:**
- Linux camera: negotiated format parsed but never stored — frames stamped with the
  *requested* format (`…linux_pipewire.c:706`, s3); `GetSupportedFormats` quits after the
  first EnumFormat pod → mode list truncated to 1 (`:1180`, s4).
- macOS loopback: reported format = requested format, with an unguarded
  `mBytesPerFrame` division (`…coreaudio.mm:364`, s4); `get_supported_formats` is a NULL
  op and `get_default_format` ignores the device (`:905`, s3).
- Linux loopback: format queries are hardcoded F32/48k/2ch stubs (`:335`, s3).
- Windows camera (peak): adopt macOS's pattern — read back the committed media type
  instead of echoing the request; add rational-rate tolerant matching (s2).

**GPU-path parity:**
- Linux screen DMA-BUF: no fence/sync before sharing the fd (CPU branch does
  DMA_BUF_SYNC; GPU branch doesn't) — populate `native_fence.sync_fd` or document CPU
  preference for correctness-critical consumers (`…linux_pipewire.c:2802`, s3).
- macOS camera: planar formats (NV12/I420 — the common camera formats!) silently fall
  back to CPU despite GPU preference; implement per-plane
  `CVMetalTextureCacheCreateTextureFromImage` (`…avf.mm:344`, s3).

**Other parity items:** Linux screen global `gloop`/`gloop_thread` statics clobbered by a
second context — make per-context or refcount (`…linux_pipewire.c:46`, s3); region
capture unimplemented everywhere — Linux silently *accepts* and ignores it, fix to
NOT_SUPPORTED at minimum, or implement via SCK `sourceRect` / texture crop (s3); macOS
loopback: add an SCK-audio tier for stock macOS 13–14.1 so system loopback doesn't
require BlackHole (s2); mic-input: unsynchronized `is_running`/`lost_cb` across
miniaudio's thread and the app thread + reentrancy hazard if `lost_cb` calls
`StopCapture` (`audio_context.c:496/:486`, s4 — shared file, fixes all platforms at
once); mic-input hardcoded format queries (`:143/:322`, s3).

---

## P2 — Windows at its peak + strategic improvements

1. **Real fences instead of the 5 ms poll.** Both screen backends CPU-poll a
   D3D11_QUERY_EVENT capped at 5 ms and **silently proceed on timeout** — under exactly
   the GPU contention the boost code targets, this can reopen the black-frame race.
   `MiniAVBuffer.native_fence` exists for this and is populated by nothing. Populate
   `d3d11_fence` (screen + camera), `sync_fd` (Linux), `metal_shared_event` (macOS)
   (`screen_context_win_dxgi.c:1345`, s3).
2. **Input module rewrite + platforms.** Missing Linux (libinput/evdev) and macOS
   (CGEventTap/IOHID) backends (s5 parity gap); Windows: global
   `g_active_input_platform` context hijack (s4), `TerminateThread` leaks the OS-level
   hook (s3), unsynchronized lifecycle state (s3), no hook-eviction recovery (s3),
   `1000/hz` integer pacing + relative `Sleep` — the exact bug class fixed in screen
   (s2×2), duplicate float-math clock instead of `miniav_get_time_us()` (s2). Consider
   an actual RawInput migration (per-device identity, no AV heuristics, no eviction).
3. **WASAPI default-device reroute:** register `IMMNotificationClient` and re-init on
   default-endpoint change instead of dying on `AUDCLNT_E_DEVICE_INVALIDATED` (s3).
4. **MF camera error classification:** fixed allow-list of terminal HRESULTs can spin
   the re-arm loop forever on unlisted device-lost codes — add an N-consecutive-failures
   escalation/watchdog (`camera_context_win_mf.c:656`, s3).
5. **macOS loopback RT-thread allocations:** 3× `miniav_calloc` per buffer inside the
   CoreAudio realtime callback — use a preallocated lock-free pool (s3).
6. **Clock overflow hardening:** QPC µs conversion multiplies before dividing —
   overflows at ~weeks-scale counter values; same shape on the mach-time path. Split the
   arithmetic (`miniav_time.c:18`, s2).
7. **WGC misc:** `stop_capture` doesn't wait out an in-flight pacing sleep (narrow
   shutdown-ordering gap, s2).

---

## Low-severity backlog (unverified, s1–s2)

Linux screen: integer-division fps negotiation drops 30000/1001 (`:891`); macOS legacy
CGDisplayCreateImage timer uses leeway-quantized relative pacing (only matters pre-12.3);
WASAPI: 2 s wait timeout indistinguishable from real wakeups; polling fallback fixed 5 ms
wait; macOS loopback `stream_format` written without the capture mutex; mic-input
post-stop state asymmetry, ignored Stop result in Destroy, delivery-time timestamps;
common: `miniav_free`'s dead `ptr = NULL` + misleading comment, silent NULL-payload
release masking double-frees, watcher callback invoked under its own mutex, 1024-byte log
truncation, vestigial `MiniAVContextBase` heap object, unsynchronized QPC init.

**Refuted (excluded):** "Linux gloop pthread_create failure leaves `gloop_thread` joined
uninitialized" — the headline join mechanism misread the code; the narrower resource-leak
on that error path is real and folded into the P1 gloop item.

---

## Suggested sequencing

| Wave | Contents | Effort | Payoff |
|---|---|---|---|
| 1 | Camera timestamp rebase helper + 3 backends; Linux loopback copy+payload; `miniav_log` callback; `ReleaseBuffer` leak; DXGI `is_configured` + signature | S–M | Native A/V timestamps usable everywhere; Linux loopback safe; native logs finally visible in apps |
| 2 | `lost_cb` wiring (WGC, SCK screen, 3× camera, 2× loopback) + macOS teardown drains + SCK async start | M | Hot-unplug/permission events stop being silent hangs on every platform |
| 3 | Bounded joins (POSIX + WASAPI + watcher); POSIX dispatch guard; mic-input state locks | M | Hot-restart/shutdown can't hang or UAF |
| 4 | Format truth-telling (linux camera/loopback, macos loopback, win readback); MF GPU leak+flush; Linux EnumFormat completion | M | Correct capability discovery; GPU camera path stops leaking |
| 5 | `native_fence` end-to-end; macOS planar Metal path; WASAPI reroute; SCK-audio loopback tier | M–L | GPU paths correct under contention; loopback works on stock macOS 13+ |
| 6 | Input: Windows hardening/RawInput migration + Linux/macOS backends; region capture | L | Full module parity |

Fixes land under **miniav_ffi 0.6.0** (changelog section already open). Wave 1+2 are the
highest value-per-line in the codebase right now: they are almost entirely
apply-the-existing-Windows-pattern changes with the reference implementation to copy from
one directory over.
