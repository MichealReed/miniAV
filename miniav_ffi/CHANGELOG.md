# miniav_ffi CHANGELOG

## 0.7.4

- Increment downstream deps
## 0.7.3

- New `MiniAV_Audio_SetCaptureMirror`: the capture callback also writes each block into a caller-owned single-producer/single-consumer ring, so a consumer on another thread - a web worker sharing the wasm linear memory - can drain captured audio without calling into wasm at all. The ring header is eight u32 slots (monotonic write/read cursors, capacity, channels, dropped-frame count, sample rate), so occupancy is unambiguous across a 2^32 wrap with no full/empty flag; `base = NULL` detaches. The cursor accesses map onto Interlocked intrinsics under MSVC, which has no `__atomic_*` builtins.

- **`MiniAV_AudioOutput_Configure` no longer opens the wrong device.** A
  `device_id` that matched no enumerated playback device was replaced by the
  SYSTEM DEFAULT and reported as success, so a caller asking for one endpoint
  silently got another — indistinguishable, from the outside, from the request
  having worked. It now returns `MINIAV_ERROR_DEVICE_NOT_FOUND`.
  - An EMPTY `device_id` still means "system default"; that is the supported
    way to ask for it, and callers who want a fallback can retry with it.
  - The refusal applies only when device enumeration itself SUCCEEDED. If the
    device list could not be read at all (a transient COM failure on Windows),
    the previous default-fallback behaviour is kept — absence cannot be proven
    without a list.
  - Behaviour change in an error path: a caller relying on the silent
    substitution will now see a failure instead of unexpected audio. Callers
    that need a guaranteed-audible output should retry with `""`.

- `MiniAV_AudioOutput_GetDefaultFormat` now honours its `device_id` argument
  (it was `MINIAV_UNUSED` and always answered for the system default device,
  while the interface promised "for a device"). The id is the device name,
  matching the portable-id convention `Configure` resolves; an unmatched
  name falls back to the default with a warning, same policy as `Configure`.

## 0.7.2

- released 08/13/26 - MR
## 0.7.1

- **`<miniav.h>` now includes `miniav_playback.h`.** The umbrella header pulled
  in types/buffer/capture but not playback, stranding all 21 public
  `MiniAV_AudioOutput_*` declarations. A C consumer that included only
  `<miniav.h>`, as the docs say to, got an implicit declaration for
  `MiniAV_AudioOutput_CreateContext` — which C assumes returns `int`, silently
  truncating the returned 64-bit handle and segfaulting inside miniaudio on
  first use. Dart/FFI callers were never affected (they bind symbols directly).
  Trap: the symbols were exported all along, so this never failed to LINK — it
  failed at the language level, and the crash surfaces far from the include.
  Any new public header must be added to `miniav.h`.

- **Windows per-process loopback had never worked: every `pid:` target
  received the WHOLE SYSTEM's audio.** The backend called
  `IAudioClient3::InitializeSharedAudioStream(flags, <PID>, fmt, NULL)`,
  putting the target PID in the `PeriodInFrames` argument. A PID is never a
  legal period, so the call always failed with
  `AUDCLNT_E_INVALID_DEVICE_PERIOD` (0x88890021) and the backend fell through
  to whole-system loopback — right format, wrong content, no error above DEBUG,
  and indistinguishable from correct output by inspecting the PCM. Real
  per-process capture is now implemented with `ActivateAudioInterfaceAsync`
  against `VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK` and
  `AUDIOCLIENT_ACTIVATION_PARAMS`, mode
  `PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE` (apps routinely render
  audio from child processes; excluding the tree would make browsers, Electron
  shells and launchers silent). Requires **Windows 10 build 20348 / Windows
  11**. Verified with a two-tone oracle: two child processes render 997 Hz and
  3001 Hz, and a `pid:` capture of either contains only its own tone at ~40000x
  separation, while a whole-system capture contains both
  (`src/loopback/test/test_loopback_process_isolation.c`; positive control
  `MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK=1` +
  `MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1` reproduces the old substitution).
- **Behaviour change: per-process loopback that cannot be delivered now FAILS
  `Loopback.configure` instead of silently substituting whole-system audio.**
  Applies to an unsupported Windows build, an activation failure, or a PID that
  is not running. `MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1` opts back into the
  substitution, which is then logged at ERROR. Whole-system loopback (a `NULL`
  or MMDevice-ID target) is untouched.
- **New: `MiniAV_Loopback_GetActiveTargetInfo`** (C API; not in the Dart
  bindings) reports the scope the backend ACTUALLY achieved —
  `MINIAV_LOOPBACK_TARGET_PROCESS` with the PID, or
  `MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO` — as opposed to the one requested.
  `MINIAV_LOOPBACK_TARGET_NONE` means the backend does not report scope
  (macOS/Linux). Windows always reports one of the first two.
- Per-process loopback genuinely negotiates, unlike endpoint loopback: the
  requested rate/channels/format is honoured and converted into (48 k, 44.1 k
  and 16 kHz verified), and it taps the target BEFORE the endpoint master
  volume, so it is typically louder than the same audio via system loopback.
  The format read-back contract from earlier in 0.7.1 is unchanged — whatever
  the stream is actually initialized with is what
  `getConfiguredFormat()` and every buffer's `info` report.
