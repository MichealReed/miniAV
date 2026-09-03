# miniav_tools_codecs

First-party codec backends for [`miniav_tools`](../miniav_tools) — hardware
video encode/decode, audio codecs and container framing with **no FFmpeg
dependency**, plus GPU compute codecs powered by
[minigpu](../../../minigpu) (WGSL via Google Dawn).

FFmpeg remains available as a fallback through
[`miniav_tools_ffmpeg`](../miniav_tools_ffmpeg); this package is what the
negotiator prefers when it can.

## Registration

**Nothing here registers itself on import.** Dart has no import side-effect: a
top-level `final x = register();` is lazy, runs on first *read*, and nothing
reads it. Call the registration explicitly:

```dart
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

void main() {
  registerFirstPartyBackends(); // idempotent
  runApp(...);
}
```

If you use [`miniav_recorder`](../miniav_recorder) you do not need this — the
recorder calls it before negotiating an encoder, so recording apps get the
first-party path with no setup.

Individual registrations (`registerMfEncodeBackend`, `registerMfDecodeBackend`,
`registerAacBackend`, `registerOpusBackend`, `registerPcmBackend`,
`registerSwAudioBackend`, `registerContainerFramingBackend`,
`registerMinigpuBackend`) are exported for finer control. All are idempotent and
no-op on platforms they do not serve.

**Registering is not winning.** Every backend reports its capability honestly and
the negotiator ranks `isHardware` above `zeroCopy` above `priority` — so on a
machine with no hardware MFT, FFmpeg's hardware path still takes H.264. There is
no unregister; to force a choice, say so at the call site:

```dart
MiniAVTools.createEncoder(config,
    preference: BackendPreference.pinned('mf_encode'));
MiniAVTools.createEncoder(config,
    preference: BackendPreference.excluded({'mf_encode'}));
```

## What it provides

| Area | Backend | Codecs / formats | Platform |
|------|---------|------------------|----------|
| Video encode | `mf_encode` | H.264, HEVC — OS hardware MFT (NVENC / AMF / QSV), software MFT fallback | Windows |
| Video decode | `mf_decode` | H.264, HEVC → D3D11 texture | Windows |
| Audio | `mf_aac` | AAC encode + decode (OS codec; license-clean) | Windows |
| Audio | `opus` | Opus decode (libopus) | all |
| Audio | `sw_audio` | MP3 decode (dr_mp3) | all |
| Audio | `pcm` | pcmS16le, pcmF32le | all |
| Container | `container_framing` | WAV, Ogg, ADTS, MP4/M4A demux + mux; MP3 demux | all |
| Video encode | `minigpu` | MJPEG in WGSL compute shaders | any Dawn GPU |

`sw_audio` claims MP3 and nothing else. `SwAudioDecoder` also drives dr_flac and
stb_vorbis, but only for a WHOLE-FILE feed: those entry points take a complete
container and the decoder ignores `AudioDecoderConfig.extraData`, which is where
a demuxer puts the FLAC STREAMINFO / Vorbis setup headers it stripped. Claiming
them for negotiation would be terminal rather than optimistic — this backend
outranks FFmpeg and its `open()` cannot decline — so **demuxed FLAC and Vorbis
decode through `miniav_tools_ffmpeg`**, which is not optional for them.

Colour conversion (`GpuRgbaToYuv420Converter`, `dartI420ToRgba` and friends)
lives here too and is the canonical implementation.

## Zero-copy video encode (Windows)

`MfVideoEncoder` takes GPU-resident input in two shapes, both without a CPU
readback:

- a capture buffer's **shared NT handle**, opened straight onto the encoder's
  device (`supportsD3d11SharedHandleInput`);
- a raw **`ID3D11Texture2D` on another device** — a GPU processor's scaled or
  filtered output — imported via `GetSharedHandle` + `OpenSharedResource` and
  converted RGBA→NV12 by a D3D11 VideoProcessor
  (`supportsD3d11TextureInput`).

Measured cost of the second path at 2560x1440 fed at 60 fps: 0.60 ms/frame
mean, 0.91 ms p99 (`benchmark/mf_texture_bench.dart` — pace the feed, or you
measure encoder throughput rather than overhead).

MF requires an MTA apartment and Flutter's UI thread is STA, so the native layer
owns a dedicated MTA worker and marshals every call to it. Nothing in this
package needs to run on a particular thread.

## MP4 and Annex-B

Encoders emit Annex-B (start-code framed, parameter sets in-band); MP4 needs an
`avcC`/`hvcC` configuration record and length-prefixed samples. `Mp4Muxer`
converts automatically, deciding once from the track's `extraData` — a leading
`0x01` means it is already a configuration record and is passed through, so
remuxing a demuxed file does not double-convert. The primitives are exported:
`isAnnexB`, `splitAnnexB`, `buildAvcC`, `buildHvcC`, `annexBToLengthPrefixed`.

## Usage

```dart
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

registerFirstPartyBackends();

final encoder = await MiniAVTools.createEncoder(EncoderConfig(
  codec: VideoCodec.h264,
  width: 1920,
  height: 1080,
  hwAccel: HwAccelPreference.preferred,
));
```

### Direct GPU pipeline access

```dart
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';

final pipeline = MinigpuMjpegPipeline();
await pipeline.init(width: 1920, height: 1080);
final encoded = await pipeline.encode(frame);
await pipeline.dispose();
```

## Dependencies

- [`minigpu`](../../../minigpu/minigpu) — GPU compute facade
- [`gpu_tensor`](../../../minigpu/gpu_tensor) — tensor buffers over Dawn
- [`gpu_pipeline`](../../../minigpu/gpu_pipeline) — shader pipeline helpers
- [`miniav_tools_platform_interface`](../miniav_tools_platform_interface)

Native code (Media Foundation shims, libopus, dr_mp3/dr_flac/stb_vorbis) builds
from source via `hook/build.dart` into the `codecs_native` asset. dr_flac and
stb_vorbis are linked but only reachable through a whole-file
`SwAudioDecoder` feed — see the note under "What it provides".

## See also

- [miniav_tools](../miniav_tools) — user-facing facade
- [miniav_recorder](../miniav_recorder) — recording pipeline
- [miniav_tools_ffmpeg](../miniav_tools_ffmpeg) — FFmpeg backend (fallback)
- [Design doc](../miniav_tools_design.MD)
