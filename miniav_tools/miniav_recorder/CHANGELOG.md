# Changelog

## 0.5.7

- Idle/CFR duplicate frames now ask the encoder to repeat its last frame rather
  than re-encoding the GPU processor's `SharedOutputTexture`. The old approach
  failed whenever that texture was not part of the live path — notably direct
  BGRA passthrough (`gpuWork=false`), where nothing writes it — producing a
  steady stream of encode errors from a timer while live encoding was perfectly
  healthy. Falls back to the old path for encoders without the capability, and a
  declined repeat now leaves the slot unfilled instead of raising.

## 0.5.6

- **Muxing prefers the first-party writer.** `FfmpegMuxer` requires a live
  `AVCodecContext` per audio track to fill codecpar (`ch_layout` is not
  reachable from the Dart-side `AVCodecParameters` prefix), so it can only mux
  audio that FFmpeg itself encoded. Once AAC moved to the OS codec by default in
  0.5.3, that coupling broke clip saving outright: the temporary encoder opened
  purely to obtain an `FfmpegEncoderBridge` was no longer an FFmpeg one, the
  bridge map came back empty, and the muxer threw "Audio tracks must be bound to
  a FfmpegAudioEncoder". Both the clip path and the main file sink now use the
  first-party ISO-BMFF writer for MP4/M4A with H.264/HEVC/AV1 + AAC, which takes
  already-encoded packets and needs no encoder handle at all. Anything it does
  not cover -- MKV above all -- still goes to FFmpeg exactly as before.
- The clip path no longer requires a caller-supplied `muxerFactory`, and no
  longer restricts the first-party writer to AV1. That restriction was correct
  when the Dart writer only understood AV1; it now writes H.264/HEVC too
  (Annex-B to length-prefixed samples, plus the `avcC`/`hvcC` record), so the
  gate had outlived its reason.
- New `firstPartyMuxerCanWrite()` in `container_utils.dart` holds that policy in
  one place rather than duplicating it across the two muxing sites.

## 0.5.5

- **Internal pins are now caret ranges, not exact versions.** Exact pins made
  every patch cascade: publishing `miniav_tools_platform_interface` 0.5.3 made
  the already-published `miniav_tools` 0.5.3 and `miniav_tools_ffmpeg` 0.5.3
  unsatisfiable next to it, because they pinned 0.5.2 exactly and nothing in the
  set could move independently. `dart pub publish` warns about this. `release.py
  sync` now normalises to caret so it cannot recur.

## 0.5.4

- Picks up `miniav_tools_codecs` 0.6.2 (0.6.1 could not build its native assets
  downstream). No recorder code change.
- README: the zero-copy section still said the shared handle goes to the FFmpeg
  backend's `FfmpegD3d11HwEncoder`, which has not been the default since 0.5.3.
  Now documents the two GPU-resident frame shapes, which capability each needs,
  and why negotiation is restricted to backends that accept the shape the
  recorder has already committed to producing.

## 0.5.3

- **The FFmpeg-free path is now the default.** `_prepare` calls
  `registerFirstPartyBackends()` before negotiating, so on Windows H.264/HEVC
  goes to the OS hardware encoder MFT (NVENC / AMF / QSV) and AAC to the OS
  codec, with no per-app registration. FFmpeg is still registered and still
  wins wherever it is genuinely the better path — capability is reported
  honestly and `isHardware` outranks priority. Pin or exclude explicitly with
  `BackendPreference.pinned` / `.excluded` if a specific backend is required.

- Encoder negotiation is now restricted to backends that accept the frame kind
  the caller has already committed to producing. With scale/effects on, the
  screen path hands over a D3D11 *texture*; without this a higher-priority
  encoder that takes only shared handles wins, trips the safety net, and adds
  back the CPU readback the GPU path existed to avoid — strictly worse than the
  backend it displaced. Ranking cannot see this: it compares
  hardware/zero-copy/priority, not what is about to be handed over.

