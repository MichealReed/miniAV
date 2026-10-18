# Changelog

## 0.6.1

- Requires spawn ^0.1.2.

## 0.6.0

- Video frames are timed by when they were captured, not when they reached the
  recorder, so uneven delivery no longer makes playback uneven. A source whose
  clock does not keep real time falls back to arrival time (logged once).
- A frame captured before the previous one is dropped and counted (`ooo=` in the
  stats line) instead of being encoded after a newer picture.
- Each packet is written with its own frame's timestamp. Hardware encoders
  return packets two to four frames late, so video ran 67–133 ms behind audio at
  30 fps and the packets drained at stop all carried the stop time. Frames an
  encoder never answers are counted (`enc_lost=`).
- Duplicate frames no longer show an older picture after a newer one. Encoders
  that implement `FrameRepeatingEncoder` (Media Foundation, FFmpeg D3D11) repeat
  their own copy of the last frame; where an encoder cannot, a
  constant-frame-rate gap on the pipelined zero-copy path is left unfilled.
- The stats line reports capture timing from the source's clock:
  `cap_dt=min..max` (steps between captured frames) and `lag<=` (worst delivery
  lag).
- A camera's mode is chosen by size, rate and format together: the closest size
  wins, an unrequested rate comes from the default mode, and NV12 beats YUY2
  beats other raw formats. On Windows an MJPEG-only mode is requested as NV12;
  elsewhere MJPEG modes are skipped.
- A camera delivering below 90% of its set rate for 10 s (typically a webcam in
  low light) logs a warning, and an info line once it recovers.
- Recording a camera's GPU frames with the Media Foundation encoder works; the
  first frame used to fault the GPU. Screen frames that need no scaling or
  effects take the same path and are converted from BGRA to NV12. Requires
  miniav_tools_codecs 0.7.8.
- Requires miniav 0.8.0 and the 0.6.0 miniav_tools packages
  (miniav_tools_codecs 0.8.0).

## 0.5.17

- `addScreen(captureCursor: true)` draws the mouse cursor into the recording
  (default false, as before). Honoured on Windows WGC (Windows 10 2004+), macOS
  ScreenCaptureKit and Linux PipeWire; DXGI cannot draw a cursor and on web the
  browser decides. Where a platform declines, recording continues without the
  cursor and logs it once.

## 0.5.16

- Raise the spawn constraint to ^0.1.1 — native transfer now actually transfers,
  and a web message the worker cannot deserialize is reported instead of
  vanishing.

## 0.5.15

- The container writer runs on a worker, so `stop()` no longer freezes the
  calling isolate while the MP4 index is written. Only the first-party
  MP4/M4A/WAV writers move; FFmpeg containers (MKV/WebM/TS) still finish in
  process, as does everything when no worker can start (logged).
- New `Recorder.finalizeProgress`: a stream of `RecorderFinalizeProgress` naming
  the phase `stop()` is in (stopping capture, draining, flushing, writing the
  index, closing, done) with elapsed time.
- `stop()` logs a per-phase timing breakdown and warns when shutdown ran long
  enough to drop frames.
- The codec configuration record reaches the container with the first packet, so
  encoders that publish it late (Intel Quick Sync) can use the first-party MP4
  writer instead of falling back to FFmpeg. Requires `miniav_tools_codecs`
  0.7.6.
- A track build that throws part way no longer leaks the native objects it
  already created.
- `Recorder.updateTrackConfig` returns `Future<void>` (the container may be on a
  worker); calling it as a statement is unaffected.
- The video encoder log line includes the encoder's D3D11 device and whether it
  matches the capture's.

## 0.5.14

- A frozen capture is detected: the watchdog also watches frames from the
  source, not just encoded packets, which the idle-frame duplicator kept
  producing over a dead capture.
- After 3 s of source silence the watchdog asks the platform whether the display
  is still attached and the same size, cutting the frozen stretch after a mode
  change or unplug from ten seconds to about three. The 10 s window remains the
  fallback and doubles, up to a minute, after each fruitless re-acquire, so a
  still desktop is not churned.
- An outage is timed from when the capture went quiet, not from when the
  watchdog declared it.
