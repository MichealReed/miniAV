# Changelog

## 0.6.3

- Version bump for the miniav_tools 0.6.3 family. No functional change in
  this package.

## 0.6.2

- Byte-stream demuxing (`DemuxerInput.byteStream`) frees its byte pipe only
  once the worker isolate has exited. `close()` freed it as soon as the worker
  was closed, possibly while the worker was still inside a read, and an open
  that timed out on a stalled stream leaked it whenever the worker had not
  answered within 2 seconds. `close()` now waits up to 2 seconds for the exit,
  and a pipe whose worker never exits is leaked rather than freed under it.

## 0.6.1

- Requires spawn ^0.1.2.

## 0.6.0

- D3D11 encoder: no unbounded waits, and no frame encoded from an unfinished
  copy. A producer that never released its texture's keyed mutex hung the encode
  call and the isolate waiting on it, and a frame was encoded whether or not its
  copy had finished. Each wait is now bounded at 100 ms. A frame that misses one
  is dropped and the encoder re-sends its last accepted frame in its place, so
  every `encode` call still submits exactly one frame; before any frame has been
  accepted, `encode` throws `CodecRuntimeException`.
  - Shim ABI 22: `FfmpegShim.d3d11CopyResource` returns 0 (copied), 1 (dropped)
    or -1 (bad argument), and the BGRA→NV12 conversion returns
    `FfmpegShim.kVpSourceBusy` or `FfmpegShim.kVpBltIncomplete` for a dropped
    frame.
- `FfmpegD3d11HwEncoder` implements `FrameRepeatingEncoder`: `repeatLastFrame`
  re-sends the encoder's own copy of the last accepted frame under a new
  timestamp, instead of reading the producer's texture again when it may already
  hold the next picture.
- Video encoders (software, hardware, NVENC and D3D11) no longer lose a frame
  when `avcodec_send_frame` returns `EAGAIN`. The frame was never encoded, so a
  caller pairing packets with frames in order matched every later packet to the
  wrong frame.
- New `Ffmpeg.avFrameRef` binding (`av_frame_ref`).
- Requires miniav_platform_interface 0.8.0 and
  miniav_tools_platform_interface 0.6.0.

## 0.5.9

- Requires spawn ^0.1.1: native transfers actually transfer, and a web message
  the worker cannot deserialize is reported instead of vanishing.

## 0.5.8

- Increment downstream deps

## 0.5.7

- Version alignment with the miniav_tools 0.5.7 family release.

## 0.5.6

- Host the container demuxer on spawn, so it runs on an isolate natively and a
  Web Worker on web through one API.

## 0.5.5

- `IsolateDemuxer` runs on `package:spawn` (a new dependency) instead of
  hand-written isolate code; behaviour is unchanged.
- FFmpeg log forwarding uses a Dart native port instead of a `NativeCallable`
  (shim ABI 21, new exports `miniav_shim_init_dart_api` /
  `miniav_shim_set_log_port`; the shim vendors the Dart SDK's BSD-licensed
  dynamic-linking API). FFmpeg's log callback is process-wide, so a log line
  after the registering isolate exited aborted the process.
  `setFfmpegLogCallback` gains an optional `level:`; the last isolate to
  register receives the lines.
- `FfmpegDemuxer` fills `VideoTrackInfo.rotationDegrees` from the container's
  display matrix (shim ABI 20); it reported 0, so portrait phone videos played
  sideways. Only clockwise quarter turns are reported, as in the first-party MP4
  demuxer; decoded frames keep their coded orientation for the consumer to turn.
- `FfmpegMuxer` writes `VideoTrackInfo.rotationDegrees` as a display matrix, so
  rotation survives a remux; a rotation that is not a multiple of 90 throws.
- `hook/build.dart` registers the shim sources, so an edited shim rebuilds; a
  stale shim's old ABI disabled the whole backend.

## 0.5.4

- Internal dependencies are caret ranges instead of exact pins, which made each
  patch release unsatisfiable next to already-published packages.
- Republished: 0.5.3 pinned `miniav_tools_platform_interface: 0.5.2` exactly and
  could not resolve next to packages needing 0.5.3.

## 0.5.3

- Declares the `PlatformEncoder` GPU-input capabilities: `FfmpegD3d11HwEncoder`
  reports `supportsD3d11SharedHandleInput` and `supportsD3d11TextureInput`, and
  CPU-fed encoders report neither. Behaviour is unchanged.
- Demuxing and live-stream muxing for playback (shim ABI 15):
  - `FfmpegDemuxer` reads files, bytes and live byte streams into
    `EncodedPacket`s with microsecond timestamps, with `durationUs`,
    `isSeekable` and keyframe `seek`. `createDemuxer` returns an
    `IsolateDemuxer` by default because reading a live stream blocks;
    `backendOptions {'sw_isolate': '0'}` runs in-isolate (files and bytes only).
  - A live `Stream<List<int>>` is fed through a blocking byte pipe with
    backpressure; closing it unblocks a stalled read.
  - In-memory input is seekable, so an MP4 with `moov` at the end opens from
    bytes. `FfmpegMuxer` supports `BytesMuxerOutput` (seekable, so faststart
    works) and `CallbackMuxerOutput` (streamable containers).
  - `Container.fmp4` writes real fragmented MP4 (init segment up front,
    live-streamable), with an optional `frag_duration`.
  - A live stream that stalls while opening raises `CodecInitException` after 15
    s (`backendOptions {'open_timeout_ms'}`) instead of hanging `open()`.