- Traps, all three of which fail silently or misleadingly:
  (1) `ActivateAudioInterfaceAsync` returns `E_ILLEGAL_METHOD_CALL`
  (0x8000000E) — before looking at the activation params at all — unless the
  completion handler is **agile**: it must answer `QueryInterface` for
  `IAgileObject` and delegate `IMarshal` to a free-threaded marshaler. C++
  samples inherit this from WRL's `FtmBase`, so it is invisible in the docs.
  (2) `IAudioClient::GetMixFormat` returns `E_NOTIMPL` on a process-loopback
  client — there is no endpoint format to inherit, the caller must supply one.
  (3) Activating for a **nonexistent PID succeeds** and then delivers zeroed
  frames forever; the PID is therefore validated with `OpenProcess` first
  (`ERROR_ACCESS_DENIED` counts as alive — elevated targets do work).

- **`MiniAVInputConfig` bindings were 16 bytes short of the C struct, so every
  `Input_Configure` read past the end of its own allocation.** The C struct
  grew three appended motion fields (`motion_rate_hz`, `motion_mode`,
  `motion_callback`) — 48 → 64 bytes — while `miniav_ffi_bindings.dart` still
  described the 7-field, 48-byte shape. `calloc<MiniAVInputConfig>()` sized the
  allocation from the short definition and `input_api.c`'s
  `ctx->config = *config;` copied 64 bytes out of it, so 16 bytes of unrelated
  heap landed in `ctx->config.motion_*`; `miniav_input_deliver_motion` calls
  `motion_callback` as a function pointer (iOS/Android backends read the same
  two fields straight from the caller's buffer during `configure`). The
  bindings now mirror the C struct (`MiniAVVec3`, `MiniAVQuat`,
  `MiniAVMotionEvent`, `MiniAVMotionMode`, `MiniAVAttitudeRef`,
  `MiniAVDisplayRotation`, `MiniAVMotionCallback` added), and
  `copyInputConfigToNative` writes the motion trio explicitly zero/null. Motion
  is still not delivered over FFI — the fields are present and inert, and
  `MINIAV_INPUT_TYPE_MOTION` is never requested, so no backend starts a sensor.
  Trap: appending a field keeps OFFSETS stable but changes `sizeof()`, and
  `sizeof()` is what callers allocate with and what struct assignment copies —
  "ABI-additive" never meant a stale binding was safe.
- **New: `MiniAV_ABI_StructSize` / `MiniAV_ABI_StructCount` /
  `MiniAV_ABI_StructNameAt`** (`src/common/miniav_abi.c`) export `sizeof()` for
  every struct that crosses the FFI boundary.
  `test/abi_struct_size_test.dart` asserts `sizeOf<T>()` against C for all of
  them and fails if C adds a struct Dart does not check. Audited with it and
  clean: `MiniAVDeviceInfo` 513, `MiniAVVideoInfo` 24, `MiniAVAudioInfo` 16,
  `MiniAVLoopbackTargetInfo` 16, `MiniAVKeyboardEvent` 24, `MiniAVMouseEvent`
  48, `MiniAVGamepadEvent` 32, `MiniAVVec3` 24, `MiniAVQuat` 32,
  `MiniAVMotionEvent` 232, `MiniAVVideoPlane` 40, `MiniAVBuffer` 264,
  `MiniAVNativeBufferInternalPayload` 72, plus the anonymous
  `MiniAVLoopbackTargetInfo.TARGETHANDLE` / `MiniAVBuffer.data{,.video,.audio}`
  members. `MiniAVInputConfig` was the only mismatch.

- **Windows loopback reported the REQUESTED audio format, not the endpoint's,
  and stamped every delivered PCM buffer with it.**
  `MiniAV_Loopback_Configure` cached the caller's request into
  `configured_video_format` right after the backend had stored the real WASAPI
  mix format there. WASAPI shared-mode loopback has no format negotiation — it
  always runs at the endpoint mix format — so on a 44.1 kHz or 5.1 endpoint the
  bytes were right and the label was wrong, with no error and no log; muxing
  that audio wrote the wrong sample rate into the file header. Both Windows
  screen backends hardcode a 48 kHz / 2 ch request, so this hit every screen
  recording with audio. Configure now reads the format back from the backend
  (`get_configured_video_format`) and caches THAT. Contract, matching the
  PipeWire and CoreAudio backends: **the negotiated format wins and is reported
  back** — `MiniAV_Loopback_GetConfiguredFormat` and `MiniAVAudioBuffer.info`
  describe what is actually delivered; a request the endpoint cannot provide is
  logged at WARN, not faked and not failed. `num_frames` is still carried
  through from the request (a caller-side chunk hint WASAPI does not
  negotiate). Trap: a backend that writes its result into the shared context
  field can have it clobbered by the generic layer immediately afterwards —
  PipeWire/CoreAudio were unaffected only because they keep theirs in the
  platform context.

- **Windows window capture with `captureAudio: true` delivered video only, and
  returned success.** The WGC backend formatted its per-process audio target as
  `"PID:%lu"` while `MiniAV_Loopback_Configure` matched a case-sensitive
  `"pid:"`, so the ID fell through to the "assume an MMDevice ID" branch,
  `IMMDeviceEnumerator::GetDevice(L"PID:1234")` failed, and audio was disabled
  with a WARN. Producers now emit lowercase `pid:` (canonical, same shape as
  `hwnd:`) and the consumer matches case-insensitively so IDs from older builds
  still resolve. **Behaviour change:** `MiniAV_Screen_ConfigureWindow` /
  `ConfigureDisplay` / `ConfigureRegion` and `MiniAV_Screen_StartCapture` now
  return an error when `capture_audio` was requested and no audio path could be
  established, instead of returning `MINIAV_SUCCESS` with a video-only capture.
  Both Windows screen backends (WGC and DXGI) answer the same way. Callers that
  want video regardless should configure with `captureAudio: false`. Note:
  per-process loopback still falls back to whole-system audio (see
  `docs/PLATFORM_SUPPORT.md`).

- **Windows WGC: a window resized mid-capture could be handed a
  `dataSizeBytes` past the end of the mapped buffer.** The
  `Direct3D11CaptureFramePool` was sized once from `capture_item.Size()` at
  StartCapture and never revisited, while per-frame dimensions came from the
  live `frame.ContentSize()`; the CPU path then computed
  `RowPitch(pool-sized) * height(new, larger)` (measured: 1,180,160 bytes
  advertised over a 903,680-byte mapping), and the GPU path had the same shape.
  The pool is now recreated (`Direct3D11CaptureFramePool::Recreate`) when the
  content size changes, and the reported extent is clamped to what was actually
  mapped/allocated either way. Recreation runs under the context's critical
  section — the same lock teardown holds while closing the pool — after the
  frame is closed and outside the callback drain, so it cannot deadlock against
  the existing `WGCCallbackRef` / `wgc_drain_callbacks` protocol. New exports
  `miniav_wgc_debug_oversize_reports()` and
  `miniav_wgc_debug_pool_recreates()` back the regression harness. Trap: a
  frame pool's surfaces are always pool-sized; `ContentSize()` is the target's
  live size and the two are only equal until something resizes.

- **New Windows-only C regression harnesses**, both with positive controls that
  restore the pre-fix behaviour and fail if the bug does *not* reproduce:
  `src/loopback/test/test_loopback_format_honesty.c`
  (`MINIAV_LOOPBACK_STRESS_REQUESTED_FORMAT=1`,
  `MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID=1`) and
  `src/screen/test/test_wgc_resize_stress.c`
  (`MINIAV_WGC_STRESS_NO_POOL_RECREATE=1`, `MINIAV_WGC_STRESS_UPPERCASE_PID=1`,
  `MINIAV_SCREEN_STRESS_AUDIO_OPTIONAL=1`).

- **Windows camera: destroying a context no longer frees the Media Foundation
  source-reader callback while MF still holds it.** `MFPlatformContext` *is*
  the `IMFSourceReaderCallback` given to the source reader, so MF holds a
  reference and drops it asynchronously on an RTWorkQ thread — after
  `IMFSourceReader_Release` has returned. `mf_destroy_platform` freed the
  object outright and `MFPlatform_Release` deliberately did nothing at
  refcount 0, so MFReadWrite then called through a freed vtable and killed the
  process with `0xC0000005` at a heap address. Release now frees on the last
  reference (whichever thread holds it) and destroy drops only its own. No API
  change. Traps: `parent_ctx` must be cleared *under the callback's critical
  section* and re-read *inside* it (a callback that latched the pointer before
  blocking on the lock would use the parent after the caller freed it); and the
  critical section must be deleted in the final release, not in destroy.
- **Windows COM/Media Foundation initialisation is now process-lifetime and
  library-owned** (`src/common/miniav_com_win.{h,c}`; one `CoIncrementMTAUsage`
  plus one `MFStartup`, never released). It used to be driven per FFI entry
  point in the camera (MF), loopback (WASAPI) and screen (WGC) backends.
  `CoInitializeEx`/`CoUninitialize` are PER-THREAD and a Dart isolate does not
  own a fixed OS thread: measured on this suite, one isolate's consecutive FFI
  calls ran on three different pool threads, and single pool threads served two
  different isolates. A `CoUninitialize` therefore evicted a thread another
  isolate believed it owned, and the last thread leaving the MTA destroyed
  every COM object in it. No API change; single-consumer behaviour is
  unchanged and an STA host keeps its STA. Traps: releasing on a refcount edge
  would reintroduce the race (the count can reach zero while another isolate's
  objects are live), so init is deliberately monotonic; the held MTA reference
  is also what makes miniaudio's own unpaired `CoUninitialize` survivable, so
  `MINIAV_COM_ENSURE_MTA()` must stay ahead of every `ma_context_init`.
  `MINIAV_COM_TRACE=1` logs each call site with its OS thread id.

- **The WASAPI loopback capture thread now joins the MTA explicitly.** It calls
  `IAudioCaptureClient`/`IAudioClient` methods but had never entered an
  apartment at all; it worked only because the process-lifetime MTA reference
  above makes an uninitialised thread an implicit MTA member and because these
  are direct in-process vtable calls with no marshalling — an accident of the
  current design rather than a contract. It now pairs `CoInitializeEx`/
  `CoUninitialize` around the thread body. Trap, and the distinction that
  makes this correct where per-call COM was not: a DEDICATED thread we create
  and join is the one place the pair is sound, because both calls run on the
  SAME thread with balanced lifetime — unlike FFI entry points, where the Dart
  VM hands an isolate's consecutive calls to different pool threads. The
  process MTA reference additionally guarantees this `CoUninitialize` can never
  be the last one out. `RPC_E_CHANGED_MODE` is handled by NOT uninitialising
  (it would unbalance whoever put the thread in an STA).

- **Windows screen capture (WGC): stopping or destroying a context now waits
  for in-flight capture callbacks.** WinRT dispatches `FrameArrived` /
  `GraphicsCaptureItem.Closed` on threadpool threads, and revoking an event
  token does not wait for a handler that is already running — while the FPS
  pacing loop deliberately blocks for up to a frame interval *after* releasing
  the context lock. Teardown therefore closed the pacing timer and stop event
  the callback was waiting on, deleted the critical section and freed the
  context under it. Stop/destroy now clear `is_streaming`, signal the stop
  event, revoke the tokens, release the lock, then drain an in-flight callback
  count (2 s bound, logs on expiry) before freeing. Capture-lost notification
  also takes the lock to read `lost_cb`, and invokes it unlocked so an app may
  stop or destroy from inside it. No API change; teardown may now block for the
  few ms a callback needs to unwind. Traps: the drain MUST run with the
  critical section released (an in-flight handler acquires it — draining under
  it deadlocks); and the pacing loop's no-waitable-timer fallback used a bare
  `Sleep()` that ignored the stop event, parking teardown for a whole frame
  interval — it now waits on the event, keeping the same absolute deadline.
- **`setLogCallback` now delivers through a Dart native port instead of a
  `NativeCallable`** (new C exports `MiniAV_InitDartApi` / `MiniAV_SetLogPort`;
  `miniav_c/third_party/dart_dl/` vendors the BSD-licensed Dart SDK
  dynamic-linking API). `MiniAV_SetLogCallback` is a PROCESS-GLOBAL registry:
  the installed pointer is owned by ONE isolate, and when that isolate exits
  the VM deletes the trampoline while the C library keeps the pointer — the
  next `miniav_log()` from a capture thread, or from inside a leaf FFI call
  such as `MiniAV_ReleaseBuffer`, aborted the whole process
  (`runtime_entry.cc: Callback invoked after it has been deleted`). A
  whole-suite `dart test` hit it every run, since every test FILE is a
  separate isolate in ONE VM process. Semantics are unchanged and now
  documented: PROCESS-GLOBAL, LAST WRITER WINS — with several isolates
  registered only the most recent receives lines. Trap: the message crosses as
  raw bytes, not a `Dart_CObject` string, because device names can carry
  Latin-1 and `Dart_CObject_kString` requires valid UTF-8. `MiniAVLogCallback`
  stays in the C API for non-Dart embedders, which own their function's
  lifetime; on the web/wasm build `MiniAV_InitDartApi` returns
  `MINIAV_ERROR_NOT_SUPPORTED` and the port path is inert.
- **`stopCapture()` no longer closes a `NativeCallable` the native side is
  still holding.** Loopback, input and the device-change registry closed
  theirs unconditionally and only `print`ed the native result — but
  `MINIAV_ERROR_TIMEOUT` is precisely the code the C layer returns to say "the
  thread did not join and still has your pointer" (which is why it
  deliberately leaks its own context there). Those paths now drop the callable
  without closing it, matching the native leak; closing it was a
  use-after-free that aborted the VM. Camera, screen and audio input were
  already correct (their backends fence under a critical section or a device
  join).