- Microphone, loopback, camera and both inputs of a mixed-audio track report
  device loss and re-acquire, like the screen. A lost audio endpoint used to go
  silent while the recording reported success.
- `Recorder.captureStatus` and `Recorder.captureIssues` report one entry per
  capture source rather than per track.
- New `lossPolicy` and `reacquireLimit` on `addCamera`, `addMic`, `addLoopback`
  and `addMixedAudio`. `VideoCaptureLossPolicy` is now `CaptureLossPolicy`; the
  old name still works.
- A lost display is found again by name, since Windows issues new display
  handles on every topology change. A screen track without an explicit display
  no longer re-picks a possibly different default display when it rebuilds.
- An absent capture target is reported once, then rarely, as the new
  `CaptureTargetUnavailable` (also thrown by `start()`), instead of a stack
  trace every few seconds.
- A stage rebuild checks its target is present before re-acquiring the GPU
  device, and refuses a target reporting 0x0.

## 0.5.13

- Increment downstream deps

## 0.5.12

- Screen capture survives losing its target (Win+P, dock/undock, lock, RDP,
  display mode change): it is re-acquired in place, same file and track, with a
  frozen frame across the gap. A lost display used to go unnoticed and the
  recording reported success.
- A watchdog declares a loss when a source stops producing and the platform says
  nothing (a GPU device reset), and rebuilds the device, processor, encoder and
  capture in place. A rebuild that would not match the container is refused.
- New `VideoCaptureLossPolicy` and `reacquireLimit` on `addScreen` (default:
  keep re-acquiring), `Recorder.captureStatus` and `Recorder.captureHealthy` for
  live health, and `Recorder.captureIssues` at stop. A window target is never
  re-acquired and a different display is never substituted.
- A duplicate frame whose encode fails retires its source instead of retrying
  forever, audio encodes are chained so a gap fill cannot overtake live audio,
  and container timing repairs are logged at stop.

## 0.5.11

- Log the encoder's D3D11 device alongside the capture context's, so a device
  mismatch (every GPU frame refused) is visible.

## 0.5.10

- released 08/13/26 - MR

## 0.5.9

- Requires `miniav_tools_codecs` ^0.7.0 (streamed MP3 decode fix).
- Audio-only `.wav` (PCM) and `.aac`/ADTS file sinks record, through the
  first-party streaming muxers. `.wav` was impossible before and `.aac` got an
  M4A written into it.
- New `firstPartyMuxerCanWrite(audioTracks:)`, since WAV and ADTS hold exactly
  one audio track.
- Audio tracks pass the encoder's extra data to the muxer, so Opus keeps its
  pre-skip; a synthesised header played every sample ~6.5 ms late.
- `containerForExtension` maps `.aac`/`.adts` to ADTS, and
  `containerForTrackMix` answers WAV for audio-only PCM.
- The Media Foundation encoder's imported textures are released when the
  producer's frame size changes or the GPU processor's output ring is torn down;
  a 4K screen recording held ~135 MB of dead VRAM. New `EncoderImportCache`
  holds the policy, and `EncoderImportCache.noteFrame(buffer)` replaces
  `noteProducerSize`.
- Fixed a permanent gap in `cfrOutput` + `duplicate` recordings after the import
  cache was dropped, and the `black` idle policy now reports a torn-down ring
  too.

## 0.5.8

- Audio negotiation is container-aware: MP4/M4A recordings keep the OS AAC
  encoder, and an impossible codec/container pairing fails at `start()` with a
  `CodecInitException` naming both, before any device opens.
- MP4/M4A file sinks and clips use the first-party ISO-BMFF writer when the
  codecs allow. It streams to disk, so long recordings no longer sit in RAM; if
  it declines, the cause is logged and FFmpeg is used.
- **Behaviour change:** the default container for video+audio is MP4, not MKV,
  when both codecs are known and first-party writable. Unstated codecs still get
  MKV.
- Opus is accepted alongside AAC for first-party MP4/M4A clips.
- `ClipBuffer.saveClip` registers the backends it needs instead of relying on a
  `Recorder` having run first.
- A first frame that fails to encode no longer leaves a CFR/idle slot the pacer
  thinks is filled.

