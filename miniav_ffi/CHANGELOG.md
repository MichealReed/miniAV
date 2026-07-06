# minigpu_ffi CHANGELOG

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
