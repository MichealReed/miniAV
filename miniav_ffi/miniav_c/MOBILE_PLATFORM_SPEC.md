# miniAV Mobile Platform Catch-Up Spec (Android + iOS)

**Status: IMPLEMENTED (2026-07-10) — shipped for miniav_ffi 0.7.0, device-unverified.**
All six §6 agents delivered: Android camera (Camera2 NDK) + screen
(MediaProjection), iOS camera (AVF port) + screen (both ReplayKit tiers),
broadcast sender kit (`src/screen/ios/miniav_broadcast_sender.*` +
`broadcast_extension/`), miniav_flutter consent plugin. Phase 0 gates /
`PERMISSION_DENIED` / API seams / JNI + AVAudioSession shims / pinned
broadcast protocol / CMake truthing / CI matrix all landed. An 8-dimension
adversarial review (25 Opus agents) confirmed 11 of 17 findings — all fixed
(3 critical: two broadcast-lifecycle UAFs, one in-app late-completion UAF).
Windows desktop suites re-verified green after the shared-file edits.
**Real gates remaining:** the CI android/ios legs (first compile of the new
backends) and on-device runs. Build-flag notes discovered during
implementation: Android uses `__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__`
(link floor 24, runtime-gated 26+ APIs); iOS links Metal in the base block.

Date: 2026-07-09 · Follows the completed 6-wave desktop audit (`NATIVE_AUDIT.md`).
Target release: miniav_ffi **0.7.0** (0.6.0 ships the desktop audit work first).

**Resolved decisions (2026-07-09):**
- **Q1 Android consent:** miniav_flutter gains a small Android plugin piece
  (Kotlin MethodChannel helper + typed foreground service); miniav_ffi stays
  pure-FFI with the `MiniAV_Screen_SetAndroidMediaProjection` C seam.
- **Q2 iOS screen:** BOTH in-app ReplayKit AND the Broadcast Upload Extension
  (system-wide) — see §B.3b for the extension architecture.
- **Q3 Mobile input:** none in v1 — input stays force-OFF on Android and iOS
  (desktop input backends from Wave 5+6 remain the complete input story).
- **Q4 Android loopback:** deferred — stays force-OFF; clean follow-up on the
  projection seam once screen capture ships.

---

## 0. Where we actually are (scouted, with evidence)

The repo is further along than "no mobile support" — and further behind than the
build files imply:

| Layer | State |
|---|---|
| CMake platform detection | ✅ `MINIAV_PLATFORM_ANDROID` / `MINIAV_PLATFORM_IOS` first-class (CMakeLists 9–48) |
| CMake backend scaffolding | ⚠️ **Aspirational** — options + exact source paths already declared (`ANDROID_CAMERA2` ON, `ANDROID_MEDIAPROJECTION` ON, `IOS_AVF` ON, `IOS_REPLAYKIT` ON) but **none of the referenced files exist** → any Android/iOS configure fails at `target_sources` today |
| Dart native-assets hook | ✅ Already routes `OS.android` (Ninja) and `OS.iOS` (Make) through `native_toolchain_cmake` — no hook changes needed |
| Dart platform dispatch | ✅ `dart.library.ffi` conditional import routes Android/iOS to `miniav_ffi` automatically (both support `dart:ffi`) |
| Buffer/type layer | ✅ **Ahead of the backends**: `MINIAV_BUFFER_CONTENT_TYPE_GPU_AHARDWAREBUFFER`, `native_fence.sync_fd` (documented Linux/Android), `GPU_METAL_TEXTURE` + `metal_shared_event` shared macOS/iOS |
| Mic input (shared miniaudio) | ✅ **Nearly free**: `audio_context.c` has zero platform ifdefs; vendored miniaudio has mature AAudio (API 27+) → OpenSL ES fallback and iOS CoreAudio backends built in |
| Backend dispatch tables | ❌ **Link-error trap**: gated `#if defined(__APPLE__)` / `#if defined(__linux__)` — iOS trips `__APPLE__` (references uncompiled macOS ops), Android trips `__linux__` (references uncompiled PipeWire ops). Must become `TARGET_OS_OSX` / `!defined(__ANDROID__)` |
| Loopback + Input modules | CMake force-OFF for non-desktop (CMakeLists 59–73) — deliberate, revisit per §5/§6 |
| Permission story | ❌ None anywhere: no `MINIAV_ERROR_PERMISSION_DENIED` code, no Dart permission handling, no MethodChannel/plugin scaffolding in any package |
| Flutter example app | ✅ Has real `android/` + `ios/` folders (stock manifests — no permissions declared yet) |