- **Screen zero-copy is gated on encoder capabilities, not on a concrete type.**
  The check was `encoder.platform is FfmpegD3d11HwEncoder`, so any other
  GPU-capable encoder failed it, tripped the safety net, and was silently forced
  onto the CPU-readback path — a full frame readback per frame at screen
  resolution, with no error anywhere. It now asks
  `supportsD3d11SharedHandleInput` (capture NT handle → direct passthrough) and
  `supportsD3d11TextureInput` (processor texture → pipelined), which are gated
  separately: an encoder that takes a handle but not a foreign-device texture
  now gets passthrough when there is no scale/effects work, and falls back only
  when there is. Capture also configures GPU output when a registered backend
  accepts `miniavBufferD3D11`, so the handle exists to pass through.

- Warn at GPU init when the loaded minigpu native binary predates the event-drain
  fix (`Minigpu.drainSpinBudgetMs` null or 0), and expose it as
  `Recorder.gpuDrainFixPresent`. Without that fix every GPU wait costs a ~15.6 ms
  Windows timer quantum; the per-frame GPU stage then overruns the frame budget
  on its own, the adaptive throttle reads that as a saturated GPU and steps the
  live capture rate down — so a stale native artifact presents as recording
  stutter with no error anywhere. The bundled DLL is a build artifact and a stale
  one loads perfectly happily, which is what makes this worth a runtime check.
- Screen effect chain now uses fire-and-forget dispatch: one synchronization
  point per frame instead of one per effect. The texture downscale stays awaited
  on purpose — its per-frame texture bind has no ordered variant and the texture
  is destroyed as soon as the call returns.
- Requires `minigpu: ^1.5.9`, where buffer binds are ordered against
  `dispatchFire`. On 1.5.8 the same code would silently bind wrong.

## 0.5.2

- Fixed the metronomic stutter in screen recordings: the fps throttle no
  longer thins a source that is within ~15% of the target rate (e.g. WGC/DXGI
  capture delivering ~31.4 fps against a 30 fps target — each deleted frame
  was a double-length presentation hole every ~0.7 s of playback). The
  throttle now engages only when the source meaningfully outruns the target
  (e.g. 60→30), thinning evenly via the credit scheduler, and logs its
  engage/release transitions. Pairs with the `miniav_ffi` 0.5.11
  capture-pacing fix that removes the over-delivery at its source; both
  policies live in the new unit-tested `FramePacer`.
- New **`cfrOutput`** knob on screen sources (`ScreenRecorderSource.cfrOutput`
  / `RecorderBuilder.addScreen(cfrOutput: ...)`, default false — VFR): output
  PTS are quantized to the exact rational fps grid and every grid slot is
  filled exactly once — live frames claim the slot nearest their capture
  time, slots the capture missed are backfilled with duplicates of the
  previous frame (zero-copy/direct paths; the idle duplicator fills overdue
  grid slots too), and surplus frames are dropped. A missed capture becomes
  an invisible duplicated frame instead of a visible playback hiccup,
  regardless of source cadence. Verified end-to-end: 6 s real capture →
  100% of encoded PTS deltas exactly one grid slot.
- Video stats line now reports `dup=N` (idle-fill + CFR backfill duplicate
  frames) when non-zero.
- Fix the scale/effects pipeline (bilinear scale, censor boxes, crop, …) being
  silently dropped on the CPU-encode path — most visibly with **window (WGC)
  capture**. Two causes, both fixed:
  - **Capture output preference.** The GPU processor imports the capture's
    D3D11 texture handle, but the capture was set to CPU output whenever a GPU
    encoder wasn't selected (`useGpuOutput=false`), even though a processor was
    still created for the scale/effects. Window (WGC) capture then returns plain
    CPU buffers with no handle, so the processor couldn't import them and the
    whole effects chain was skipped. (Display/DXGI capture happened to still
    carry a handle, which is why only window capture broke.) The capture now
    uses GPU output whenever a processor will run — including the CPU-readback
    path — so the processor always gets a handle.
  - **Encoder-fallback reconciliation.** When GPU output *was* configured but
    the encoder that opened is CPU-input (e.g. the isolate-hosted software /
    CPU-fed HW encoder — zero-copy and the minigpu GPU encoder were unavailable
    on the adapter), the reconciliation path **nulled the GPU processor**,
    discarding downscale + effects. It now keeps the processor and switches it
    to CPU read-back. (Exposed by the isolate CPU-fed HW encoder +
    `preferCaptureAdapter`, which make CPU-input fallback more common.)
