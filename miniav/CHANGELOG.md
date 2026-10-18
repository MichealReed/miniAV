# miniav CHANGELOG

## 0.8.1-WIP

## 0.8.0

- `MiniScreenContext` exposes `setCaptureFrameRate`, `setContentHint`,
  `fallbackToCpuDelivery` and `cpuDeliverySurface`. The web backend
  implements them; native backends report them as unsupported.
- Screen frames from Windows Desktop Duplication carry `damage`: the
  rectangles that changed since the previous frame.
- Windows camera frames carry `color`, the YUV matrix and range of the
  picture, so a viewer can convert them to the right RGB. Other platforms
  report `null` for now.

## 0.7.4

- Increment downstream deps

## 0.7.3

- New `openCaptureMirror` / `closeCaptureMirror` on the audio-input facade hand
  captured audio to another thread instead of `startCapture`'s callback; closing
  the mirror resumes normal delivery. They return null where unsupported.

## 0.7.2

- released 08/13/26 - MR

## 0.7.1

- Picks up miniav_ffi 0.7.1: destroying a Windows camera context no longer frees
  the Media Foundation callback while MF still holds it, and COM/MF
  initialisation is process-wide instead of per call. No API change in this
  package.

## 0.7.0

### GPU buffer handoff contract (Windows)

- **Behaviour change:** miniav closes the shared NT handle of a GPU frame when
  the buffer is released; it leaked one kernel handle per captured GPU frame.
  Finish importing the handle (`OpenSharedResource1`, minigpu
  `importVideoFrame`, …) before `releaseBuffer` / `releaseBufferSync`, do not
  `CloseHandle` it yourself, and release every buffer, including ones you skip.
- README fix: the GPU handle is in `nativeHandles[0]`, not `planes[0]`. On the
  GPU path `planes[0]` is an empty `Uint8List`, so use `buffer.contentType` to
  tell CPU frames from GPU frames.
- `MiniAVNativeFence` is documented as unimplemented: no backend fills it. The
  Windows backends wait up to 16 ms for the GPU copy and then hand the frame
  over anyway, so a texture may not be finished.
- `MiniScreen.setIOSAppGroup(String)` registers the App Group shared with the
  iOS Broadcast Upload Extension; call it before configuring the
  `system_screen_broadcast` display.

## 0.6.0

## 0.5.11

## 0.5.10

## 0.5.9

- Add `MiniAV.releaseBufferSync()`, a synchronous variant of `releaseBuffer()`
  for hot paths such as a per-frame capture callback.

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

## 0.4.1

- fix issue with num frames not being reported for audio_inputs

## 1.0.0

- Initial version.