- `hook/build.dart` registers `miniav_c/**` sources as build dependencies.
  Without them an edited `.c`/`.h` kept serving the previously built DLL, so a
  newly added export resolved to nothing and the failure looked like a Dart
  bug.
- `code_assets`, `hooks` and `logging` are now real dependencies. `hook/build.dart`
  imports them and a consumer never receives `dev_dependencies`, so the native
  asset could not build downstream. `dart pub publish` reports this as an error;
  0.7.0 shipped past it because publishing runs with validation skipped.
- `miniav_platform_interface` is now a caret range (`^0.7.0`) rather than an
  exact pin, which had made every patch release of it unsatisfiable alongside
  this package.

## 0.7.0

### GPU buffer handoff contract (Windows) — leak fixes

- **The shared NT handle handed out on the GPU path is now closed by miniav**
  in the release path of all three Windows backends (WGC screen, DXGI screen,
  MF camera). It was previously only logged as "app is responsible", and no
  caller closed it: one leaked kernel handle per captured GPU frame. The DXGI
  backend did not even store the handle, so it was unclosable.
  Callers must import the handle before releasing the buffer and must not close
  it themselves. WGC additionally keeps an outstanding-handle counter and logs
  an ERROR at context destroy if any handle was never released.
- **Buffers queued to a `NativeCallable.listener` are no longer dropped on
  close.** `stopCapture()`/`destroy()` closed the callable immediately, and
  `close()` discards undelivered messages — a dropped buffer never reaches
  `MiniAV_ReleaseBuffer`, leaking its D3D11 texture reference and shared handle.
  Screen and camera contexts now stop the native capture first, drain pending
  callbacks into a release-only branch, and close afterwards. `destroy()` also
  no longer skips the native StopCapture.
