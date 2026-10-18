# miniav_platform_interface CHANGELOG

## 0.8.0

- Screen frames can say which parts changed: `MiniAVVideoBuffer.damage`
  (`MiniAVVideoDamage`, `MiniAVDamageRect`) holds a frame's changed rectangles
  when the backend can certify them. Partial damage is relative only to the
  frame delivered just before it in the same `sourceEpoch`; a gap in
  `generation`, a size change, `fullFrame` or `null` means the whole frame.
- `MiniScreenContextPlatformInterface` gains four members. Their defaults report
  "unsupported" and leave the capture alone:
  - `setCaptureFrameRate(fps)` changes the selected source's rate without
    opening the picker again.
  - `setContentHint(hint)` sets the selected video track's content hint.
  - `fallbackToCpuDelivery()` switches a live capture to CPU frames without
    reacquiring its source.
  - `cpuDeliverySurface` is the surface CPU delivery draws into, when the
    backend can expose it without a copy. The context keeps ownership.
- Video frames can say how their YUV is coded: `MiniAVVideoBuffer.color`
  (`MiniAVVideoColor`: a `MiniAVYuvMatrix` of BT.601, BT.709 or BT.2020,
  and full or limited range). It is `null` when the backend does not say:
  RGB formats, screen capture, and for now every camera backend except
  Windows.

## 0.7.4

- Increment downstream deps

## 0.7.3

- New `MiniAVBufferContentType.gpuWebVideoFrame`: a WebCodecs `VideoFrame` in
  `nativeHandles[0]`, with no CPU planes. Release it with `releaseBuffer`, which
  closes it; unclosed frames make the browser's track processor stop producing,
  with no error.
- New `openCaptureMirror` / `closeCaptureMirror` on the audio-input interface,
  with `MiniAVCaptureMirrorHandle` describing where a capture mirror lives in a
  form that can cross threads. Null where the platform has none.

## 0.7.2

- released 08/13/26 - MR

## 0.7.1

- Version bump so the family can depend on miniav_ffi 0.7.1 (Windows camera and
  COM/MF fixes). No API change in this package.

## 0.7.0

- The GPU buffer handoff contract is documented on its types:
  `MiniAVBufferContentType` tells CPU from GPU frames (`planes[0]` is empty on
  the GPU path); `MiniAVVideoBuffer.nativeHandles[0]` holds the Windows shared
  NT handle, which miniav closes on buffer release; and `MiniAVNativeFence` is
  unimplemented, its fields always holding their sentinel values.
- `MiniScreenPlatformInterface.setIOSAppGroup(String)` registers the App Group
  for iOS system-wide broadcast capture; the default throws `UnsupportedError`.

## 0.6.0

## 0.5.11

## 0.5.10

## 0.5.9

- Add `releaseBufferSync()` to `MiniAVPlatformInterface`, defaulting to
  `releaseBuffer()`; backends with a synchronous release should override it.

## 0.5.8

- fix audio buffer allocations and leak issue

## 0.5.7

- Fix logger noisiness

## 0.5.6

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- Add `setLogCallback` (a no-op by default) and `installStderrLogger` to route
  native MiniAV log lines to a Dart callback.

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