- Screen recording no longer freezes the app on the CPU-fed encode path, and
  now uses hardware encode where it previously couldn't. When the zero-copy
  D3D11 encoder is unavailable (e.g. an AMD iGPU whose AMF NV12 pool fails, or
  any adapter whose only hardware vendor is QSV / MediaFoundation), the
  recorder's encoder — via `miniav_tools_ffmpeg` 0.5.2 — now runs a CPU-fed
  hardware encoder (or the software encoder) on a worker isolate. This both
  keeps the synchronous encode off the UI isolate AND lets QSV / MediaFoundation
  initialise (their MTA requirement can't be met on Flutter's STA UI isolate).
  Requires `miniav_tools_ffmpeg` 0.5.2.

## 0.5.1

- New `Recorder.preferCaptureAdapter()` static (Windows): binds the
  process-global GPU context to the adapter driving the primary display so
  capture → GPU processing → HW encode stay on ONE adapter (same-adapter
  zero-copy). This is what enables iGPU HW encoders (AMD AMF / Intel QSV) on
  hybrid systems where a discrete GPU is also present — without it, capture
  frames produced on the display iGPU reach a dGPU-bound pipeline through a
  per-frame CPU bridge. Must be called at app startup BEFORE any minigpu use
  (including audio visualizers); logs a warning when it lands too late.
  Trade-off: all of the process's minigpu compute then runs on the display
  adapter (`MGPU_ADAPTER_NAME` env var overrides). Requires minigpu 1.5.6.

## 0.5.0

- GPU-saturation anti-stutter (when another workload, e.g. a game, maxes the GPU):
  - Per-stage timing in the video stats line: `gpu=avg/max ms` (GPU processor
    stage — downscale/effects/YUV/shared-texture copy) and `enc=avg/max ms`
    (encoder stage). A `gpu=` figure far above the frame interval while encoded
    fps sags identifies GPU saturation directly.
  - Adaptive GPU-pressure throttle (`addScreen(adaptiveGpuThrottle: true)`,
    default on): sustained GPU-stage overrun steps the LIVE capture rate down by
    a power-of-two divisor (shown as `adapt=÷N` in stats) instead of letting
    frames pile into the encode queue and drop unevenly as `busy_drop` stutter.
    Throttle drops are evenly spaced and the frame duplicator keeps the encoded
    output at the target fps, so playback degrades smoothly; the divisor
    restores automatically (with hysteresis) when GPU pressure clears.
  - Together with the process/device GPU scheduling priority boost shipping in
    miniav_ffi 0.5.10 and minigpu_ffi 1.5.5 (capture + compute submissions
    preempt a saturating workload), this converts "GPU maxed → stutter" into
    "GPU maxed → briefly reduced live refresh at a steady cadence".
  - Direct BGRA passthrough on the zero-copy path: when no scale policy and no
    effects are configured, encoder-sized capture frames are fed to the D3D11
    encoder as their shared NT handle directly (`FrameSource.miniavBuffer`) —
    the encoder opens the handle on its own device and copies it with the COPY
    engine. Zero shader-core work per frame, so a saturated GPU has nothing of
    ours to starve. The frame duplicator retains the last live buffer as its
    idle-fill source; size-mismatched frames (mid-stream display mode change)
    fall back to the GPU processor, which rescales.
  - Pipelined zero-copy encode (scale/effects configs): the GPU processor stage
    of frame N+1 now overlaps the encode of frame N (each stage internally
    serialized, single-slot handoff). `GpuScreenProcessor` gained a
    shared-output texture ring (`sharedRingDepth`, recorder uses depth 2) so
    the texture being written is never the one the encoder is reading — under
    GPU saturation the ballooned GPU stage hides behind the encode instead of
    adding to it, and tearing is structurally impossible on this path.
