# Changelog

## 0.2.6

- Increment downstream deps
- Increment downstream deps
- Increment downstream deps

## 0.2.5

- Play web audio entirely off the main thread where the page supports shared memory: a worker demuxes and decodes into a ring an AudioWorklet reads, and the media clock is taken from what the audio device has consumed rather than what was written. Falls back to the existing audio pump everywhere else. Adds PlayerStats.audioUnderruns and MiniavPlayer.usingWorkerAudio, and drives ManagedMediaSource on iPhone where classic MediaSource does not exist.

## 0.2.4

- `openSource` now passes the container's coded dimensions to the video
  decoder. HEVC via `openSource` previously opened a session that could never
  produce a frame (black screen, no fallback): the Media Foundation HEVC
  decoder MFT rejects every packet until its input type carries a frame size,
  and the dimensions the demuxer had already read were dropped on the way to
  `DecoderConfig`.
- End-of-stream drain no longer discards audio or ignores a pending seek. It
  used the live (drop-on-full) sink write regardless of latency mode, so a
  decoder that emits its output at `flush()` had most of its tail thrown away
  — an mp3 lost ~58% of its samples, an AAC file the last ~12 ms. It also
  skipped the seek preroll, so seeking such a stream resumed from the landing
  keyframe instead of the requested position. `videoFramesDecoded` now counts
  drained frames too.
- `pause()` in `paced` (VOD) mode now HOLDS the decoded chunk being written
  instead of abandoning it. A whole-file decoder hands over the entire stream
  in one chunk, and that chunk is the only copy left once the packet is
  dequeued — pausing an mp3 part-way through dropped everything after the
  pause (58% of the file here) and `onEnded` still reported it played. Only
  close and seek discard now. `live` mode is unchanged (dropping is the point
  there).
- `onEnded` now waits for the video tail to be PRESENTED, not merely decoded.
  The drain handed the last frames to the scheduler, which then spent the rest
  of the file's media time pacing them to the screen — a 10-frame fixture had
  0 of them presented (8 still queued) when `onEnded` completed, so an app
  that closed the player there cut the ending off. Packets still queued behind
  the decode-ahead gate at EOF are also decoded before the flush now (a flush
  racing an in-flight decode loses frames). Both waits are bounded — a wedged
  presenter delays end-of-stream, it never blocks it. The doc on `onEnded` now
  states exactly what it does and does not guarantee.
