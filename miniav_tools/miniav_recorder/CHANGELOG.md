# Changelog

## 0.5.17

- `addScreen(captureCursor: true)` draws the mouse cursor into the recording. miniAV has had the toggle since before this package existed and the recorder never called it, so every recording made here was cursor-less with no way to say otherwise - which for a usability recording removes the one thing you most want to see. Defaults to false, matching every backend, so existing recordings are unchanged.

- Honoured on Windows WGC (`IsCursorCaptureEnabled`, Windows 10 2004 and later), macOS ScreenCaptureKit and Linux PipeWire. Windows DXGI cannot draw a cursor and captures without one; on web the browser decides. Where a platform declines, the recording continues cursor-less and says so once - a cursor is worth asking for, not worth failing a session over.

## 0.5.16

- Raise the spawn constraint to ^0.1.1 — native transfer now actually transfers, and a web message the worker cannot deserialize is reported instead of vanishing.

## 0.5.15

The container writer moves off the isolate that calls `stop()`, and the
recorder says what it is doing while it finishes.

- **The container writer runs on a worker, so `stop()` no longer freezes the caller.** Building an MP4 index is one synchronous pass over every sample in the recording — over half a million entries for two hours — and the isolate paying for it was the one drawing the UI. The writer itself is untouched: it runs on the worker through the same pinned backend, so a file cannot come out different depending on where it was assembled. If no worker can be started the recorder writes in process exactly as before and says so in the log, because a worker that will not start should cost a freeze, not the recording. A worker that dies mid-recording is reported once, when it happens, rather than as one error per dropped packet.

- Only the first-party MP4/M4A/WAV writers move. A worker-hosted FFmpeg muxer is a separate problem: it takes codec parameters from a live `AVCodecContext` through a raw pointer into an encoder on another isolate, and it needs every stream's extradata before it will write a header. FFmpeg containers (MKV/WebM/TS) still finish in process.

- New `Recorder.finalizeProgress`: a broadcast stream of `RecorderFinalizeProgress` reporting which phase `stop()` is on — stopping capture, draining, flushing, writing the index, closing, done — with elapsed time and, for the index phase, which file. Phases rather than a fraction: the expensive step is one call into a container writer that reports nothing while it runs, and a percentage over that would be a progress bar that lies.

- The codec configuration record is handed to the container with the first packet, for encoders that only publish it after their first output. Without this an Intel Quick Sync machine could not use the first-party MP4 writer at all and fell back to FFmpeg for the whole recording — which then rewrote the entire multi-gigabyte file at stop to move `moov` to the front. Requires `miniav_tools_codecs` 0.7.6.

- `stop()` reports where its time went — one line with a per-phase breakdown (stop capture / drain / flush / write index / dispose), warning when the whole shutdown ran long enough to drop frames. Every phase does synchronous FFI on whatever isolate called stop, and which one blocked was not knowable from outside. For scale: writing the container index is proportional to sample count, measured at ~240ms for 30 minutes and ~1s for 2 hours of 30fps video plus AAC.

- A track build that throws part way through no longer orphans the native objects it had already created. Harmless as a one-off at start; a leak per attempt in the stage rebuild, which runs the same builder every few seconds for the whole length of an outage, and each orphan is a capture context holding a graphics device.

- `Recorder.updateTrackConfig` now returns `Future<void>` rather than `void`, because the container it talks to may be on a worker. Calling it as a statement is unaffected.

- The video encoder log line now includes the encoder's D3D11 device and whether it matches the capture's. It was being built with a comment explaining why it mattered and then never printed — a device mismatch presents as every GPU frame being refused with no clue as to why.

## 0.5.14

- Watchdog fixes
- **A frozen capture is now detected.** The silence watchdog read encoded packets, on the reasoning that a healthy static screen still emits a duplicate every frame interval, so packet silence is already pathological. True — and the converse is what broke it: the idle-frame duplicator goes on re-encoding its last frame when the capture underneath is dead, so the one detector meant to catch "capture stopped and nothing said so" was blind in the default configuration. Seen in the field on a display mode change (5120x1440 to 3840x1440): the platform never reported a loss, a few frames arrived at the new size, then nothing for the remaining fifty seconds while the packet counter climbed and the picture sat frozen. The watchdog now also watches frames from the SOURCE, which the duplicator cannot forge.

- The watchdog now asks the platform instead of always waiting out the window. Three seconds of source silence - which a moving screen never reaches - triggers one question: is the display still attached, and is it still the size the capture is delivering? A display that has been re-routed or resized while the capture hands over nothing is a stale capture item, and saying so needs no guesswork. Cuts the frozen stretch from ten seconds to about three for a mode change or an unplug; the ten-second window remains the fallback for a stall the display itself does not show.

- A watchdog outage is now timed from when the capture went quiet, not from when the watchdog concluded it. Both silences are decided after a window has elapsed and the recording was already frozen for all of it, so timing from the declaration counted only the recovery: three ten-second freezes were reported as "0.8s missing". That number is what an operator uses to decide whether a session is usable.

