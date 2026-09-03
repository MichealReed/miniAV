# miniav_platform_interface CHANGELOG

## 0.7.4

- Increment downstream deps
## 0.7.3

- New `MiniAVBufferContentType.gpuWebVideoFrame`: a WebCodecs `VideoFrame` carried in `nativeHandles[0]` rather than as an integer address, with no CPU planes - producing them would be exactly the readback the type exists to avoid. The frame MUST be released via `releaseBuffer`, which closes it: a `VideoFrame` pins a capture surface and a `MediaStreamTrackProcessor` whose frames are not closed simply stops producing once its queue fills, with no error and no event.

- New `openCaptureMirror` / `closeCaptureMirror` on the audio-input interface, plus `MiniAVCaptureMirrorHandle` - where a capture mirror lives, in a form that can cross a thread. Null where the platform has no such thing, so this is a capability question and not an error.

## 0.7.2

- released 08/13/26 - MR
## 0.7.1

- Version bump so the family can depend on miniav_ffi 0.7.1, which fixes a
  Windows use-after-free of the Media Foundation source-reader callback and
  makes COM/MF initialisation process-lifetime instead of per-FFI-call. No API
  change in this package.

## 0.7.0

- Documented the GPU buffer handoff contract on the types that carry it:
  `MiniAVBufferContentType` is **the** CPU/GPU discriminator (`planes[0]` is
  non-null but empty on the GPU path), `MiniAVVideoBuffer.nativeHandles[0]`
  holds the Windows shared NT HANDLE as an `int` and is **owned and closed by
  miniav on buffer release**, and `MiniAVNativeFence` is **unimplemented** —
  every field is always its sentinel and must not be read as "GPU work done".

- `MiniScreenPlatformInterface.setIOSAppGroup(String)` — registers the App
  Group for iOS system-wide broadcast capture; default implementation throws
  `UnsupportedError` on platforms without it.

## 0.6.0

## 0.5.11

## 0.5.10

## 0.5.9

- add `releaseBufferSync()` to `MiniAVPlatformInterface` with a default
  implementation that delegates to `releaseBuffer()` (additive and
  non-breaking; backends with a genuinely synchronous release should override).

## 0.5.8

- fix audio buffer allocations and leak issue
## 0.5.7

- Fix logger noisiness
## 0.5.6

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- add setLogCallback default no-op
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

## 0.4.4

## 0.4.3

## 0.4.1

- fix issue with num frames not being reported for audio_inputs

## 1.0.0

- Initial version.