- The end-of-stream tail now yields to `pause` / `seek` / `close` instead of
  timing out into a false completion. A pause freezes the media clock AND stops
  the decode pump, so none of those waits can be satisfied while paused:
  `onEnded` used to complete ~30 s later on a paused player with the tail still
  queued, `drain()` could flush a decoder that still had packets queued (decode
  errors on resume), and a seek in the tail window paid a fixed ~1 s and then
  recreated the decoders with the demux pump still running. The tail now holds
  across a pause and abandons on seek/close (seek re-reaches EOF and finishes
  it). `close()` also completes `onEnded` on the native path — only the web/MSE
  path did, so an app awaiting it to advance a playlist hung forever when the
  user stopped playback early. `VideoScheduler.waitUntilPresented` takes an
  optional `shouldAbort`, and reads a PAUSED clock as a stall rather than as
  pacing (it can never reach the head frame's pts).
- A machine with no audio output device no longer takes playback down.
  Opening the device threw out of the audio pump, which nothing awaits — an
  unhandled async error per chunk that no `onError` could catch. The sink now
  degrades ONCE (logged once, via `dart:developer`, not raised per chunk) to a
  silent sink that accepts writes and, in `paced` mode, still consumes them at
  the stream's real rate, so backpressure and end-of-stream timing are
  unchanged. New `MiniavPlayer.audioOutputUnavailable` reports it;
  `PlayerAudioOutput.debugCreateContext` is a `@visibleForTesting` seam for
  the failure path.
- New `MiniavPlayer.videoDecoderConfig`: the config the video decoder was
  opened with, so a caller (or a test) can see what the container's track
  description compiled to — the coded dims above are otherwise unobservable
  until the decoder silently produces nothing.
- First end-to-end player tests: `openSource` playback of wav/PCM, Ogg/Opus,
  mp3, ADTS/AAC, m4a/AAC, H.264 and HEVC in MP4, plus a seek and a
  pause/resume. They assert decoded output and presented frames, not just
  which backend was negotiated. The HEVC input is a committed fixture and the
  AAC ones are synthesized, so the coverage does not depend on optional OS
  encoders or on generated files a clone does not have.
  `MiniavPlayer.debugOnDecodedAudio` is a new `@visibleForTesting` hook for
  observing decoded PCM without an audio output device. The audio tests are
  genuinely headless now: one of them forces the device-open failure rather
  than skipping when there is no device.
- Docs: FLAC and Vorbis decode through FFmpeg, not first-party. The README and
  `registerPlayerBackends` advertised an FFmpeg-free path for both; the
  first-party decoders behind them need a whole container and cannot take a
  demuxed track, so `miniav_tools_codecs` 0.7.0 stopped claiming those codecs.
  Dropping `miniav_tools_ffmpeg` from an app that plays `.flac` or Ogg/Vorbis
  raises `NoBackendForCodecException`. MP3 decode and MP3 demux are unaffected
  and stay first-party.
- Floor `miniav_tools_codecs` at ^0.7.0: on 0.6.9, `openSource` on an mp3
  played a fraction of a second and reported end-of-stream. The software MP3
  decoder still emits its whole output at `flush()` — what makes that play
  through is the drain fix above, not a change in the decoder.
- Floor `miniav_tools_ffmpeg` at ^0.5.5, which reads the container's display
  matrix. A phone clip whose track declares 90/180/270 degrees now renders
  turned by `MiniavPlayerView`; 0.5.4 reported 0 for every container, so the
  same file played sideways. Dropping back to 0.5.4 restores the old
  (sideways) behaviour.

## 0.2.3

- Floor `miniav_tools_codecs` at ^0.6.9: mp3 sources played through
  `openSource` ended almost immediately — bare mp3 bytes were mis-sniffed as
  ADTS and opened as a fake AAC track. 0.6.9 fixes the sniff and adds a
  first-party MP3 demuxer, which also makes mp3 playable on web (no FFmpeg
  there to fall back to).
- Floor `minigpu_view` at ^1.5.10 (published 1.5.9 constrained `miniav` ^0.5.2
  and could not resolve beside `miniav` 0.7.x).

## 0.2.2

- **Internal pins are now caret ranges, not exact versions.** Exact pins made
  every patch cascade: publishing `miniav_tools_platform_interface` 0.5.3 made
  the already-published `miniav_tools` 0.5.3 and `miniav_tools_ffmpeg` 0.5.3
  unsatisfiable next to it, because they pinned 0.5.2 exactly and nothing in the
  set could move independently. `dart pub publish` warns about this. `release.py
  sync` now normalises to caret so it cannot recur.
- Requires `minigpu_view` ^1.5.10, whose published 1.5.9 still constrained
  `miniav: ^0.5.2` and blocked any consumer of both.

## 0.2.1

- Repins `miniav_tools_codecs` to 0.6.2. 0.2.0 pinned 0.6.1 exactly, and 0.6.1
  cannot build its native assets for a consumer — so 0.2.0 is unusable through
  no fault of its own code. An exact pin propagates a dependency's breakage;
  this is the argument for caret ranges on internal pins.
- README rewritten: it described decode as FFmpeg-only, which stopped being true
  once `registerPlayerBackends()` began registering the Media Foundation
  hardware decoder and the OS AAC codec. Now documents which paths run without
  FFmpeg, per platform, plus latency modes and `extraData` expectations.

## 0.2.0

- **Fixed: `miniav` constraint raised to `^0.7.0`.** It was `^0.6.0`, which
  excludes 0.7.0 entirely — the release in which miniav took ownership of the
  shared NT handle and closes it in `releaseBuffer`. A published player resolving
  under the old constraint leaked one kernel handle per GPU frame (60/s at
  60 fps).

- **Web playback (video).** The player now compiles and runs on web:
  conditional backend registration (FFmpeg on native / WebCodecs on web —
  keeps `dart:ffi` out of the web build and `dart:js_interop` out of native),
  and a web present branch — a WebCodecs `VideoFrame` (already display-ready)
  is presented directly through minigpu_view's canvas (`webVideoFrame`
  PreviewSource) with no YUV→RGBA convert and no minigpu compute context. The
  scheduler now carries either YUV420P bytes (native) or a browser VideoFrame
  (web) and owns its release (VideoFrames are `close()`d on present or drop).
  Demo: the unified `examples/player` runs the same encode→decode→present
  loop on web (WebCodecs) and native (FFmpeg) from one `main.dart`, with the
  native-only container `stream`/`file` modes gated behind a conditional
  import. Web audio now works too (Opus via WebCodecs → miniaudio WASM sink).
- Stream/broadcast smoothness: `MiniavPlayer.openSource` defaults to `paced`
  (pts-clocked). `PlayerLatencyMode.live` (latest-wins) is documented as
  correct ONLY for realtime packet feeds — using it for a demuxed container
  stream collapses each fragment burst to ~1–2 presented frames (choppy).
- **Source-driven playback** — `MiniavPlayer.openSource(MediaSource)` where
  `MediaSource` is `.file(path)` / `.bytes(Uint8List)` /
  `.byteStream(Stream<List<int>>)` (live/progressive fMP4/MKV/MPEG-TS). Probes
  the container, auto-configures decoders from the tracks (codec + extradata),
  and runs an internal demux pump with decode-ahead backpressure.
- Transport surface: `duration`, `position`, `isSeekable`, `seek(Duration)`
  (keyframe seek with preroll drop + decode-pump quiesce so decoders are never
  swapped mid-decode), and `onEnded`. Paced mode is the default for sources
  (pts-clocked VOD); pass `latency: live` for realtime feeds.
- Paced audio output (`writePaced`) never drops — the ring-full wait is the
  decode-ahead throttle for VOD playback.

## 0.1.0

- Initial release: packet-driven zero-copy player.
  - Video: worker-isolate FFmpeg decode → single GPU upload → WGSL
    YUV420P→RGBA8 (BT.601 limited, byte-exact vs CPU reference) →
    `SharedOutputTexture` ping-pong → minigpu_view present (zero readback).
  - Audio: worker-isolate FFmpeg decode (AAC/Opus/MP3/Vorbis/FLAC → f32
    interleaved) → miniaudio `StreamPlayer`.
  - `PlayerLatencyMode.live` (latest-wins) and `.paced` (pts-clocked)
    scheduling; keyframe-resync catch-up on decode backlog; stats.
