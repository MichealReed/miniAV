# Changelog

## 0.6.1

- Requires spawn ^0.1.2.

## 0.6.0

- New `FrameRepeatingEncoder`, for a video encoder that can re-submit the last
  frame it accepted under a new timestamp. Re-submitting the producer's surface
  could read the next picture, so the duplicate showed newer content than the
  frame after it and playback jumped backwards. `repeatLastFrame` returns a
  packet as `encode` does; an encoder whose packets do not carry their frame's
  timestamp throws when it has nothing to repeat, so a caller pairing packets
  with frames stays in step.
- `FrameSource.miniavBuffer` takes an optional `timestampUs` that replaces the
  buffer's own, so a buffer submitted twice carries its own time.
- Requires miniav_platform_interface 0.8.0.

## 0.5.8

- Requires spawn ^0.1.1: native transfers actually transfer, and a web message
  the worker cannot deserialize is reported instead of vanishing.

## 0.5.7

- Increment downstream deps

## 0.5.6

- Exports the audio-ring cursor primitives, so a ring with its own layout
  (miniAV's capture mirror) can reuse their memory ordering. `gpuWebVideoFrame`
  buffers map to the `webVideoFrame` frame source kind.

## 0.5.5

- New `SharedAudioRing`: a lock-free single-producer/single-consumer ring of
  interleaved f32 PCM in shared memory, so decoded audio reaches an audio thread
  without passing through the main thread. Adds the demux wire protocol shared
  by worker-hosted demuxers.

## 0.5.4

- Documentation fix only; no API or behaviour change.

## 0.5.3

- `PlatformEncoder` gains `supportsD3d11SharedHandleInput` (a
  `FrameSource.miniavBuffer` whose `nativeHandles[0]` is a D3D11 shared NT
  handle) and `supportsD3d11TextureInput` (a `D3D11TextureFrameSource` on the
  producer's own device), both `false` by default, so the recorder picks its
  zero-copy path by capability. Classes that `implements PlatformEncoder` must
  declare both.
- Audio decoding: `PlatformAudioDecoder`, `DecodedAudio` (interleaved f32),
  `AudioDecoderConfig` and `MiniAVToolsBackend.createAudioDecoder` (default
  `null`, so existing backends are unaffected).
- Demuxer streams: `DemuxerInput.byteStream(Stream<List<int>>)`
  (`StreamDemuxerInput`) for live or progressive containers, plus
  `PlatformDemuxer.durationUs` (nullable) and `isSeekable`, both with defaults.
  A demuxed packet's `trackIndex` indexes into `tracks`.
- `DecodedFrame.webVideoFrame` (`Object?`, default `null`): a browser
  `VideoFrame` ready to present, from WebCodecs decoding on web. Native classes
  that `implements DecodedFrame` must return `null`.

## 0.5.2

## 0.5.1

## 0.5.0

- Version bump to keep the miniav_tools family in lockstep; no changes in this
  package.

## 0.4.10

- New `CpuExecutor` runs CPU-bound work off the main isolate: on a long-lived
  background isolate natively, inline on web, without `dart:isolate` reaching
  web builds.
- New `FrameSource.yuv420p`: a planar YUV420P (I420) frame source, so a GPU
  colour conversion can feed an encoder directly.
- New `PlatformEncoder.acceptsYuv420pPlanes` (default `false`) for encoders that
  take YUV420P planes natively.

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Increment to keep in step with others.

## 0.4.6

- Increment to keep in step with others.

## 0.4.5

- Version bump for coordinated release with `miniav_recorder` 0.4.5.

## 0.4.4

- fixing recorder loopback drift

## 0.4.3

- audio data issue, increment miniav

## 0.4.2

- fix timing issue

## 0.4.1

- fix audio timing, add frame duplication

## 0.4.0

- fix frame rate scheduling

## 0.3.12

- fused shader cache fix

## 0.3.11

- Use GPU until we cant.

## 0.3.9

- AMF Fix, fix unknown audio error

## 0.3.8

- Fix vendor Order

## 0.3.7

- fix NV12 path

## 0.3.6

- fix cpu path

## 0.3.5

- fix recorder sync drift

## 0.3.4

- attempt fix resolution issue

## 0.3.3

- fix precheck

## 0.3.2

- fix property

## 0.3.1

- fix scaling crazy, attempt fix other HW encoders

## 0.3.0

- fix recorder logging, Tier A path, deps to 1.5.0

## 0.2.21

- increments minigpu to 1.4.15

## 0.2.20

- increments minigpu to 1.4.14

## 0.2.19

- increments minigpu to 1.4.12

## 0.2.18

- increments minigpu to 1.4.11

## 0.2.17

- increments minigpu to 1.4.9

## 0.2.16

- increments minigpu to 1.4.8, hopefully fix cpu fallback

## 0.2.15

- increments minigpu to 1.4.7

## 0.2.14

- fixes unicode, increments minigpu to 1.4.7

## 0.2.12

- Increment minigpu to 1.4.6

## 0.2.11

## 0.2.9

## 0.2.8

- Add `RecorderLogSource.minigpu`, routing native minigpu/Dawn log lines through
  the unified `Recorder` log callback, and the public `Recorder.minigpuLevelFor`
  helper.

## 0.2.7

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- Increment minigpu to 1.4.4

## 0.2.5

## 0.2.4

## 0.2.3

- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all
  native logs (MiniAV + FFmpeg) through a single Dart callback

## 0.2.1

- fixes dawn find issue

## 0.2.0

- add more quality control, fix ffmpeg usage issue

## 0.1.9

- fixes timestamp issues

## 0.1.8

- recorder scaling, warmup feature

## 0.1.7

- adds transform effects

## 0.1.6

- adds clip buffer

## 0.1.5

- fix loopback issue

## 0.1.4

- fix loopback issue, add tests

## 0.1.3

- update with fixes

## 0.1.2

- recorder sync and multi files

## 0.1.1

- updated to latest miniav/minigpu deps

## 0.1.0 — 2026-05-02

- Initial release. Defines `MiniAVToolsPlatform`, `MiniAVToolsBackend`,
  `EncoderConfig`, `DecoderConfig`, `MuxerConfig`, `DemuxerConfig`,
  `EncodedPacket`, `FrameSource`, codec/container enums, and exception types.
