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
| MP3 decode | dr_mp3 | all |
| Raw PCM (`pcmS16le`, `pcmF32le`) | first-party | all |
| WAV / Ogg / ADTS / MP4 framing, MP3 demux | first-party | all |

FFmpeg is registered alongside as the cross-platform software floor and the
fallback for everything else (MKV, VP8/VP9/AV1, software video, AAC when the
calling thread is STA, **and FLAC/Vorbis**). So an H.264 + Opus stream on
Windows decodes with zero FFmpeg; the same stream on Linux x86-64 falls back to
FFmpeg software decode automatically, with no code change.

**It does not fall back on macOS, Android or iOS.** The FFmpeg shim this
package needs is only built when the FFmpeg auto-download succeeds, and no
artifact exists for those platforms — so `brew install ffmpeg` on macOS changes
the error, not the outcome. There is no video decoder at all on those three
today. Note also that the FFmpeg-free demuxers accept in-memory **bytes only**,
so `MediaSource.file(...)` routes to FFmpeg on every platform; the honest macOS
feature set is audio-only playback of WAV/MP3/Opus/Ogg via `MediaSource.bytes`.
Full matrix, caveats and the plan:
[`docs/PLATFORM_SUPPORT.md`](../../docs/PLATFORM_SUPPORT.md).

FLAC and Vorbis are on the FFmpeg side of that line: the first-party decoders
behind them need a whole container, and a demuxed track arrives as packets
whose headers the demuxer has already stripped. Playing a `.flac` or an
Ogg/Vorbis file therefore requires `miniav_tools_ffmpeg` (registered here by
default) — dropping it raises `NoBackendForCodecException` on open.

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
present, so you do not need `MiniavPlayerView`. MP3, Opus, AAC and raw PCM
decode first-party; FLAC and Vorbis decode through FFmpeg (see above). WAV,
Ogg, ADTS, MP4 and bare MP3 demux without FFmpeg; anything else (MKV, MOV)
demuxes through FFmpeg and then decodes first-party where it can.

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