- Software fallback no longer freezes the app:
  - Video `TrackInfo` now carries the encoder's codec extradata (SPS/PPS) when
    available at open, so `FfmpegMuxer` can write the track header without a
    live encoder bridge — required for the isolate-hosted software encoder
    (miniav_tools_ffmpeg 0.5.0), whose `AVCodecContext` lives on a worker
    isolate and performs the libav encode off the UI isolate.

## 0.4.10

- Frame-drop / lag fixes. The capture→encode pipeline was
  CPU/event-loop-bound, dropping frames while the GPU idled:
  - Replace the depth-1 back-pressure gate with a small bounded (depth-3) frame
    queue with oldest-drop, so a brief encode overrun no longer drops the next
    frame. The encode stage stays strictly serialized (the encoder/muxer FFI is
    single-threaded); only a sustained overrun drops, and then the oldest frame.
  - Split the video frame-drop counter into throttle-drops (by design — capture
    outruns the target fps) vs busy-drops (real back-pressure). The video stats
    log now reports `thr_drop=`/`busy_drop=` separately so a busy-bound config
    is immediately distinguishable.
  - GPU CPU-readback path (`processToBytes`) reuses a persistent read-back
    buffer instead of allocating ~8 MB per frame at 1080p; the mixed-audio path
    recycles its PCM byte buffers from a small pool and drops a per-chunk
    `sublist` copy.
  - Per-frame buffer release on the capture hot path uses the new synchronous
    `MiniAV.releaseBufferSync()` (no per-frame `Future` allocation).
  - Accepted frames now carry their capture-time timestamp so PTS spacing stays
    even when the serialized encoder briefly stalls and then drains the queue.
