# miniav_web CHANGELOG

## 0.7.3

- New Release
- Screen capture is zero-readback now. It was a `<video>` -> canvas `drawImage` -> full-frame `getImageData` loop per animation frame - about 8.3 MB of synchronous main-thread readback per 1080p frame, which the browser then re-uploaded to the GPU - plus roughly 1.1 s of deliberate start-up sleeps. It now uses the same pump the camera module always had: `MediaStreamTrackProcessor(maxBufferSize: 1)` handing `VideoFrame`s straight to the consumer, a `requestVideoFrameCallback`-driven `VideoFrame(<video>)` where the processor is missing, and the canvas readback only as a final fallback. The black-frame probing sleeps are gone.
- Camera and audio input reworked onto the same routes.
- New `package:miniav_web/capture_mirror.dart`: the capture mirror's consumer on its own entry point, deliberately separate from the `miniav_web.dart` barrel. That barrel is a Flutter web plugin and pulls `package:flutter` in with it, while this path is meant to be drained from a worker whose payload dart2js compiles with no Flutter at all; Dart's import graph is per-library, so this one costs only `dart:typed_data`.
## 0.7.2

- released 08/13/26 - MR
## 0.7.1

- Version bump to keep the miniav 0.7.1 family aligned. No functional change in
  this package; the 0.7.1 fixes are Windows-native and do not apply to the web
  implementation.

## 0.7.0

- Implements the new `setIOSAppGroup` interface member (throws
  `UnsupportedError` — iOS only).

## 0.6.0

## 0.5.11

## 0.5.10

## 0.5.9

- override `releaseBufferSync()` as a no-op (web requires no explicit buffer
  release; avoids the default delegation allocating a `Future` on web).

## 0.5.8

- fix audio buffer allocations and leak issue
## 0.5.7

- Fix logger noisiness
## 0.5.6

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
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

- fixed black rendering on chrome

## 0.4.4

## 0.4.3

## 0.4.1

- fix issue with num frames not being reported for audio_inputs

## 1.0.0

- Initial version.
