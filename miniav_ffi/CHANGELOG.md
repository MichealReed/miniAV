# miniav_ffi CHANGELOG

## 0.8.1-WIP

## 0.8.0

- New, optional strict capture of one approved application's window on Windows
  x64, for hosts that must share exactly that window and nothing else. Ordinary
  screen capture is unchanged.
  - The host passes the process handle it opened when the app was approved;
    miniAV keeps it and the selected window for the whole capture and never
    falls back to ordinary capture.
  - Frames are GPU-only BGRA at one fixed size, handed out the moment the GPU
    has finished copying them, at most three at a time and no faster than the
    configured rate. While the host holds all three, the newest frame waits
    rather than being dropped, so the window's latest picture always arrives.
  - A resize, the window closing, the app exiting or the approval expiring ends
    the capture.
  - A strict capture is used once. Destroy reports it as pending until every
    frame and callback has been released; one whose clean-up fails is
    quarantined.
  - Dart bindings for every strict record and function are in
    `miniav_ffi_windows_strict_screen.dart`.
  - Verified against a real window in a separate process. Left to the host:
    checking that the native library is genuine, user consent, and finishing its
    own GPU work on a frame before releasing it.
- CPU video planes cover exactly the frame's bytes. The chroma planes of 4:2:0
  formats (NV12, NV21, I420, YV12, 10-bit 4:2:0) were viewed with the full frame
  height and ran past the end of the frame. An MJPEG frame is one plane of
  `dataSizeBytes`, and GPU frames always have empty planes (a Linux DMA-BUF
  camera frame used to get a view over its file descriptor).
- Windows input capture: an event is no longer overwritten before an
  asynchronous receiver reads it. With two controllers reporting in one poll,
  the first report (or its disconnect) was lost. Events are copied into fixed
  rings owned by the input context (256 per controller, 256 keyboard, 1024
  mouse); a receiver that falls further behind reads newer events in place of
  the ones it missed.
- Windows screen capture (WGC) delivers evenly spaced, fresh frames at the
  configured rate. The callback used to sleep out each interval while WGC queued
  frames, so the delivered frame was up to an interval old and the picture
  advanced unevenly. It now delivers the newest frame of each interval when the
  interval closes, stamped with the interval's time, holding a frame up to about
  half an interval.
- Windows window capture (WGC) reports the source lost within about a tenth of
  a second of the window closing. It relied on Windows announcing the close,
  which it does not do for every window (a closed popup whose app kept running
  never was), so such a capture just stopped delivering frames.
- Windows GPU frames from WGC and the Media Foundation camera are shared only
  after the GPU has finished writing them (a fence wait of at most 100 ms); a
  consumer on another device could read a partly written picture. A WGC frame
  still unfinished is dropped with a warning, and the camera delivers it through
  its CPU path. DXGI is unchanged.
- The D3D11 devices WGC and the Media Foundation camera create are
  multithread-protected, since their immediate contexts are used from several
  threads.
- Windows camera:
  - The default mode prefers NV12, then YUY2, then other raw formats, MJPEG
    last; 720p, then 1080p, then the size nearest 720p; 30 fps, else the nearest
    rate.
  - A raw format at a size and rate the camera offers only as MJPEG is decoded
    by Media Foundation instead of failing to configure, and keeps the camera's
    own frame timing.
  - MJPEG with the GPU output preference is delivered as CPU memory instead of
    failing on its first frame.
  - GPU frames in a texture array, mipmapped or not shareable are copied into a
    shareable texture.
  - Per-frame notes are logged once per configuration.
  - YUV frames report their colour as `MiniAVVideoBuffer.color` (native
    `MiniAV_VideoBuffer_GetColor`): the matrix and range Media Foundation
    states, else BT.601 and full range for MJPEG the reader decodes,
    limited otherwise. The choice is logged once per configuration.
- WGC asks the compositor for at most three frames per output interval
  (`MinUpdateInterval`, Windows 11 24H2+); a 240 Hz display captured at 30 fps
  made eight GPU copies per delivered frame.