- Frame-drop / lag fixes:
  - Decouple muxing from the encode path. `dispatchPacket` previously awaited the
    shared muxer's `writePacket` inline, so every encoded video/audio packet
    blocked the encode gate on a libav write. Encoded packets are now chained onto
    a bounded, serialized per-sink write queue (`BoundedWriteQueue`) drained
    independently; the muxer write overlaps the next encode instead of blocking
    it. Order is preserved (FIFO per track; libav interleaves by DTS), and a
    sustained backlog applies back-pressure rather than dropping encoded data. The
    queue is fully drained before the muxer trailer is written on stop.
  - GPU color conversion for the software/CPU-encode fallback. New
    `GpuYuv420Converter` runs RGBA→YUV420P (planar u8, BT.601 limited) as a
    minigpu compute shader instead of the per-pixel Dart loop. It reads the RGBA
    straight from the on-GPU effects buffer and reads back the ~2.7× smaller YUV
    planes (1.5 vs 4 bytes/px); the software encoder consumes YUV420P natively.
    Output is byte-identical to the previous CPU conversion (verified against the
    reference on the real GPU). The `processorCpuReadback` encode path now uses
    this GPU YUV conversion (and feeds the planes via `FrameSource.yuv420p`)
    whenever the encoder reports `acceptsYuv420pPlanes` (the software path);
    CPU-fed hardware encoders (NV12/RGBA) keep the RGBA read-back.
  - Clip export (`ClipBuffer.saveClip`): the keyframe-aligned window selection is
    now a single bounded snapshot pass (`selectClipSlice`) instead of multiple
    full-buffer `where().toList()` scans plus a separate later sort. This shrinks
    the synchronous block on the live recording path when a clip is saved and
    produces a stable, pre-sorted copy decoupled from the live ring buffer. The
    (previously untested) GOP-preroll / no-keyframe-drop logic is now unit-tested.
    (Moving the FFmpeg mux itself fully off the isolate onto a worker is a
    follow-up — see Phase 2 #9 worker offload.)
  - Zero-copy GPU encode path now awaits minigpu's async shared-output copy
    (`bgraToRgbaSharedOutputAsync` / `copyFromBufferAsync`, minigpu ≥ 1.5.3)
    instead of the synchronous variants, so the per-frame GPU copy + cross-device
    present sync runs on minigpu's worker thread rather than busy-polling on this
    isolate. (Requires `minigpu: ^1.5.3`.)

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Add `Recorder.warmup()`: registers the FFmpeg backend, then delegates to
  `MiniAVTools.warmup()`. Calling `MiniAVTools.warmup()` from `main()` before
  any `start()` silently skipped FFmpeg (the backend is only registered
  lazily inside `start()`), so the download still hit the first recording.

## 0.4.6

- Dart-side logging no longer writes to `dart:io` `stderr` anywhere
  (recorder runtime, clip buffer, GPU screen processor): those writes crash
  console-less Windows GUI apps with an uncatchable async
  `FileSystemException` (errno 6). All messages now flow through the
  `Recorder.setLogCallback` router; the no-callback default sink is `print`.
- `Recorder.setLogCallback` / `setLogLevel` now also route the
  `miniav_tools_ffmpeg` Dart layer (auto-downloader, encoder selection,
  vendor probing) as `RecorderLogSource.ffmpeg`, so FFmpeg download failures
  are visible through the unified callback.

## 0.4.5

- Add `Recorder.sharedGpu` getter: exposes the process-global `Minigpu`
  instance after `ensureSharedGpu()` returns, or `null` when GPU is
  unsupported. Allows host code (e.g. a live GPU preview widget or a custom
  compute pass) to reuse the same Dawn device without a second `gpu.init()`.
- Export `GpuScreenProcessor` from the public `miniav_recorder` API so callers
  can build their own GPU preview pipelines using
  `MinigpuPreviewController` + `MiniavGpuPreview` from `minigpu_view`.

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

- add RecorderLogSource.minigpu: routes native minigpu/Dawn log lines through the unified Recorder log callback; Recorder.minigpuLevelFor public helper for tests; 12 new tests in log_level_test.dart

## 0.2.7

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- Increment minigpu to 1.4.4

## 0.2.6

- bump `miniav_tools_ffmpeg` to ^0.2.6 (fix missing `dart:convert` import that caused compile error in 0.2.5).

## 0.2.5

- bump `miniav_tools_ffmpeg` to ^0.2.5 to pick up the allowMalformed UTF-8 fix (FormatException on FFmpeg log messages with non-UTF-8 bytes such as Latin-1 filenames).
- fix: loopback/mixed audio crackles caused by the `_busyEncode` drop pattern. When `dispatchPacket` (file muxer write) yielded to the Dart event loop, the next 10 ms loopback chunk would fire, hit the busy guard, and be silently discarded — advancing `_framesOut` without emitting audio, creating a PTS hole heard as a pop/crackle. Replaced with a sequential `_encodeChain` future so chunks always queue in order and are never dropped.

## 0.2.4

- bump `miniav_tools_ffmpeg` to ^0.2.4 to pick up the FfmpegShim.tryLoad cache-poisoning fix (audio encoder failed when `Recorder.setLogLevel`/`setLogCallback` was called before FFmpeg was loaded).

## 0.2.3

- RecorderLogLevel and RecorderLogSource enums; Recorder.setLogLevel, setLogCallback; internal logs routed through callback; 30 new tests in log_level_test.dart
- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all native logs (MiniAV + FFmpeg) through a single Dart callback

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
- FFmpeg-backed muxing to MP4/MKV files and chunked streams via `miniav_tools_ffmpeg`.
- Zero-copy GPU screen-capture path on Windows via shared D3D11 device.
