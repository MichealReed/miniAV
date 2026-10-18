# Changelog

## 0.3.1-WIP

## 0.3.0

- Requires miniav 0.8.0 and the 0.6.0 miniav_tools packages
  (miniav_tools_codecs 0.8.0). No other changes.

## 0.2.7

- Requires spawn ^0.1.1: native transfers actually transfer, and a web message
  the worker cannot deserialize is reported instead of vanishing.

## 0.2.6

- Increment downstream deps

## 0.2.5

- Web audio plays entirely off the main thread where the page supports shared
  memory: a worker demuxes and decodes into a ring that an AudioWorklet reads,
  and the media clock follows what the audio device has consumed. Elsewhere the
  existing audio pump is used. New `PlayerStats.audioUnderruns` and
  `MiniavPlayer.usingWorkerAudio`.
- Uses `ManagedMediaSource` on iPhone, where classic `MediaSource` does not
  exist.

## 0.2.4

- `openSource` passes the container's coded dimensions to the video decoder;
  HEVC through `openSource` showed a black screen because the Media Foundation
  HEVC decoder needs them. New `MiniavPlayer.videoDecoderConfig` shows the
  config the decoder was opened with.
- The end-of-stream drain no longer discards audio or ignores a pending seek: an
  MP3 lost ~58% of its samples and an AAC file its last ~12 ms, and a seek near
  the end resumed from the keyframe instead of the requested position.
  `videoFramesDecoded` counts drained frames too.
- `pause()` in `paced` mode holds the audio being written instead of dropping
  it; pausing an MP3 part-way lost everything after the pause. `live` mode still
  drops.
- `onEnded` completes once the last video frames are presented, not just
  decoded, so an app closing the player there no longer cuts off the ending.
- The end of a stream waits through `pause()` and gives way to `seek()` and
  `close()`, instead of timing out into a false completion. `close()` also
  completes `onEnded` on native, so an app waiting on it to advance a playlist
  no longer hangs when playback is stopped early.
  `VideoScheduler.waitUntilPresented` takes an optional `shouldAbort`.
- A machine with no audio output device plays with silent audio, at the stream's
  real rate, instead of raising an uncatchable error for every chunk. New
  `MiniavPlayer.audioOutputUnavailable` reports it.
- New `@visibleForTesting` hooks `MiniavPlayer.debugOnDecodedAudio` and
  `PlayerAudioOutput.debugCreateContext`.
- Docs: FLAC and Vorbis decode through FFmpeg (see `miniav_tools_codecs` 0.7.0),
  so without `miniav_tools_ffmpeg`, playing `.flac` or Ogg/Vorbis raises
  `NoBackendForCodecException`. MP3 stays first-party.
- Requires `miniav_tools_codecs` ^0.7.0 (an MP3 source played a fraction of a
  second on 0.6.9) and `miniav_tools_ffmpeg` ^0.5.5, which reads the container's
  rotation, so `MiniavPlayerView` turns portrait phone clips instead of playing
  them sideways.

## 0.2.3

- Requires `miniav_tools_codecs` ^0.6.9: MP3 sources were detected as AAC and
  ended almost immediately. Its first-party MP3 demuxer also makes MP3 playable
  on web.
- Requires `minigpu_view` ^1.5.10; 1.5.9 constrained `miniav` ^0.5.2 and could
  not resolve beside `miniav` 0.7.x.

## 0.2.2

- Internal dependencies are caret ranges instead of exact pins, which made each
  patch release unsatisfiable next to already-published packages.
- Requires `minigpu_view` ^1.5.10, whose published 1.5.9 still constrained
  `miniav: ^0.5.2` and blocked any consumer of both.

## 0.2.1

- Requires `miniav_tools_codecs` 0.6.2. 0.2.0 pinned 0.6.1, which cannot build
  its native assets for a consumer, so 0.2.0 is unusable.
- README rewritten: since `registerPlayerBackends()` registers the Media
  Foundation hardware decoder and the OS AAC codec, decode no longer needs
  FFmpeg everywhere. It documents which paths run without FFmpeg on each
  platform, the latency modes and what `extraData` must hold.

## 0.2.0

- Requires `miniav` ^0.7.0, which closes each GPU frame's shared handle on
  release; under `^0.6.0` a player leaked one kernel handle per GPU frame.
- Web playback: the player compiles and runs on web, decoding with WebCodecs and
  presenting each `VideoFrame` directly through minigpu_view's canvas
  (`webVideoFrame`), with no conversion and no minigpu compute context. Web
  audio plays too (Opus via WebCodecs into the miniaudio WASM sink). The
  `examples/player` demo runs on web and native from one `main.dart`.
- `MiniavPlayer.openSource(MediaSource)` plays a `.file(path)`,
  `.bytes(Uint8List)` or `.byteStream(Stream<List<int>>)` (live or progressive
  fMP4/MKV/MPEG-TS): it probes the container, configures decoders from its
  tracks and runs its own demux pump with backpressure.
- Transport: `duration`, `position`, `isSeekable`, `seek(Duration)` (to a
  keyframe; decoders are never swapped mid-decode) and `onEnded`.
- `openSource` defaults to `paced` (timestamp-clocked) playback.
  `PlayerLatencyMode.live` (latest frame wins) is only for realtime packet
  feeds: on a demuxed container it presents one or two frames per fragment.
- Paced audio output (`writePaced`) never drops; a full ring throttles decoding
  instead.

## 0.1.0

- Initial release: packet-driven zero-copy player.
  - Video: FFmpeg decode on a worker isolate, one GPU upload, a WGSL YUV420P →
    RGBA conversion (BT.601 limited range, byte-exact against the CPU reference)
    and a `SharedOutputTexture` presented through minigpu_view with no readback.
  - Audio: FFmpeg decode on a worker isolate (AAC/Opus/MP3/Vorbis/FLAC to
    interleaved f32) into a miniaudio `StreamPlayer`.
  - `PlayerLatencyMode.live` (latest-wins) and `.paced` (pts-clocked)
    scheduling; keyframe-resync catch-up on decode backlog; stats.