- WGC logs pacing and copy timings every 10 s at info level.
- Windows Desktop Duplication reports which parts of each frame changed, as
  `MiniAVVideoBuffer.damage` (native `MiniAV_VideoBuffer_CopyDamage`).
  - `generation` counts the frames delivered in one `sourceEpoch`, and partial
    damage is relative to the frame delivered just before. Changes from captures
    that were never delivered, such as a mouse-only update, carry into the next
    frame.
  - A gap in `generation`, a size change or `fullFrame` means the whole frame
    must be processed. The first frame, bad or missing metadata and more than
    256 rectangles report the whole frame.
  - Only BGRA frames at the output's own size and orientation carry damage.
    Everything else reports `null`, including Windows Graphics Capture, which
    miniAV uses first whenever it can start.
- Screen contexts implement the new platform-interface members
  (`setCaptureFrameRate`, `setContentHint`, `fallbackToCpuDelivery`,
  `cpuDeliverySurface`) as unsupported.

## 0.7.4

- Increment downstream deps

## 0.7.3

- New `MiniAV_Audio_SetCaptureMirror`: the capture callback also writes each
  block into a caller-owned single-producer/single-consumer ring, so a consumer
  on another thread (a web worker sharing wasm memory) can read captured audio
  without calling into wasm.
- `MiniAV_AudioOutput_Configure` returns `MINIAV_ERROR_DEVICE_NOT_FOUND` for a
  `device_id` that matches no playback device, instead of silently opening the
  system default. An empty `device_id` still means the default, and the default
  is still used when the device list cannot be read.
- `MiniAV_AudioOutput_GetDefaultFormat` honours its `device_id` (the device
  name); an unknown name falls back to the default with a warning.

## 0.7.2

- released 08/13/26 - MR

## 0.7.1

- `<miniav.h>` includes `miniav_playback.h`. C code that included only
  `<miniav.h>` got an implicit declaration of
  `MiniAV_AudioOutput_CreateContext`, truncated the returned handle and crashed.
  Dart callers were not affected.
- Windows per-process loopback works: a `pid:` target used to capture the whole
  system's audio. It now uses process loopback, including the target's child
  processes, and needs Windows 10 build 20348 / Windows 11.
- **Behaviour change:** per-process loopback that cannot be delivered (older
  Windows, activation failure, a PID that is not running) fails
  `Loopback.configure` instead of substituting whole-system audio.
  `MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1` restores the substitution.
- New `MiniAV_Loopback_GetActiveTargetInfo` (C API only) reports the scope
  actually captured: the process or the whole system.
- Per-process loopback honours the requested rate, channels and format, and taps
  audio before the endpoint volume, so it is typically louder than system
  loopback.
- The Dart `MiniAVInputConfig` binding was 16 bytes shorter than the C struct,
  so `Input_Configure` read past its allocation into the motion fields. The
  bindings now match, motion types included; motion is still not delivered over
  FFI.
- New `MiniAV_ABI_StructSize` / `MiniAV_ABI_StructCount` /
  `MiniAV_ABI_StructNameAt` export the size of every struct that crosses FFI,
  and a test checks each against Dart.
- Windows loopback reports and stamps the endpoint's real format instead of the
  requested one, which wrote the wrong format into recordings from a 44.1 kHz or
  5.1 endpoint. A request the endpoint cannot meet is logged, not faked.
- Windows window capture with `captureAudio: true` delivers audio; the process
  id was formatted in a case the loopback did not match. **Behaviour change:**
  screen configure and `StartCapture` fail when audio was requested and cannot
  be set up, instead of succeeding video-only.
- WGC recreates its frame pool when the window is resized, so a resized window
  no longer reports `dataSizeBytes` past the end of the mapped buffer.
- New Windows C regression tests for loopback format reporting and WGC resizing.
- Windows camera: destroying a context no longer frees the Media Foundation
  callback while MF still holds it, which crashed the process.
- Windows COM and Media Foundation are initialised once for the process instead
  of per call. Dart isolates hop OS threads, so a per-call `CoUninitialize`
  could tear down COM objects another isolate was using.
- The WASAPI loopback capture thread joins the MTA explicitly.
- WGC stop/destroy waits for in-flight capture callbacks before freeing the
  context, and the lost callback may stop or destroy the context from inside it.