## 0.5.7

- Idle/CFR duplicate frames ask the encoder to repeat its last frame instead of
  re-encoding the GPU processor's output texture, which produced a stream of
  encode errors on direct BGRA passthrough. Encoders without that capability use
  the old path.

## 0.5.6

- Muxing prefers the first-party writer: clips and file sinks use it for MP4/M4A
  with H.264/HEVC/AV1 + AAC. This fixes clip saving, broken since AAC moved to
  the OS encoder in 0.5.3 ("Audio tracks must be bound to a
  FfmpegAudioEncoder"). MKV and everything else still go to FFmpeg.
- The clip path no longer requires a `muxerFactory` and no longer limits the
  first-party writer to AV1.
- New `firstPartyMuxerCanWrite()` in `container_utils.dart`.

## 0.5.5

- Internal dependencies use caret ranges instead of exact pins, so publishing
  one package no longer makes its siblings unsatisfiable.

## 0.5.4

- Picks up `miniav_tools_codecs` 0.6.2 (0.6.1 could not build its native assets
  downstream). No recorder code change.
- README: documents the two GPU-resident frame shapes for zero-copy and the
  encoder capability each needs.

## 0.5.3

- The FFmpeg-free path is the default: on Windows H.264/HEVC go to the OS
  hardware encoder (NVENC/AMF/QSV) and AAC to the OS codec, with no per-app
  registration. FFmpeg stays registered and wins where it is better; use
  `BackendPreference.pinned` / `.excluded` to choose.
- Encoder negotiation only considers backends that accept the frame kind the
  recorder will hand over, so a handle-only encoder can no longer win and force
  a CPU read-back.
- Screen zero-copy is gated on encoder capabilities
  (`supportsD3d11SharedHandleInput`, `supportsD3d11TextureInput`) instead of on
  `FfmpegD3d11HwEncoder`, which silently forced other GPU encoders onto CPU
  read-back.
- Warn at GPU init when the loaded minigpu binary predates the event-drain fix
  (every GPU wait then costs ~15.6 ms, which shows up as stutter); exposed as
  `Recorder.gpuDrainFixPresent`.
- The screen effect chain synchronises once per frame instead of once per
  effect. Requires `minigpu: ^1.5.9`.

## 0.5.2

- Fixed the regular stutter in screen recordings: the fps throttle no longer
  thins a source within ~15% of the target rate (e.g. 31.4 fps capture for a 30
  fps target). It engages only when the source clearly outruns the target, thins
  evenly, and logs when it engages and releases. The policy lives in the new
  `FramePacer`.
- New `cfrOutput` on screen sources (`addScreen(cfrOutput: ...)`, default off):
  output timestamps sit exactly on the frame-rate grid, missed slots are filled
  with duplicates and surplus frames are dropped.
- The video stats line reports `dup=N` (duplicate frames) when non-zero.
- Fixed scaling and effects being silently dropped on the CPU-encode path, most
  visibly with window capture: capture uses GPU output whenever a processor
  runs, and a fallback to a CPU-input encoder keeps the processor (reading back
  on the CPU) instead of discarding it.
- Screen recording no longer freezes the app on the CPU-fed encode path, and can
  use QSV/Media Foundation hardware encode there, by running the encoder on a
  worker isolate. Requires `miniav_tools_ffmpeg` 0.5.2.

## 0.5.1

- New `Recorder.preferCaptureAdapter()` (Windows): binds the process's GPU
  context to the adapter driving the primary display, so capture, processing and
  hardware encode share one adapter. This enables iGPU encoders (AMF/QSV) on
  hybrid systems. Call it at startup before any minigpu use; all minigpu compute
  then runs on that adapter (`MGPU_ADAPTER_NAME` overrides). Requires minigpu
  1.5.6.

## 0.5.0

- Less stutter when another workload saturates the GPU:
  - The video stats line shows per-stage timing: `gpu=avg/max ms` and
    `enc=avg/max ms`.
  - Adaptive GPU-pressure throttle (`addScreen(adaptiveGpuThrottle: true)`,
    default on): sustained GPU overrun steps the live capture rate down by a
    power of two (`adapt=÷N`) while duplicates keep the output at the target
    rate, and restores it when pressure clears.
  - With no scaling or effects, the zero-copy path hands the capture's shared
    handle straight to the encoder, which copies it itself: no shader work per
    frame.
  - With scaling or effects, GPU processing of the next frame overlaps encoding
    of the current one (`GpuScreenProcessor.sharedRingDepth`).
- Video `TrackInfo` carries the encoder's codec extradata (SPS/PPS), so the
  isolate-hosted software encoder (miniav_tools_ffmpeg 0.5.0) can be muxed
  without freezing the app.

## 0.4.10

- Fewer dropped frames:
  - A bounded frame queue (depth 3, oldest dropped) replaces the depth-1 gate,
    so a brief encode overrun no longer drops the next frame.
  - The stats line separates `thr_drop=` (by design) from `busy_drop=`
    (back-pressure).
  - The CPU read-back path reuses its buffer instead of allocating ~8 MB per
    1080p frame, and mixed audio recycles its PCM buffers.
  - Frames are released with `MiniAV.releaseBufferSync()` and carry their
    capture timestamp, keeping PTS spacing even after an encoder stall.
  - Muxer writes go through a bounded per-sink queue (`BoundedWriteQueue`)
    instead of blocking the next encode; it is drained before the trailer is
    written.
  - New `GpuYuv420Converter` converts RGBA to YUV420P on the GPU for the
    software encoder: byte-identical to the CPU conversion, with ~2.7× less
    read-back.
  - `ClipBuffer.saveClip` selects its window in one bounded pass
    (`selectClipSlice`), shortening the stall on the live recording.
  - The zero-copy path awaits minigpu's async shared-output copy instead of
    busy-polling. Requires `minigpu: ^1.5.3`.

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Add `Recorder.warmup()`: registers the FFmpeg backend, then runs
  `MiniAVTools.warmup()`, so the FFmpeg download happens before the first
  recording.

## 0.4.6

- Dart-side logging no longer writes to `stderr`, which crashed console-less
  Windows GUI apps; every message goes through `Recorder.setLogCallback`
  (default sink: `print`).
- `Recorder.setLogCallback` / `setLogLevel` also route the `miniav_tools_ffmpeg`
  Dart layer, as `RecorderLogSource.ffmpeg`.

## 0.4.5

- Add `Recorder.sharedGpu`: the process-global `Minigpu` instance after
  `ensureSharedGpu()` (or `null`), so host code can reuse the same device.
- Export `GpuScreenProcessor`, for custom GPU preview pipelines with
  `minigpu_view`.

## 0.4.4

- Fix recorder loopback drift.

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

- Add `RecorderLogSource.minigpu`: native minigpu/Dawn log lines go through the
  recorder's log callback. New `Recorder.minigpuLevelFor`.

## 0.2.7

- Fix a FormatException on non-UTF-8 bytes in MiniAV log messages.
- Increment minigpu to 1.4.4

## 0.2.6

- Require `miniav_tools_ffmpeg` ^0.2.6 (fixes a compile error in 0.2.5).

## 0.2.5

- Require `miniav_tools_ffmpeg` ^0.2.5 (FFmpeg log messages with non-UTF-8 bytes
  no longer throw).
- Fix loopback/mixed audio crackles: chunks that arrived while a packet was
  being written were dropped; they now queue in order.

## 0.2.4

- Require `miniav_tools_ffmpeg` ^0.2.4 (the audio encoder failed when the log
  level or callback was set before FFmpeg loaded).

## 0.2.3

- Add `Recorder.setLogLevel` and `Recorder.setLogCallback`, with
  `RecorderLogLevel` and `RecorderLogSource`: all native logs (MiniAV and
  FFmpeg) and the recorder's own go through one Dart callback.

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

- Initial release.
- Multi-source A/V recorder built on `miniav` and `miniav_tools`.
- Synchronised capture from screen, camera, microphone, and loopback audio.
- FFmpeg-backed muxing to MP4/MKV files and chunked streams via
  `miniav_tools_ffmpeg`.
- Zero-copy GPU screen-capture path on Windows via shared D3D11 device.
