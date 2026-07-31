# miniav_player

Network-first, zero-copy A/V player for Flutter.

Two ways in:

- **Packet-driven** (`MiniavPlayer.open`) — your transport (QUIC / WebTransport
  / WebSocket / in-process pipe) delivers `EncodedPacket`s and the player owns
  everything after that: decode, GPU colour convert, presentation, audio
  playback and A/V pacing. No demuxer, no file I/O.
- **Source-driven** (`MiniavPlayer.openSource`) — hand it a file, a byte buffer
  or a byte stream and an internal demux pump feeds the same pipeline. This is
  the path for local media playback, and it supports `seek()`.

Built on [`miniav_tools_codecs`](../miniav_tools_codecs) (hardware decode),
[`miniav_tools_ffmpeg`](../miniav_tools_ffmpeg) (software floor),
[minigpu](https://pub.dev/packages/minigpu) (WGSL YUV→RGBA) and `minigpu_view`
(shared-texture presentation).

## Install

```yaml
dependencies:
  miniav_player: ^0.2.1
```

Native code (Media Foundation shims, libopus, dr_mp3/dr_flac/stb_vorbis, FFmpeg)
builds through the dependencies' native-asset hooks. Nothing to configure.

## Hot path

```text
network packet ─▶ decode worker isolate (HW MFT on Windows, else FFmpeg)
              ─▶ TransferableTypedData hop (zero-copy transfer)
              ─▶ ONE GPU upload (1.5 B/px planes)
              ─▶ WGSL YUV→RGBA (BT.601 limited)
              ─▶ SharedOutputTexture (GPU→GPU copy)
              ─▶ Flutter Texture samples the shared handle — zero readback
```

## Codec backends

`MiniavPlayer.open` registers them for you (`registerPlayerBackends()`,
idempotent) — you do not need to call anything. What it registers, and what
therefore runs **without FFmpeg in the process**:

| Path | Backend | Platform |
|------|---------|----------|
| H.264 / HEVC decode → D3D11 texture | Media Foundation hardware MFT | Windows |
| AAC decode | OS codec (Media Foundation) | Windows |
| Opus decode | libopus | all |
| MP3 / FLAC / Vorbis decode | dr_mp3 / dr_flac / stb_vorbis | all |
| Raw PCM (`pcmS16le`, `pcmF32le`) | first-party | all |
| WAV / Ogg / ADTS / MP4 framing | first-party | all |

FFmpeg is registered alongside as the cross-platform software floor and the
fallback for everything else (MKV, VP8/VP9/AV1, software video, and AAC when the
calling thread is STA). So an H.264 + Opus stream on Windows decodes with zero
FFmpeg; the same stream on Linux/macOS falls back to FFmpeg software decode
automatically, with no code change.

Selection is by capability, not by registration order — the negotiator ranks
`isHardware` above `zeroCopy` above `priority`. To force one:

```dart
BackendPreference.pinned('mf_decode');
BackendPreference.excluded({'mf_decode'});
```

## Usage

```dart
final player = await MiniavPlayer.open(
  video: VideoStreamSpec(
    config: DecoderConfig(codec: VideoCodec.h264 /*, extraData: avcC */),
  ),
  audio: AudioStreamSpec(
    config: AudioDecoderConfig(codec: AudioCodec.aac, extraData: asc),
  ),
  latency: PlayerLatencyMode.live, // or .paced for VOD-style pts pacing
);

transport.onVideoPacket = player.submitVideoPacket;
transport.onAudioPacket = player.submitAudioPacket;

// Widget tree:
MiniavPlayerView(player: player);

// Lifecycle:
player.pause();
player.resume();
await player.drain(); // end-of-stream
await player.close();
```

### Playing a file (or bytes, or a byte stream)

```dart
final player = await MiniavPlayer.openSource(
  MediaSource.file('/path/to/track.mp3'),
  latency: PlayerLatencyMode.paced,
);

await player.seek(const Duration(seconds: 30));
```

`MediaSource.bytes(...)` and `MediaSource.byteStream(...)` take the same path —
the stream form buffers a bounded amount of undemuxed input and pauses the
source behind it, so a slow consumer cannot run the process out of memory.

Audio-only files work exactly the same way; there is simply no video track to
present, so you do not need `MiniavPlayerView`. MP3, FLAC, Vorbis, Opus, AAC
and raw PCM all decode first-party. Container support is the limit rather than
the codec: WAV, Ogg, ADTS and MP4 demux without FFmpeg, and anything else
(including a bare `.mp3` file, MKV, and MOV) demuxes through FFmpeg and then
decodes first-party.

### Sharing an app GPU context

```dart
final gpu = Minigpu();
await gpu.init();
final player = await MiniavPlayer.open(video: ..., gpu: gpu);
```

> Call `Minigpu.preferDisplayAdapter()` **before any minigpu initialisation** if
> you need to control adapter binding. On a hybrid-GPU machine the default
> adapter may not be the one the display is on, which costs a cross-adapter copy
> per frame.

## Latency modes

- `PlayerLatencyMode.live` — latest-wins presentation: a newer decoded frame
  supersedes a queued one. Bounded decode input queue with keyframe-resync
  catch-up. Watch `stats.videoPacketsDropped` to know when to ask your transport
  for a keyframe.
- `PlayerLatencyMode.paced` — VOD-style presentation timed off PTS.

## Extra data

`DecoderConfig.extraData` expects the codec configuration record — `avcC` for
H.264, `hvcC` for HEVC, `AudioSpecificConfig` for AAC. If your transport carries
Annex-B instead, `miniav_tools_codecs` exports `isAnnexB`, `buildAvcC` and
`buildHvcC` to build one from a keyframe's in-band parameter sets.

## Status

Working: packet-driven playback, file/byte/stream playback with seeking,
hardware decode on Windows, GPU presentation with no readback, A/V sync, live
and paced modes.

Not yet: the WebCodecs web path and D3D11VA zero-upload.
`docs/PLAYER_PLAN.md` in the repository tracks the architecture and roadmap.

## See also

- [miniav_recorder](../miniav_recorder) — the recording counterpart
- [miniav_tools](../miniav_tools) — codec facade
- [miniav_tools_codecs](../miniav_tools_codecs) — first-party codec backends