- `setLogCallback` delivers through a Dart native port instead of a
  `NativeCallable` (new C exports `MiniAV_InitDartApi` / `MiniAV_SetLogPort`),
  so a log line after the registering isolate exits no longer aborts the
  process. The callback is process-wide: the last isolate to set it receives the
  lines.
- `stopCapture()` on loopback, input and the device-change registry no longer
  closes a `NativeCallable` the native side still holds after a timeout.
- `hook/build.dart` registers the `miniav_c` sources, so an edited `.c`/`.h`
  rebuilds the native library.
- `code_assets`, `hooks` and `logging` are regular dependencies, so the native
  asset builds downstream.
- `miniav_platform_interface` is a caret range (`^0.7.0`) instead of an exact
  pin.

## 0.7.0

### GPU buffer handoff contract (Windows) — leak fixes

- The shared NT handle of a GPU frame is closed by miniav when the buffer is
  released (WGC, DXGI, MF camera); it leaked one kernel handle per frame. Import
  the handle before releasing the buffer, and do not close it yourself.
- Buffers queued to a `NativeCallable.listener` are released instead of dropped
  when capture stops; each dropped one leaked a texture and a handle.
- `MiniAVBuffer.native_fence` is documented as never populated.

Mobile platform catch-up: Android and iOS backends for camera and screen
capture. Mic capture uses the existing miniaudio module. No mobile input yet;
Android loopback is deferred.

### New backends

- Android camera (Camera2 NDK, API 24+): CPU frames as NV12, NV21 or I420, and
  an `AHARDWAREBUFFER` GPU path on API 26+.
- Android screen (MediaProjection, API 26+): the app passes a consented
  `MediaProjection` through the new `MiniAV_Screen_SetAndroidMediaProjection`;
  clearing it stops capture and fires `lost_cb`. RGBA CPU and AHardwareBuffer
  GPU paths.
- iOS camera (AVFoundation): front/back naming, NV12-preferred formats and Metal
  zero-copy textures. Returns `PERMISSION_DENIED` without prompting.
- iOS screen (ReplayKit): `app_screen` captures the app, and
  `system_screen_broadcast` captures the whole system through a Broadcast Upload
  Extension (producer kit `miniav_broadcast_sender` plus a reference
  `SampleHandler`), sharing frames through an App Group set with
  `MiniAV_Screen_SetIOSAppGroup`.
- iOS mic: the `AVAudioSession` is activated around capture, so shared mic
  capture works unchanged.

### API / infrastructure

- New error code `MINIAV_ERROR_PERMISSION_DENIED (-23)`: miniAV never prompts,
  so apps request OS permissions first. Every code has an error string, and
  `MiniAV_GetVersionString()` reports the real version.
- Dart bindings: `MINIAV_ERROR_PERMISSION_DENIED` added (an unknown code used to
  throw), and `MiniFFIScreenPlatform.setIOSAppGroup(String)`.
- Android JNI plumbing, stricter platform gates for Android and iOS, CMake
  support for both, and a CI build matrix for Windows, Linux, macOS, Android and
  iOS.
- Flutter consent piece (in `miniav_flutter`): `requestScreenCapture()`,
  starting the foreground service before `getMediaProjection` as Android 14
  requires.

### Remote-desktop primitives (desktop output/control direction)

- New `MiniAV_Inject_*` module replays keyboard and mouse events on the local
  machine: Windows `SendInput`, macOS `CGEventPost` (needs Accessibility), Linux
  `/dev/uinput` (X11 and Wayland). It takes the same event structs capture
  produces; missing permission is `MINIAV_ERROR_PERMISSION_DENIED`. No gamepad
  injection.
- `MiniAV_Screen_SetCaptureCursor(ctx, bool)` (before configure, off by default)
  draws the cursor on Windows WGC, macOS ScreenCaptureKit and Linux PipeWire.
  DXGI cannot, and logs a warning.
- `MiniAVMouseEvent` gains `wheel_delta_x` (horizontal wheel) and `is_absolute`.
- Dart: `MiniInject` / `MiniInjectContext`, `MiniScreen.setCaptureCursor` and
  the new mouse fields; web reports injection as unsupported.