- Decoding for playback (shim ABI 14):
  - `FfmpegAudioDecoder`: AAC, Opus, MP3, Vorbis and FLAC to interleaved f32.
  - `DecoderConfig.extraData` and `AudioDecoderConfig.extraData` reach the
    codec; they were ignored.
  - `IsolateVideoDecoder` / `IsolateAudioDecoder` decode on a worker isolate and
    are returned by default (`backendOptions {'sw_isolate': '0'}` keeps the
    in-isolate path).
  - `FfmpegSoftwareDecoder` timestamps were scaled wrongly and are now passed
    through.

## 0.5.2

- CPU-fed hardware encoders run on a worker isolate, fixing a recording freeze
  on the CPU path. `IsolateSoftwareEncoder.open` gains `hwVendorOrder` /
  `requireHardware` and tries each hardware vendor before software.
  - QSV and Media Foundation open: they need an MTA COM apartment, which
    Flutter's UI isolate is not.
  - Opening and encoding no longer block the UI isolate; frames cross as
    `TransferableTypedData` (~1 ms at 720p).
  - `FfmpegBackend.createEncoder` uses it after the zero-copy path, with the
    vendor order taken from the capture adapter (new `hwVendorOrderForDevice`;
    on AMD, Media Foundation before AMF, which can encode black).
    `IsolateSoftwareEncoder` reports its real encoder's `acceptsYuv420pPlanes`
    and an `activeEncoderDescription`; `sw_isolate: '0'` keeps the in-isolate
    path.

## 0.5.1

- `FfmpegD3d11HwEncoder.open` with an injected `ID3D11Device` tries the device's
  own vendor first (AMD → AMF, Intel → QSV, NVIDIA → NVENC, then Media
  Foundation) instead of always starting with NVENC. `vendorOrder` is optional;
  passing it still overrides.

## 0.5.0

- Software encoding no longer freezes the app: the software fallback is
  `IsolateSoftwareEncoder`, which runs `FfmpegSoftwareEncoder` on a worker
  isolate. `backendOptions: {'sw_isolate': '0'}` returns the in-isolate encoder.
- AMF (AMD) D3D11 zero-copy always converts to NV12 first: BGRA input was
  rejected, or silently encoded black, on real AMD hardware.
- The NV12 frame pool tries progressively simpler bind flags (AMD rejects some
  combinations). If none works, the vendor is reported unavailable and encoding
  falls back to the next vendor or the CPU, instead of producing black video.

## 0.4.10

- `FfmpegSoftwareEncoder` accepts planar YUV420P frames (`FrameSource.yuv420p`,
  `acceptsYuv420pPlanes`) without converting them, so the recorder can convert
  on the GPU. Hardware encoders keep their RGBA/NV12 input.

## 0.4.9

- Licensing: the auto-downloaded FFmpeg is the BtbN LGPL build
  (`kFfmpegLicense`) instead of GPL, so it is safe for proprietary dynamic
  linking. The cache directory is per licence, which forces a fresh download.
- **Behaviour change:** without libx264/libx265, software H.264 comes from
  `libopenh264` and Windows Media Foundation (`h264_mf`, now usable as a CPU
  fallback). There is no software HEVC: a HEVC or over-4096 px request with no
  hardware encoder falls back to H.264 at no more than 4096 px. AV1 (SVT-AV1)
  and VP9 (libvpx) remain.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Importing the package never registered the backend: call
  `registerFfmpegBackend()` explicitly (idempotent). `miniav_recorder` does so
  in `warmup()` and `start()`.

## 0.4.6

- Diagnostics go through a levelled log hook, `setFfmpegToolsLogCallback` /
  `setFfmpegToolsLogLevel` (default sink `print`), instead of `stderr`, which
  crashed Windows GUI apps without a console.
- README documents FFmpeg warmup (`ensureFFmpegLoaded`, `MiniAVTools.warmup()`,
  `FfmpegDownloader.ensureFfmpeg`), the real cache paths and the log hook.

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

## 0.2.6

- Fix a compilation error introduced in 0.2.5.

## 0.2.5

- `FfmpegShim.setFfmpegLogCallback` no longer throws `FormatException` on FFmpeg
  log messages that are not valid UTF-8.

## 0.2.4

- `FfmpegShim.tryLoad()` no longer caches a failure when called before FFmpeg is
  loaded, which broke the audio encoder when
  `Recorder.setLogLevel`/`setLogCallback` was called early.

## 0.2.3

- FFmpeg log forwarding: `FfmpegShim.setFfmpegLogLevel` and
  `setFfmpegLogCallback` (shim ABI 8); `FfmpegShim` is exported.
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

## 0.1.0

- Initial release. FFmpeg-backed encoder, decoder, muxer and demuxer registered
  against `miniav_tools_platform_interface`.
- Software encode for H.264 / HEVC / VP9 / VP8 / AV1 / MJPEG / ProRes via
  libavcodec.
- Stage A hardware encode (CPU frame in, encoded packet out) using NVENC / AMF /
  QSV / VideoToolbox / MediaFoundation / V4L2 M2M.
- Stage B zero-copy D3D11 encode on Windows from an `ID3D11Texture2D` NT shared
  handle, with no PCIe transfer or colour conversion.
  `FfmpegD3d11HwEncoder.openWith(cfg, vendor, existingD3d11Device,
  sourceTextureFormat)` takes the caller's `ID3D11Device*` (sharing needs the
  same adapter) and a `bgra` (default) or `rgba` source format.
- MP4 / Matroska / MPEG-TS muxer with byte-buffer, file and streaming callback
  outputs, and fragmenting for low-latency streaming.
- Auto-download of FFmpeg shared libraries (BtbN GPL builds) on first run; set
  `MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD=1` to opt out.