- Source silence uses a much longer window than output silence (10s vs 3s), because the two mean different things: screen capture is event-driven, so a desktop where nothing moves legitimately delivers nothing for minutes. Each re-acquire that fails to bring frames back doubles the window, up to a minute, and a frame arriving earns the short window back — so a real death is caught in ten seconds while a genuinely still desktop settles at roughly one re-configure a minute, each covered by the duplicator and invisible in the file.

- **Every capture source now hears its device die, reports it, and re-acquires it — not just the screen.** The loss machinery lived on the video runtime because video was the only path wired to it, and none of it is about pictures. Microphone, loopback, camera and both inputs of a mixed-audio track are on it now. The signal had been there the whole time: WASAPI calls its lost callback on `AUDCLNT_E_DEVICE_INVALIDATED`, Media Foundation ends the sample stream, and `addLostListener` carried both to Dart. Nothing subscribed. One Win+P took out a display and the HDMI audio endpoint that belonged to the same monitor; the video loss was reported and the audio simply stopped, four seconds absent from the file with "Recording stopped" reported as success.

- A mixed-audio track tracks its two inputs separately, because they fail independently — a render endpoint dies with the monitor while the microphone beside it keeps working. This is the worst place to lose an input silently: the mix is driven by the loopback callback, so a dead endpoint stops the whole track, microphone included.

- `Recorder.captureStatus` and `Recorder.captureIssues` now report one entry per capture SOURCE rather than per track, so a mixed track's microphone and endpoint appear under their own names. Both already returned lists; nothing at the call site changes.

- New on `addCamera` / `addMic` / `addLoopback` / `addMixedAudio`: `lossPolicy` and `reacquireLimit`, matching `addScreen`. `VideoCaptureLossPolicy` is now `CaptureLossPolicy` — the old name is a typedef for it and keeps working.

- Re-acquiring a lost display now looks for the display, not for the handle it used to have. A display device id is a live platform handle - on Windows literally an HMONITOR - and Windows destroys its monitor objects and issues new ones on every topology change, which is exactly the family of losses this recovers from. Every re-acquire was therefore asking for a monitor that had stopped existing: a Win+P test lost ten seconds of video to a display that was attached and capturable the whole time. Each attempt now re-resolves the target by the platform's display name, so a display that comes back under a new handle is picked up. A still-live id is always preferred, so platforms whose ids are already stable are unaffected.

- A screen track built without an explicit display id no longer re-picks "the default display" when it rebuilds. After a topology change that can be a different monitor, and a recording that continued on one would have looked correct in every log line and in the file.

- A capture target that is simply absent now reports as absent - once, and then rarely - instead of an error and a stack trace every few seconds for the length of the outage. New `CaptureTargetUnavailable`, which `start()` throws too, so an application that asked for a display that is not attached is told that instead of `MINIAV_ERROR_SYSTEM_CALL_FAILED`.

- A stage rebuild checks its target is present before re-acquiring the graphics device and warming the encoder SDK, and refuses a target reporting a 0x0 size rather than deriving an encoder configuration from it.

## 0.5.13

- Increment downstream deps

## 0.5.12

- Screen capture now survives losing its target. A capture item closing - Win+P, dock/undock, lock, an RDP transition, a display mode change - is re-acquired in place: same file, same track, same encoder, with a frozen frame across the gap. Nothing previously subscribed to the platform's capture-lost notification at all, so a lost display went unnoticed and the recorder re-encoded a dead capture handle at the frame rate for the rest of the session, reporting success at stop.

- A watchdog declares a loss when a source stops producing packets and the platform says nothing, which is the only cover for a graphics device reset. That case escalates to rebuilding the device, processor, encoder and capture context in place; a rebuild that would not match what the container already declares is refused rather than spliced.

- New: VideoCaptureLossPolicy and reacquireLimit on addScreen (default: re-acquire for as long as the recording runs), Recorder.captureStatus and Recorder.captureHealthy for live health during a recording, and Recorder.captureIssues at stop - so a file that is short because its display went away is distinguishable from one that is short because someone stopped early. A window target is never re-acquired, since a destroyed HWND does not come back, and a different display is never substituted.

- A duplicate frame whose encode fails now retires its source instead of re-encoding it forever, the audio track's encodes are chained so a gap fill cannot overtake live audio and hand the muxer a backwards timestamp, and container timing repairs are logged at stop.

## 0.5.11

- Report the encoder's D3D11 device alongside the capture context's, so a device mismatch - which otherwise shows up as every GPU frame being refused with no explanation - is visible in the log.

## 0.5.10

- released 08/13/26 - MR

## 0.5.9

- Floor `miniav_tools_codecs` at ^0.7.0 (streamed MP3 decode fix; `^0.6.9`
  cannot admit it).