- Linux absolute positioning works (separate relative-mouse and absolute-pointer
  devices), and macOS relative moves no longer use a stale cursor position.

## 0.6.0

- Camera timestamps are real microseconds on the shared monotonic clock on
  Windows, Linux and macOS (they were 100 ns units, nanoseconds and session
  time). macOS ScreenCaptureKit is rebased the same way.
- Linux loopback audio no longer leaks or hands out memory PipeWire reuses.
- `MiniAV_SetLogCallback` actually delivers; logs went to stderr only. The
  receiver owns each message and frees it with `MiniAV_Free`.
- Device loss (`lost_cb`) is reported by every backend: WGC, macOS
  ScreenCaptureKit, camera and loopback on Linux and macOS. An unplug or revoked
  permission used to be a silent stall.
- macOS camera and screen teardown no longer races in-flight callbacks.
- macOS ScreenCaptureKit `StartCapture` reports real failures (10 s timeout →
  `MINIAV_ERROR_TIMEOUT`) instead of succeeding with no frames.
- Windows camera GPU path: no texture leak per frame, a flush before sharing,
  and correct clean-up of frames that fell back to CPU.
- `MiniAV_ReleaseBuffer` no longer leaks on invalid-context branches.
- DXGI: `GetConfiguredFormats` works again.
- `lost_cb` runs on internal threads: do not stop or destroy the context
  synchronously from inside it.
- Added `miniav_c/NATIVE_AUDIT.md`, the cross-platform audit and roadmap.
- Shutdown is bounded on every platform: stop paths time out
  (`MINIAV_ERROR_TIMEOUT`) instead of hanging, and a thread that will not exit
  leaks its context (logged) rather than having it freed under it.
- The callback-dispatch guard works on Linux and macOS, so `MiniAV_Dispose`
  waits for in-flight callbacks (hot restart).
- Mic input: stop/destroy after a device loss releases the device, and device
  loss fires once per run.
- Formats report what was negotiated: Windows and Linux camera, macOS and Linux
  loopback, and mic input read back the real format and list real device modes
  instead of hardcoded tables. Windows camera frame-rate matching is rational
  (30000/1001).
- Input capture on Linux (evdev) and macOS (CGEventTap + GameController).
  Windows input allows one active context at a time, uses monotonic timestamps
  and polls gamepads without drift.
- macOS camera GPU path delivers NV12/I420 as per-plane Metal textures, with a
  signalled `MTLSharedEvent` in `native_fence`.
- macOS system-audio loopback works on stock macOS 13+ through ScreenCaptureKit
  (no BlackHole needed).
- macOS screen region capture.
- Clock conversions no longer overflow on long uptimes.
- The Media Foundation camera reports device loss after 30 consecutive read
  failures instead of retrying forever.
- The pre-share GPU wait on the DXGI/WGC zero-copy paths is bounded at 16 ms and
  logs when it times out.
- Not yet done (see `NATIVE_AUDIT.md`): handing `native_fence` to the encoder,
  following the WASAPI default device, Windows screen region crop.
- Review fixes across these changes: macOS start/stop races, Linux evdev
  diagonal moves, leak-on-timeout paths and format fallbacks.

## 0.5.11

- Windows screen capture (WGC + DXGI) paces frames on an absolute
  high-resolution schedule. A 30 fps target delivered ~31.4 fps (or ~21 fps
  without a raised timer resolution), which showed as regular stutter in
  recordings.

## 0.5.10

- DXGI screen capture raises the process's GPU scheduling priority and the
  capture device's GPU thread priority, so capture keeps its cadence when a game
  saturates the GPU. Failures are logged and capture continues.

## 0.5.9

- `releaseBufferSync()` releases synchronously, and `releaseBuffer()` delegates
  to it.
- DXGI releases each duplication frame right after copying it, removing a frame
  of latency and the frame-rate cap it caused.

## 0.5.8

- fix audio buffer allocations and leak issue

## 0.5.7

- Fix logger noisiness

## 0.5.6

- Add `setLogCallback` and `installStderrLogger`, routing native log lines to
  Dart.
- Fix a FormatException on non-UTF-8 log messages.

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
