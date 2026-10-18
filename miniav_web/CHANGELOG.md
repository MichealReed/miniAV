# miniav_web CHANGELOG

## 0.8.1-WIP

## 0.8.0

- Standard gamepad polling and snapshots through the existing input context,
  with bounded polling; a gamepad reads as neutral when disconnected or while
  the page is hidden.
- Stopping capture from inside a callback no longer leaves a polling timer
  running.
- Screen capture delivers the audio shared with the screen:
  `configureDisplay(captureAudio: true)` asked for it, but the track was never
  read. It arrives as 48 kHz 32-bit float buffers of 960 frames (20 ms), mono or
  stereo.
  - At most one buffer is in flight, so a consumer that falls behind loses sound
    instead of building up delay. Nothing is delivered while the track is muted.
  - If audio cannot start, video carries on without it.
  - `getConfiguredFormats` reports audio only while a live audio track exists.
- Screen capture with a CPU output preference delivers frames from the start;
  the preference was honoured only after a GPU failure, so a caller that
  declined GPU `VideoFrame`s never got a picture.
- CPU delivery reads the canvas only when the video has a new frame (where
  `requestVideoFrameCallback` exists) and no faster than the configured rate,
  instead of on every animation frame.
- Screen capture implements `setCaptureFrameRate` (a track constraint, no new
  picker), `setContentHint` (the video track's `contentHint`),
  `fallbackToCpuDelivery` (switches a live GPU capture to canvas readback on the
  same approved stream and audio, without reopening the picker) and
  `cpuDeliverySurface` (that canvas, while CPU delivery runs).

## 0.7.4

- Increment downstream deps

## 0.7.3

- Screen capture no longer reads every frame back to the CPU. It hands browser
  `VideoFrame`s straight to the consumer (`MediaStreamTrackProcessor`, or
  `requestVideoFrameCallback` where that is missing), with canvas readback only
  as a last resort, and no longer sleeps ~1.1 s at start-up. The old path read
  ~8.3 MB per 1080p frame on the main thread.
- Camera and audio input use the same routes.
- New `package:miniav_web/capture_mirror.dart`: the capture mirror's consumer as
  a separate entry point without Flutter, so a worker compiled without Flutter
  can drain it.

## 0.7.2

- released 08/13/26 - MR

## 0.7.1

- Version bump to keep the miniav 0.7.1 family aligned; no change in this
  package.

## 0.7.0

- Implements the new `setIOSAppGroup` interface member (throws
  `UnsupportedError` — iOS only).

## 0.6.0

## 0.5.11

## 0.5.10

## 0.5.9

- `releaseBufferSync()` is a no-op, since web needs no explicit buffer release.

## 0.5.8

- fix audio buffer allocations and leak issue

## 0.5.7

- Fix logger noisiness

## 0.5.6

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- add setLogCallback and installStderrLogger to route native MiniAV C library
  logs to a Dart callback

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

- fixed black rendering on chrome

## 0.4.4

## 0.4.3

## 0.4.1

- fix issue with num frames not being reported for audio_inputs

## 1.0.0

- Initial version.