- `MiniAVBuffer.native_fence` is documented in `miniav_buffer.h` as
  never-populated, together with the 16 ms busy-poll and proceed-on-timeout
  behaviour that stands in for it.

Mobile platform catch-up: first-class **Android** and **iOS** backends for
camera and screen capture, per `miniav_c/MOBILE_PLATFORM_SPEC.md` (six Opus
implementation agents + an 8-dimension adversarial review — 17 raw findings,
11 confirmed, all fixed). Mic capture on both platforms rides the existing
portable miniaudio module. No mobile input tier in v1; Android loopback
(AudioPlaybackCapture) deferred.

### New backends

- **Android camera (Camera2 NDK, API 24+).** ACameraManager enumeration
  (facing in the device name), AImageReader YUV_420_888 CPU path with
  truthful per-frame plane labeling (NV12/NV21 by chroma pixel-stride;
  planar always delivered as I420 with explicit per-plane pointers), and a
  runtime-gated (26+) `AHARDWAREBUFFER` GPU path. Camera clock nanoseconds →
  `miniav_rebase_time_us`. No owned threads: the NDK looper model is
  documented in the backend header.
- **Android screen (MediaProjection, effective floor 26+).** The app supplies
  a consented `MediaProjection` via the new
  `MiniAV_Screen_SetAndroidMediaProjection(jvm, projection)` seam (global-ref
  ownership transfers to native; clearing with a NULL projection is the
  authoritative stop signal and fires `lost_cb`). Native builds the
  AImageReader→Surface→VirtualDisplay pipeline; RGBA CPU path +
  AHardwareBuffer GPU path; drop-oldest under backpressure.