- **Audio-only `.wav` (PCM) and `.aac`/ADTS file sinks now record.** Both route
  to the first-party streaming muxers, which take already-encoded packets and
  need no encoder handle. `.wav` was previously impossible by any route:
  `firstPartyMuxerCanWrite` gated to MP4/M4A, so the sink fell to `FfmpegMuxer`,
  which can only describe audio FFmpeg encoded — and FFmpeg has no PCM encoder.
  `.aac` was unmapped as an extension and got an M4A written into it. MP4, M4A
  and MKV routing is unchanged.
- New `firstPartyMuxerCanWrite(audioTracks:)`. WAV and ADTS hold exactly one
  audio track and neither writer reads `EncodedPacket.trackIndex`, so a second
  track would be interleaved into the first one's stream rather than refused.
  A `Set<AudioCodec>` cannot express that — two same-codec tracks collapse to
  one element — so state the count; `null` falls back to the element count,
  which is exact for a per-track iterable.
- **Audio tracks describe themselves to the muxer with the encoder's extra
  data.** Both audio `toTrackInfo()` implementations omitted it (the video one
  did not), so a first-party muxer had to synthesise the codec-private header —
  and a synthesised OpusHead carries PreSkip = 0, which drops the encoder's
  lookahead and plays every sample ~6.5 ms late. Not derivable, unlike AAC's
  AudioSpecificConfig: nothing in the sample rate or channel count holds it.
- `containerForExtension` maps `.aac`/`.adts` → `Container.adts`, and
  `containerForTrackMix` answers WAV (not MKV) for audio-only PCM. `.ogg` is
  unchanged: `OggMuxer` still has no streaming `FileMuxerOutput` mode.
- **`MfVideoEncoder.invalidateImports()` now has a caller.** The recorder drops
  the encoder's imported-texture cache when the producer's frame geometry
  changes and when the GPU processor's shared-output ring is torn down. That
  cache pins each producer surface with a reference — which is what makes a
  texture pointer a safe key — so nothing had been releasing them; a 4K screen
  recording held ~135 MB of dead VRAM until LRU eviction happened past it. New
  `EncoderImportCache` holds the policy; a ring rebuild is invisible in frame
  geometry (the ring is encoder-sized) and so must be reported explicitly.
- `EncoderImportCache.noteFrame(buffer)` replaces the raw `noteProducerSize`
  call site, and takes `importsProducerTextures`. Only a track that submits the
  producer's own texture reports a resize: direct passthrough, or a track with
  no GPU processor at all (a GPU-output camera — previously missed entirely,
  since the old call site sat behind a `processor != null` guard). A pure
  processor track's cache holds the processor's encoder-sized output ring,
  which a producer resize does not touch.
- Trap: invalidating also releases the encoder's retained repeat source, and
  nothing outside the encoder can observe that. The recorder now clears the
  duplicator's last shared texture whenever a drop actually happens; otherwise a
  `cfrOutput` + `duplicate` recording claims a grid slot that `repeatLastFrame`
  then refuses to fill, and the hole is permanent.
- The dead-ring check moved ahead of the idle-frame-policy branch, so `black`
  reports a torn-down ring too instead of leaving the imports pinned. Policy
  `none` starts no timer and still cannot report one.
- Fixed a comment claiming backend priorities put minigpu (60) above FFmpeg
  (50): minigpu is 30 and loses. The check it annotates is a capability query
  answered before any encoder exists, not a prediction of who wins.

## 0.5.8

- **Audio negotiation is container-aware.** `_prepare` resolves each file sink's
  container up front and only pins audio to FFmpeg when a sink genuinely needs
  `FfmpegMuxer` (which can only mux audio FFmpeg itself encoded). An MP4/M4A
  recording therefore keeps the OS AAC encoder, where before it was either
  forced onto FFmpeg or failed at `start()`. When the coupling cannot be
  satisfied — a caller-pinned non-FFmpeg backend, or a codec FFmpeg has no
  encoder for — `start()` throws a `CodecInitException` naming the codec and the
  container before a device is opened, instead of an opaque
  `NoBackendForCodecException` later.
- **MP4/M4A file sinks and clips use the first-party ISO-BMFF writer** whenever
  the negotiated codec mix allows it. It streams to disk, so an open-ended
  recording no longer sits in RAM. If it declines, the real cause is logged and
  the sink falls back to `FfmpegMuxer`, re-pinning bridgeless audio encoders to
  FFmpeg so the fallback can actually mux.
- **Behaviour change: the default container for video+audio is MP4, not MKV,**
  when both codec sets are known and first-party writable. Unstated codecs still
  answer MKV, so callers that never named a codec are unaffected.
- Opus is accepted alongside AAC for first-party MP4/M4A clips.
- The clip path's temporary audio encoder is pinned to FFmpeg only on the
  FFmpeg-muxer fallback, and FFmpeg is loaded on that path; a standalone
  `ClipBuffer.saveClip` now registers the backends it needs instead of relying
  on a `Recorder` having run first.
- The CFR/idle duplicate slot is claimed only after the encode returns, so a
  first frame that fails to encode no longer leaves a hole the pacer thinks is
  filled.

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