**Desktop input tracking status (the "other OS" part):** Linux (`evdev`) and
macOS (`CGEventTap`+GameController) input backends were implemented and
adversarially reviewed in Wave 5+6. They are **compile-unverified** — no code
work remains; they need CI builds (Phase 0), not new implementation.

---

## 1. Design principles

1. **Stay pure-FFI.** No federated-plugin conversion. The one thing that
   genuinely cannot be done from native code (Android's MediaProjection
   consent Activity round-trip) enters through a narrow, optional seam (§4.2).
2. **Honor the pre-sketched architecture.** CMake already names the backends
   and files; we implement exactly those paths so the build scaffolding
   becomes true instead of aspirational.
3. **Same contracts as desktop.** Backend-table dispatch, payload/release
   buffer contract, `lost_cb` one-shot + threading contract, destroy
   retry-then-leak protocol (`MINIAV_ERROR_TIMEOUT` → API layer leaks parent),
   `MINIAV_SAFE_DISPATCH` gating, `miniav_get_time_us()` rebased timestamps.
   Every lesson from the 6-wave audit applies from day one.
4. **Graceful degradation is a feature.** Modules without a mobile backend
   return clean `MINIAV_ERROR_NOT_SUPPORTED`; API-level gates are runtime
   checks (`__ANDROID_API__` / `@available`), not hard minSdk bumps.
5. **Permissions are requested by the app, reported by miniAV.** Native code
   cannot show permission prompts sanely; miniAV detects and reports
   `MINIAV_ERROR_PERMISSION_DENIED` (new code), docs tell apps to use
   `permission_handler` (or equivalents) before configuring.

---

## 2. Phase 0 — Foundation (prerequisite, small, all platforms)

**P0.1 — CI compile gates.** GitHub Actions (or equivalent) matrix that
configures+builds miniav_c for: linux-x64, macos (arm64), windows, **android
(arm64-v8a, API 24)**, **ios (arm64)**. This simultaneously (a) verifies the
Wave 1–6 Linux/macOS work including the new input backends, and (b) gates all
mobile work. Until the mobile backends exist, the android/ios legs build with
the (fixed) empty backend tables.

**P0.2 — Platform-gate corrections** (link-error trap above):
- All backend tables + context headers: `#if defined(__APPLE__)` →
  `#include <TargetConditionals.h>` + `#if defined(__APPLE__) && TARGET_OS_OSX`
  for macOS-only backends; `#if defined(__linux__)` →
  `#if defined(__linux__) && !defined(__ANDROID__)` for PipeWire/evdev.
- `miniav_timed_join` guard likewise (`pthread_timedjoin_np` is glibc-only;
  Bionic lacks it — latent today, fatal the moment Android compiles a caller).

**P0.3 — API additions (small, source-compatible):**
- `MINIAV_ERROR_PERMISSION_DENIED = -23` (the macOS input backend already
  documents this gap in a comment; Android/iOS make it unavoidable).
- Complete `MiniAV_GetErrorString`'s switch (9 codes currently fall through to
  "Unrecognized error code": DEVICE_LOST, FORMAT_NOT_SUPPORTED, …, USER_CANCELLED).
- Fix `MiniAV_GetVersion` (hardcoded 0.1.0; report the real version).

**P0.4 — CMake truthing:** the Android/iOS module branches get `if(EXISTS)`
guards removed as files land (they should *fail* if a listed file is missing —
current behavior is fine once files exist); add the missing iOS deployment
target / Android per-feature API notes as comments.

---

## 3. Phase A — Android

### A.1 Camera — `src/camera/android/camera_context_android_camera2.c` (NDK Camera2, pure C)
- `ACameraManager` (API 24+; runtime-gated — on <24 return NOT_SUPPORTED):
  enumerate via `ACameraManager_getCameraIdList` + characteristics (facing,
  orientation → device name "Back Camera (0)" etc.); formats via
  `ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS`.