- **iOS camera (AVFoundation port of the macOS backend).** Discovery-session
  enumeration with front/back naming, NV12-preferred formats, the same planar
  Metal zero-copy texture path (UMA), permission gate returns
  `PERMISSION_DENIED` without prompting, interruption-aware one-shot
  `lost_cb`. Sensor-native orientation in v1.
- **iOS screen (ReplayKit, two tiers).** `app_screen` = in-app
  RPScreenRecorder (video CPU+Metal GPU paths, app-audio + optional mic).
  `system_screen_broadcast` = system-wide capture via a Broadcast Upload
  Extension: the new producer kit (`miniav_broadcast_sender` + reference
  Swift `SampleHandler` + `SETUP.md`) writes NV12 into a page-aligned
  App-Group shared-memory ring (the pipeline's only pixel copy); the host
  wraps ring slots zero-copy with `newBufferWithBytesNoCopy` + Metal texture
  views and can deliver `GPU_METAL_TEXTURE`. Drop-oldest slot leases tied to
  `MiniAV_ReleaseBuffer`; host app group set via
  `MiniAV_Screen_SetIOSAppGroup`. Protocol pinned in
  `miniav_broadcast_protocol.h`.
- **iOS mic session shim.** `AVAudioSession` PlayAndRecord (+MixWithOthers,
  +DefaultToSpeaker) is activated around miniaudio start/stop — balanced on
  every failure path — so shared mic capture works on iOS unchanged.

### API / infrastructure

- New error code `MINIAV_ERROR_PERMISSION_DENIED (-23)`; miniAV never
  prompts — apps request OS permissions first. Error-string table completed
  for all codes; `MiniAV_GetVersionString()` now reports the real version.
- Dart bindings: `MINIAV_ERROR_PERMISSION_DENIED` added to
  `MiniAVResultCode` (previously an unknown code made `fromValue` throw
  `ArgumentError`), and `MiniAV_Screen_SetIOSAppGroup` is bound with a
  `MiniFFIScreenPlatform.setIOSAppGroup(String)` implementation.
- Android JNI plumbing (`common/miniav_jni_android`): explicit
  `JavaVM*` publication (dlopen does NOT run `JNI_OnLoad`; the C-API seam is
  authoritative), per-thread attach/detach helpers.
- Platform-gate hardening: Android no longer falls into bare `__linux__`
  arms, iOS no longer falls into bare `__APPLE__` arms (loopback/input are
  cleanly `NOT_SUPPORTED` on mobile); `miniav_timed_join` correctly gated to
  glibc. CMake: iOS deployment target 13.0, Metal linked on iOS, Android
  link floor API 24 with `__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__` for
  runtime-gated 26+ APIs. New GitHub Actions matrix
  (`.github/workflows/native-build.yml`): windows / linux / macos / android
  (arm64-v8a, API 24) / ios configure+build legs.
- Flutter consent piece (in `miniav_flutter`): Kotlin MethodChannel plugin
  (`requestScreenCapture()`), mediaProjection-typed foreground service
  started **before** `getMediaProjection` (Android 14 ordering), Java-side
  `MediaProjection.Callback.onStop` relay to both Dart and native, JNI shim
  handoff to the C seam.

### Remote-desktop primitives (desktop output/control direction)

Adds the sink/control half of the A/V/Input layer so a cross-platform
remote-desktop client/server can be built on miniAV. Per
`miniav_c/REMOTE_DESKTOP_AV_PLAN.md` (three Opus per-platform agents + a
three-dimension adversarial review — 1 major + 3 minor findings, all fixed).
Audio/video *playback* is intentionally NOT here — it becomes a future
`_tools` media player (bring-your-own / bundled codec, GPU hotpath preserved).

- **Input injection — new `MiniAV_Inject_*` module** (the sink twin of input
  capture): replays synthetic keyboard/mouse events onto the local machine.
  Windows `SendInput` (compiled + linked + smoke-tested), macOS `CGEventPost`
  (Accessibility-gated, MRC), Linux `/dev/uinput` (works under X11 **and**
  Wayland). Handles keyboard down/up, mouse absolute/relative move, all
  buttons (incl. X1/X2), and vertical + horizontal wheel. The same
  `MiniAVKeyboardEvent`/`MiniAVMouseEvent` structs used by capture are
  replayed, so a captured event injects verbatim on the same platform. Codes
  are platform-native; cross-platform translation is the caller's job.
  Permissions surface as `MINIAV_ERROR_PERMISSION_DENIED` (macOS Accessibility;
  Linux `/dev/uinput` access) — miniAV never prompts. Gamepad injection is
  out of scope in v1 (needs a virtual-gamepad driver).
- **Cursor in captured frames — `MiniAV_Screen_SetCaptureCursor(ctx, bool)`**
  (call before configure; off by default). Honored on Windows WGC
  (`IsCursorCaptureEnabled`), macOS ScreenCaptureKit (`showsCursor`), and
  Linux PipeWire (portal embedded cursor mode). Windows DXGI Desktop
  Duplication cannot draw the cursor — it logs a warning and captures
  cursor-less; use the WGC backend when you need the cursor.
- **Horizontal scroll** — `MiniAVMouseEvent` gains `wheel_delta_x` (horizontal
  wheel, populated by all three capture backends) alongside the existing
  vertical `wheel_delta`, plus `is_absolute` (capture sets it true;
  injection uses it to pick absolute vs relative move). Dart FFI struct
  updated to match (byte-exact, review-verified).
- **Dart**: `MiniInject`/`MiniInjectContext`, `MiniScreen.setCaptureCursor`,
  and the new mouse fields wired through all five packages; web reports
  injection as unsupported.
- Review fixes: Linux abs-positioning no longer no-ops (a single uinput device
  advertising both relative and absolute axes was classified as a mouse and
  ignored its ABS axes → split into a relative-mouse + absolute-pointer
  device); Linux partial-event-on-EAGAIN and cross-platform wheel over-scroll
  hardened; macOS relative-move bursts now accumulate against a shadow cursor
  instead of a stale async pointer read. Linux ABS device classification is
  the one item still pending real-compositor verification (see the plan doc).

## 0.6.0

- **Camera timestamps are now real microseconds on the shared monotonic
  epoch on all three platforms.** Windows/Media Foundation stored the 100 ns
  REFERENCE_TIME into `timestamp_us` unconverted (10× too large, wrong epoch);
  Linux/PipeWire stored the nanosecond graph-clock value (1000× too large);
  macOS/AVFoundation used the raw CMSampleBuffer PTS (session epoch, float
  math). All three now convert with integer math and rebase through the new
  shared `miniav_rebase_time_us()` (`common/miniav_time.h`) — first-sample
  anchored against `miniav_get_time_us()`, automatic re-anchor on device-clock
  discontinuities. The macOS ScreenCaptureKit screen path rebases its sample
  PTS the same way. Verified on hardware: c922 webcam median inter-frame delta
  32 ms at 30 fps.
- **Linux loopback audio no longer leaks (and no longer aliases freed
  memory).** Every delivered buffer now carries the standard audio release
  payload (`internal_handle`), and the PCM is copied out of PipeWire's ring
  buffer before the `pw_buffer` is requeued — previously the delivered pointer
  aliased memory PipeWire immediately reused (use-after-free for any async
  consumer) and no buffer was ever freeable.
- **`MiniAV_SetLogCallback` actually works now.** The registered callback was
  stored and never invoked — all native logs went to stderr only, i.e. nowhere
  in GUI apps. `miniav_log` now delivers to the callback when one is set
  (stderr as fallback). Contract note: the message is heap-allocated and owned
  by the receiver (release with `MiniAV_Free`) because receivers may dispatch
  asynchronously — the Dart FFI shim (`NativeCallable.listener`) does exactly
  that, and now decodes + frees accordingly.
- **Device-lost notifications (`lost_cb`) wired across the board.**
  Previously only DXGI screen, WASAPI loopback, and mic input fired it —
  everywhere else a hot-unplug/permission revoke was a silent permanent stall:
  - WGC screen: `GraphicsCaptureItem.Closed` handler + device-removed
    detection in the frame path (one-shot, unblocks the pacing wait).
  - macOS ScreenCaptureKit: `didStopWithError:` now flips `is_streaming` and
    fires `lost_cb` (it previously only logged).
  - Linux camera + Linux loopback: PipeWire stream error states fire
    `lost_cb` before teardown.
  - macOS camera: AVCaptureSession runtime-error + device-disconnected
    notification observers.
  - macOS loopback: `kAudioDevicePropertyDeviceIsAlive` listener on the
    tap/aggregate or virtual device.
- **macOS teardown races fixed.** Camera and screen stop/destroy paths now
  drain their delegate/sample dispatch queues (`dispatch_sync` barriers)
  before callbacks are cleared or the context is freed, and ScreenCaptureKit
  stop waits (bounded) for the stream's stop completion — previously in-flight
  frame callbacks could race context teardown (use-after-free class).
- **macOS ScreenCaptureKit `StartCapture` reports real failures.** The async
  setup chain is now awaited (bounded, 10 s → `MINIAV_ERROR_TIMEOUT`);
  permission/setup failures return an error instead of "success + zero frames
  forever".
- **Windows camera GPU path:** the shareable-copy texture is now owned by the
  frame payload and released in `release_buffer` (it leaked one texture per
  GPU frame — both on success and on share-failure paths); the device context
  is flushed before `CreateSharedHandle` (same producer-side race the screen
  path guards against); frame-payload cleanup now interprets the cpu/gpu
  union by the path actually taken (a GPU-preference frame that fell back to
  CPU was cleaned up as GPU — misreading CPU pointers as COM objects).
- **`MiniAV_ReleaseBuffer`** no longer leaks the payload wrapper on
  invalid-context/unknown-handle-type branches, and its logs no longer claim
  to free things they don't.
- **DXGI screen:** `GetConfiguredFormats` works again (`is_configured` was
  never set on this backend); removed the vestigial 4th parameter from
  `dxgi_configure_display` that mismatched the ops-table function-pointer
  type (formally undefined behavior).
- **`lost_cb` contract formalized** (`MiniAVContextLostCallback` docs): the
  callback runs on internal capture/notification threads — do not
  synchronously call StopCapture/DestroyContext from inside it (several
  backends join/drain the delivering thread; the Linux stop paths now also
  detect and refuse a self-join defensively). The Dart FFI shim satisfies the
  contract automatically via its asynchronous listener delivery.
- The whole pass was itself adversarially reviewed (25-agent diff review, 11
  confirmed findings, all fixed): the SCK async start chain now uses a
  generation/abandonment protocol so a timed-out start can never
  use-after-free a destroyed context (destroy waits for — or deliberately
  leaks rather than frees under — a still-pending chain); SCK destroy uses
  the same bounded stop as stop_capture; macOS dispatch_sync drains carry
  same-queue reentrancy guards; one-shot lost_cb guards are atomic on all
  platforms; the WGC `Closed` registration is revoked on stop (no stacking
  across stop/start cycles); the Linux loopback path acquires the dispatch
  guard before allocating (no per-quantum leak after `MiniAV_Dispose`);
  PipeWire's signed buffer time is validated before rebasing; MF's timebase
  also recalibrates on reconfigure.
- Added `miniav_c/NATIVE_AUDIT.md` — the full cross-platform audit (parity
  matrix, remaining P1/P2 findings, improvement roadmap).
- **Shutdown is now bounded on every platform.** The Linux PipeWire
  screen/camera/loopback stop paths use a new `miniav_timed_join()` (5 s)
  and return `MINIAV_ERROR_TIMEOUT` instead of hanging forever on a wedged
  compositor/PipeWire call; WASAPI's stop no longer waits `INFINITE` on the
  capture thread; the device watcher bounds its poll-thread join (a wedged
  platform `enumerate()` can no longer hang `MiniAV_Dispose`). Destroy paths
  retry the join and, if a thread genuinely will not exit, deliberately LEAK
  the platform context (loudly logged) rather than free memory a live thread
  still dereferences.
- **The callback-dispatch quiesce guard is real on Linux/macOS** — a
  `pthread_rwlock` mirror of the Windows SRWLOCK implementation. Previously
  the non-Windows stubs made `MiniAV_Dispose`'s
  "block until in-flight callbacks drain" guarantee (Flutter hot restart)
  a no-op.
- **Mic-input lifecycle hardening** (shared miniaudio module): a new
  `device_inited` flag decouples teardown from `is_running`, so
  Stop/Destroy after a device-lost notification actually uninitializes the
  device (previously silently leaked, device + worker thread);
  device-lost fires exactly once per run; DestroyContext force-uninits if
  Stop fails.
- **Format truth-telling:**
  - Windows camera: after committing a media type the reader's ACTUAL
    committed type is read back into the configured format (drivers may
    adjust), and frame-rate matching is rational (30000/1001 now matches an
    equivalent expression) instead of exact numerator+denominator equality.
  - Linux camera: the negotiated stream format is written back to the
    configured format (frames were stamped with the original request), and
    `GetSupportedFormats` no longer truncates the device's mode list to one
    entry — enumeration completes on the core sync-done event after ALL
    EnumFormat params have arrived.
  - macOS loopback: the tap/aggregate (and virtual-device AudioUnit) ACTUAL
    negotiated stream format is read back after start (frame counts were
    computed from the requested format, with an unguarded division);
    `GetDefaultFormat` queries the real target/default-output device instead
    of returning a hardcoded 44.1 kHz constant; `GetSupportedFormats` is
    implemented (was a NULL op that failed unconditionally).
  - Linux loopback: the negotiated audio format is persisted to the
    configured format; the format-query stubs now truthfully describe
    PipeWire's format-adaptive semantics instead of warning about a
    hardcoded device constraint.
  - Mic input: `GetDefaultFormat`/`GetSupportedFormats` query the actual
    device's native formats via miniaudio instead of returning hardcoded
    tables (the old code ran a dead enumeration loop purely to decorate a
    log line).
- **Input capture now exists on Linux and macOS** (was Windows-only). New raw
  evdev backend (`/dev/input/event*`, no libudev) and new CGEventTap +
  GameController backend deliver keyboard/mouse/gamepad events. The Windows
  input backend was hardened: shared monotonic clock, single-active-context
  guard (a second concurrent capture is rejected, not silently hijacked),
  absolute-QPC gamepad pacing (was a drifting `Sleep(1000/hz)`), and it no
  longer `TerminateThread`s the hook thread (which would have leaked a
  systemwide hook).
- **macOS camera GPU path honors planar formats** — NV12/I420 are now delivered
  as per-plane Metal textures instead of silently downgrading to CPU, and the
  buffer carries a signaled `MTLSharedEvent` in `native_fence`.
- **macOS system-audio loopback works on stock macOS 13+** — a ScreenCaptureKit
  audio tier is tried ahead of the third-party virtual-device requirement (no
  BlackHole needed).
- **macOS screen region capture** implemented via
  `SCStreamConfiguration.sourceRect` (was unsupported).
- **Clock conversions are overflow-safe** — QPC→µs and mach-time→µs use
  whole/remainder split arithmetic so they don't wrap on weeks-scale uptime.
- **Media Foundation camera** now escalates a persistently-failing read to
  device-lost (30 consecutive failures) instead of spinning the re-arm loop
  forever on a device-lost HRESULT outside the fixed terminal set.
- **GPU-sync poll no longer silently proceeds** — the pre-share
  `D3D11_QUERY_EVENT` wait on the DXGI/WGC zero-copy paths is bounded at 16 ms
  and logs (rate-limited) on timeout, surfacing a black-frame risk under GPU
  contention instead of hiding it.
- Deferred (documented in `NATIVE_AUDIT.md`, both peak improvements not
  defects): full `native_fence` handoff to the encoder consumer, transparent
  WASAPI default-device reroute, and Windows screen region-crop.
- Waves 5+6 were adversarially reviewed (17-agent diff review, 6 confirmed
  findings + several polish items, all fixed): the new Linux evdev backend
  coalesces per-axis mouse deltas into one throttled MOVE per report (a
  diagonal move was dropping its Y axis) and widens stick normalization to
  64-bit (32-bit overflow on LP32 arches); the macOS input backend no longer
  destructively clears keyboard/mouse from the configured set on a transient
  permission failure (a later restart re-attempts the tap), guards its worker
  run loop against a busy-spin, and clamps the gamepad poll rate; macOS
  SCK-audio stop now tears down an abandoned (timed-out) SCK chain and falls
  through to stop the virtual-device fallback instead of returning early;
  macOS region capture adopts the caller's frame rate and parses the
  `display_%u` id (was 0/0 fps and always the main display); the Windows input
  gamepad-creation-failure rollback routes through the never-`TerminateThread`
  stop path; and the misleading empty-command-buffer macOS camera fence was
  removed (the IOSurface path already serializes).
- Waves 3+4 were themselves adversarially reviewed (18-agent diff review, 7
  confirmed findings, all fixed): the leak-instead-of-free destroy protocol
  now returns `MINIAV_ERROR_TIMEOUT` and the `MiniAV_*_DestroyContext` API
  layers leak the PARENT context too (the wedged thread dereferences it —
  leaking only the platform half was still a use-after-free); normal
  `MiniAV_Audio_StopCapture` no longer fires a spurious
  `MINIAV_ERROR_DEVICE_LOST` (miniaudio posts its "stopped" notification
  during uninit — `is_running` now clears first); device formats with no
  MiniAV equivalent (e.g. s24) fall back to F32 instead of reporting
  format 0; the Linux camera negotiated-format write-back is mutex-guarded
  against torn reads from `GetConfiguredFormat`; the format-enumeration loop
  cannot hang when a node never reports info (initial core sync); the macOS
  loopback format read-backs happen BEFORE IO starts (realtime-thread
  publication order + render-buffer sizing) with the deprecated CoreAudio
  selector locally silenced; the GLib loop timeout path detaches coherently.

## 0.5.11

- Windows screen capture (WGC + DXGI): frame pacing rewritten against an
  **absolute QPC schedule** slept on a high-resolution waitable timer. The old
  relative sleeps (WGC's `Sleep(interval - 2)`, DXGI's GetTickCount64 +
  integer-ms `Sleep`) systematically over-delivered ~5% in
  timer-resolution-raised processes (any Flutter app): a 30 fps target
  delivered ~31.4 fps, and the recorder's fps throttle then deleted the
  surplus frame every ~20 frames — one double-length presentation hole every
  ~0.7 s, a metronomic, clearly visible stutter in recordings. In
  default-resolution processes the same sleeps tick-rounded the other way
  (~46.9 ms spacing ≈ 21 fps). Deliveries now land on the exact requested
  rational interval (measured mean 33.33 ms for a 30 fps target); after a
  stall or idle stretch the schedule resyncs instead of bursting stale
  catch-up frames, and the pacing wait watches the stop event so shutdown
  stays responsive mid-interval.

## 0.5.10

- DXGI screen capture: best-effort GPU scheduling boost at capture start so
  capture keeps its cadence when another process (e.g. a game) saturates the
  GPU — raises the process GPU scheduling priority to HIGH via
  `D3DKMTSetProcessSchedulingPriorityClass` (resolved dynamically from gdi32;
  covers every D3D device in the process, including minigpu's) and sets
  `IDXGIDevice::SetGPUThreadPriority(+7)` on the capture device. Failures are
  logged and capture proceeds at normal priority.

## 0.5.9

- override `releaseBufferSync()` to release synchronously (the underlying
  `MiniAV_ReleaseBuffer` C call is synchronous, so no `Future`/microtask is
  allocated); `releaseBuffer()` now delegates to it.
- DXGI screen capture (`screen_context_win_dxgi.c`): release the duplication
  frame immediately after the per-frame copy instead of holding it across the
  pacing `Sleep` until the next loop iteration. Desktop Duplication will not
  compose the next frame until `ReleaseFrame`, so the old ordering capped
  producer FPS and added a full frame of latency. Pacing is now driven by
  wall-clock elapsed since the last delivered frame (`max(0, interval - elapsed)`).

## 0.5.8

- fix audio buffer allocations and leak issue

## 0.5.7

- Fix logger noisiness

## 0.5.6

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- implement setLogCallback with NativeCallable.listener in miniav_ffi
- add setLogCallback and installStderrLogger to route native MiniAV C library logs to a Dart callback

## 0.5.5

- fix wasapi loopback issue

## 0.5.4

- adds bindings observer lib to fix crash on hot restart

## 0.5.3

- Fix crash bug on hot refresh, fix crash on second use of recorder

## 0.5.2

- adds shared textures

## 0.5.1

- adds subscriptions and fixes lost device crashes

## 0.5.0

- adding input support

## 0.4.7

- fix loopback crackles

## 0.4.6

- fix build hook null
- update cmake toolchain

## 0.4.5

- fixed windows screen cpu path

## 0.4.4

## 0.4.3

## 0.4.1

- fix issue with num frames not being reported for audio_inputs

## 1.0.0

- Initial version.