- Capture: `ACameraDevice_createCaptureSession` → `AImageReader` target.
  - **CPU path**: `AImageReader_new(..., AIMAGE_FORMAT_YUV_420_888)` →
    per-plane pointers/strides map directly onto `MiniAVVideoPlane[3]` (I420-
    like; report NV12 when pixelStride==2 chroma interleave detected, else I420).
  - **GPU path** (API 26+): `AImageReader_newWithUsage(...,
    AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE)` → `AImage_getHardwareBuffer` →
    deliver as `GPU_AHARDWAREBUFFER` (`planes[0].data_ptr = AHardwareBuffer*`,
    acquire-fence fd → `native_fence.sync_fd`). Payload retains the `AImage`
    (and `AHardwareBuffer_acquire`), release op frees both.
- Timestamps: `ACAMERA_SENSOR_TIMESTAMP` (ns, CLOCK_MONOTONIC-ish) →
  `miniav_rebase_time_us` (same discipline as all desktop backends).
- Lost/error: `ACameraDevice_StateCallbacks.onDisconnected/onError` +
  `ACameraCaptureSession` state → one-shot `lost_cb`.
- Permission: opening without CAMERA permission fails →
  map `ACAMERA_ERROR_PERMISSION_DENIED` → `MINIAV_ERROR_PERMISSION_DENIED`.
  Enumeration works without permission (IDs only).
- Threading: Camera2 callbacks arrive on an `ALooper` we own — dedicated
  callback thread with the standard bounded stop/join + leak protocol.
- Links: `camera2ndk`, `mediandk` (already in CMake).

### A.2 Mic input — shared miniaudio (nearly free)
- Compile `audio_context.c` as-is; miniaudio runtime-selects AAudio (27+) /
  OpenSL ES. miniaudio dlopens its backends — verify no new link libs needed
  (else add `-laaudio -lOpenSLES`).
- Manifest: `RECORD_AUDIO` documented (+ example app manifest updated).
  Failure → map to PERMISSION_DENIED where miniaudio surfaces it.

### A.3 Screen — `src/screen/android/screen_context_android_mediaprojection.c` (JNI + AImageReader)
MediaProjection is Java-only for the consent + projection object; frames can
still be pure native:
- **New C API** (Android-only, no-op elsewhere):
  `MiniAV_Screen_SetAndroidMediaProjection(void* jvm, void* media_projection_jobject)`
  — the app hands miniAV a ready `MediaProjection` (obtained through the
  consent Intent). Also accept `JavaVM*` implicitly via `JNI_OnLoad`.
- Native side (JNI): `MediaProjection.createVirtualDisplay(...)` targeting an
  `ANativeWindow` from `AImageReader` (RGBA_8888) → frames as CPU RGBA or
  (API 26+) `AHardwareBuffer` GPU path — identical delivery contract to A.1.
- `MediaProjection.Callback.onStop` → `lost_cb` (user revoked / system stop).
- **Consent + foreground-service plumbing lives in `miniav_flutter`** (§Q1):
  a ~150-line Android plugin piece — MethodChannel `requestMediaProjection()`
  → launches the consent Intent, starts the required
  `foregroundServiceType="mediaProjection"` service (API 29+; typed 34+),
  passes the resulting `MediaProjection` to the FFI layer. Apps not using
  Flutter can call the C API directly with their own projection object.
- ConfigureDisplay only in v1 (no window/region — Android has no such concept
  for projection); EnumerateDisplays returns the default display (+ metrics).

### A.4 Loopback — `AudioPlaybackCapture` (API 29+) — **scope question §Q4**
Java-only API (`AudioRecord` + `AudioPlaybackCaptureConfiguration`), requires
the same MediaProjection token. If in scope: JNI implementation in the
loopback module reusing the projection seam from A.3; playback-capture-allowed
apps only (media-usage streams; apps can opt out). If deferred: stays
force-OFF with clean NOT_SUPPORTED (current state).

### A.5 Input — **defer on Android** (recommendation)
No sane non-root path to global input from a native lib (evdev needs root;
global hooks don't exist; in-app touch belongs to Flutter itself). Gamepads
require an Activity input pipeline (or `InputManager` JNI polling with
significant caveats). Recommendation: keep force-OFF, README "Not Available";
revisit if a concrete need appears. (§Q3)

### A.6 Android build/API-level policy
- Native lib minSdk stays 21 (toolchain floors it there anyway); every feature
  gates at **runtime**: camera 24+, GPU buffers 26+, AAudio 27+, playback
  capture 29+. `MINIAV_ANDROID_API_LEVEL` compile definition already exists.
- ABIs: arm64-v8a + x86_64 (emulator); armeabi-v7a best-effort (the LP32 stick
  fix from Wave 5+6 review shows we care about 32-bit correctness).

---

## 4. Phase B — iOS

### B.1 Camera — `src/camera/ios/camera_context_ios_avf.mm` (port of macOS AVF)
The macOS backend was scouted as AppKit-free (AVFoundation/CoreMedia/CoreVideo/
Metal only) — this is a **port, not a rewrite**:
- Shared-source approach: extract the common AVF core into the iOS file with
  `TARGET_OS_*` seams (or `#include` the .mm with a device-discovery shim) —
  implementation detail left to the agent, but the capture pipeline
  (AVCaptureSession → CVPixelBuffer → planar CVMetalTexture path from Wave 5+6
  + CPU path + rebased timestamps + lost_cb) carries over.
- iOS-specific: `AVCaptureDeviceDiscoverySession` (position front/back in
  device names), `NSCameraUsageDescription` (docs + example Info.plist),
  session interruption notifications (backgrounding → `lost_cb` or
  suspend/resume — v1: fire lost_cb on interruption-ended-not-resumable only),
  `AVCaptureVideoOrientation` note (frames delivered sensor-native; rotation
  metadata deferred).
- Permission: `AVCaptureDevice.authorizationStatus` denied →
  `MINIAV_ERROR_PERMISSION_DENIED` at Configure (never trigger the prompt from
  native; docs say request app-side first).

### B.2 Mic input — shared miniaudio + AVAudioSession shim
- miniaudio's CoreAudio backend supports iOS; the gap is **AVAudioSession**:
  a small `TARGET_OS_IPHONE`-gated ObjC shim in the audio module sets
  category `AVAudioSessionCategoryPlayAndRecord` (with
  `MixWithOthers|DefaultToSpeaker` options) + activates before
  `ma_device_start`, deactivates on stop. `NSMicrophoneUsageDescription` docs.

### B.3 Screen — `src/screen/ios/screen_context_ios_replaykit.mm` (ReplayKit, BOTH tiers per Q2)

**B.3a — In-app capture** via `RPScreenRecorder startCaptureWithHandler:` —
captures the app's own screen (+app audio +mic optionally). CMSampleBuffer
video → CVPixelBuffer → same CPU/Metal delivery as camera; the
`capture_audio` flag maps to ReplayKit's app-audio buffers through the
existing screen-audio callback path.
- ReplayKit requires no Info.plist key but shows a system consent alert on
  first start; user-declined → `MINIAV_ERROR_PERMISSION_DENIED`.
- ConfigureWindow/Region → NOT_SUPPORTED.

**B.3b — System-wide capture via Broadcast Upload Extension** (Q2: in scope).
The extension is a **separate process** Apple starts on the user's behalf, so
this is a producer/consumer split across an IPC boundary:

- `EnumerateDisplays` returns TWO pseudo-displays: `"app_screen"` (B.3a) and
  `"system_screen_broadcast"` (B.3b) — the configured id selects the tier.
- **Why no GPU handles cross this boundary (investigated):** the primitives
  exist (`IOSurfaceCreateMachPort`, `IOSurfaceCreateXPCObject`,
  `MTLSharedTextureHandle`) but iOS gives a third-party app↔extension pair no
  transport that can carry them — no bootstrap mach services, no
  `NSXPCConnection` between third-party processes (macOS-only), and unix
  sockets can pass only fds (no iOS GPU object is fd-representable). One CPU
  copy out of the extension's IOSurface is therefore unavoidable — the design
  below makes it the ONLY copy in the pipeline.
- **Transport: page-aligned shared-memory ring in the App Group container**
  (mmap'd file, 3–4 NV12 slots ≈ 12 MB @1080p — inside the extension's ~50 MB
  ceiling), plus a unix-domain socket carrying only tiny slot descriptors
  (seq/dims/ts) and lifecycle. NOT raw frames over the socket (that would add
  two kernel copies at ~190 MB/s for 1080p60).
- **Extension side (ships as source template + tiny static lib):**
  - `miniav_broadcast_sender` — a small, dependency-free C/ObjC library the
    consuming app's `RPBroadcastSampleHandler` subclass calls:
    `mbs_open(app_group_id)`, `mbs_send_video(CMSampleBufferRef)`,
    `mbs_send_audio(...)`, `mbs_close()`.
  - Per frame: lock the CVPixelBuffer, memcpy planes into a free ring slot
    (ReplayKit delivers `420YpCbCr8BiPlanar` = NV12, so this is usually a
    stride-aware copy, no conversion; slot layout bakes in the bytesPerRow
    alignment Metal linear textures require), post the descriptor.
    **Drop-oldest backpressure**: slots leased by the host (see below) are
    skipped — the frame is dropped and counted; the extension must NEVER
    stall or queue pixel buffers.
- **Host side gets ZERO additional copies (unified memory):** the receiver
  wraps a slot's pages with `newBufferWithBytesNoCopy` and creates the same
  per-plane R8/RG8 `MTLTexture` views the planar camera path uses
  (texture-from-buffer over the shared pages) — so the broadcast tier CAN
  honor `MINIAV_OUTPUT_PREFERENCE_GPU`, delivering `GPU_METAL_TEXTURE`
  buffers that alias ring memory. CPU preference delivers plane pointers into
  the ring directly. Either way a slot is LEASED until the app's
  `MiniAV_ReleaseBuffer` (standard payload contract) and only then reusable
  by the extension.
- We ship: the sender lib, a reference `SampleHandler.swift` (~40 lines),
  and step-by-step Xcode target + App Group setup docs. Consumers must
  create the extension target themselves (Apple requires it be part of the
  app bundle — miniAV cannot inject it).
- **Deployment model (multi-app):** the extension is embedded in ONE host app
  per developer, but captures the ENTIRE system screen once started (from the
  picker or Control Center — the host need not be foregrounded to start). Any
  same-team app sharing the App Group can be the ring consumer — one
  extension serves a developer's whole portfolio. Cross-developer sharing is
  impossible (App Groups are team-scoped); third parties embed their own
  extension from our template.
- **Host-suspension caveat:** a backgrounded host without a background mode
  is suspended and stops draining the ring — the extension drop-oldest's
  through the gap (no crash, counted). Continuous capture-while-backgrounded
  requires a host background mode (background audio is the common one), or
  in-extension processing (below).
- **In-extension compute (minigpu/Dawn) — investigated, deferred:** Metal is
  available in broadcast extensions and Dawn's Metal backend targets iOS, but
  the ~50 MB ceiling + CPU throttling make Dawn+Tint (device init, pipeline
  caches, WGSL-compile spikes) a jetsam gamble, and minigpu has no iOS build
  today. Mostly unnecessary anyway: the UMA ring gives the HOST zero-copy GPU
  access, so host-side minigpu is computationally identical — in-extension
  compute only buys processing while the host is suspended. If that becomes a
  requirement: dedicated Dawn-in-extension memory spike first; VideoToolbox
  in-extension encode (below) is the proven-safe fallback for that slot.
- **Phase-2 option (not v1, noted for the recorder product):** a compressed
  mode on the same sender lib — VideoToolbox HW encode INSIDE the extension,
  shipping a 2–8 Mbit/s bitstream instead of raw frames (the standard RTMP-
  broadcast-app design; sidesteps the memory ceiling and bandwidth entirely,
  and keeps working while the host is suspended). Requires a compressed video
  content type in the buffer contract (MJPEG precedent exists) and would pair
  with a future MediaCodec/VT mobile recorder path.
- **Host side (inside `screen_context_ios_replaykit.mm`):**
  - New C API (iOS-only, no-op elsewhere):
    `MiniAV_Screen_SetIOSAppGroup(const char* app_group_id)` — must be called
    before configuring the broadcast display.
  - Configure(`system_screen_broadcast`): create+listen on the socket.
  - StartCapture: present `RPSystemBroadcastPickerView` — **UIKit-on-main-
    thread**: exposed via a helper the app can trigger, or auto-presented on
    start (spec: auto-present, with the picker's `preferredExtension` set from
    an optional bundle-id parameter; document that start returns immediately
    and frames begin when the user confirms the picker — the "connected"
    moment fires an initial frame, and a 30 s no-connection timeout fires
    `lost_cb` with `MINIAV_ERROR_TIMEOUT` semantics).
  - Receiver thread parses frames → CPU NV12 `MiniAVBuffer`s (GPU tier not
    possible across the process boundary in v1), rebased timestamps, standard
    payload/release contract. Extension disconnect (user stops broadcast,
    extension killed) → one-shot `lost_cb`.
  - Bounded teardown: stop closes the socket + joins the receiver thread with
    the standard timed-join/leak protocol.
- **Honest limits (documented):** broadcast delivers CPU frames only;
  extension memory ceiling forces drop-oldest under load; user can stop the
  broadcast from the status bar at any time (that's the lost_cb path); App
  Store review requires a justification for broadcast extensions.

### B.4 Loopback — stays OFF (no system loopback exists in the iOS sandbox;
in-app audio is covered by B.3's app-audio path).

### B.5 Input — none in v1 (Q3 decision)
Input stays force-OFF on both mobile platforms (current CMake state; README
"Not Available" stands). If a need appears later, the iOS path is a cheap port
of the Wave 5+6 macOS backend's GameController half.

### B.6 iOS build policy
- Deployment target: **iOS 13.0** (ReplayKit capture API 11+, Metal shared
  events 12+, discovery session 10+; 13 is a comfortable modern floor).
- CMake: add an iOS setup block (deployment target, `-fobjc-arc` stays OFF to
  match the MRC codebase). Static lib vs dynamic framework: whatever
  `native_toolchain_cmake` produces for iOS today — P0.1's CI leg answers
  this before implementation starts.

---

## 5. What is explicitly OUT of scope (v1)

- Flutter `Texture` widget / preview rendering (buffers-as-callbacks stays;
  the minigpu render path is the documented pattern).
- Mobile HW encode in miniav_recorder (MediaCodec/VideoToolbox) — separate
  effort; recorder remains desktop-focused.
- Android window/region screen capture (concept doesn't exist), mobile input
  (both platforms, per Q3), Android loopback (per Q4 — follow-up on the
  projection seam), touch-event capture (belongs to Flutter's own input
  pipeline), GPU frames across the iOS broadcast IPC boundary, device watcher
  on mobile (device-change callbacks return NOT_SUPPORTED v1 except camera,
  which can use `ACameraManager_registerAvailabilityCallback` cheaply —
  included).

---

## 6. Execution plan (after spec confirmation)

Parallel Opus implementation agents, same pattern as Wave 5+6 (disjoint file
ownership, contracts quoted in prompts, adversarial Opus review workflow
after, CI compile gates as the final arbiter):

| Agent | Owns | Size |
|---|---|---|
| P0 (inline, orchestrator) | gates, error code+strings, version, CMake truthing, CI workflow yaml, AVAudioSession shim, Android audio link check | S/M |
| android-camera | `camera/android/camera_context_android_camera2.c` (+`.h`) | L |
| android-screen | `screen/android/screen_context_android_mediaprojection.c` (+JNI seam, `MiniAV_Screen_SetAndroidMediaProjection`) | L |
| ios-camera | `camera/ios/camera_context_ios_avf.mm` (port of macOS AVF incl. planar Metal) | M |
| ios-screen | `screen/ios/screen_context_ios_replaykit.mm` — BOTH tiers: in-app (B.3a) + broadcast host side (B.3b) | L |
| ios-broadcast-sender | `miniav_broadcast_sender` lib + reference `SampleHandler.swift` + App Group/Xcode setup docs | M |
| flutter-consent | miniav_flutter Android plugin piece (Kotlin: MethodChannel consent helper + typed foreground service) | M |

Sequencing: P0 lands first (CI legs must exist so agents' output has a compile
gate); the six agents then run in parallel — all files are disjoint;
ios-screen and ios-broadcast-sender share the frame-header/socket protocol,
which P0 pins in a tiny shared header (`screen/ios/miniav_broadcast_protocol.h`)
BEFORE the agents launch so neither invents it.

Review: one adversarial Opus workflow over the whole tranche (the Wave 5+6
review caught 6 real bugs in agent-written backends — mandatory here too).
Verification: CI matrix compiles are the gate; runtime testing requires
physical devices (flagged honestly in the changelog, same as macOS/Linux).
