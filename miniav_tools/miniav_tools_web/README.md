# miniav_tools_web

WebCodecs/MediaStream backend for [`miniav_tools`](../miniav_tools) — browser only.  
Wraps the browser's native `VideoEncoder`, `VideoDecoder`, `AudioEncoder`, and
`AudioDecoder` APIs, with a `MediaRecorderCapture` fallback for browsers that
lack WebCodecs.  
Self-registers with the `miniav_tools_platform_interface` registry on import.

> Importing `package:miniav_tools_web/miniav_tools_web.dart` is enough.
> Once registered, `MiniAVTools.createEncoder(...)` will use this backend at
> priority 80 — browser-native encoding is preferred over wasm/software paths.

## What it provides

- **`WebCodecsBackend`** — `MiniAVToolsBackend` implementation backed by the
  browser `VideoEncoder` / `VideoDecoder` / `AudioEncoder` / `AudioDecoder` APIs.
- **`MediaRecorderCapture`** — `MediaStream`-based fallback for browsers that
  do not yet ship WebCodecs (or when the codec/config is unsupported).
- **`WebCapability`** — runtime feature detection helpers:
  `WebCapability.hasVideoEncoder`, `WebCapability.hasWebGPU`, etc.

## Automatic degradation

| Runtime capability | Behaviour |
|----|---|
| WebGPU + WebCodecs available | GPU effects (WGSL via `minigpu_web`) + WebCodecs encoding |
| No WebGPU, WebCodecs available | GPU effects skipped; WebCodecs encoding still works |
| No WebCodecs | Use `MediaRecorderCapture` directly as a fallback |

Check `WebCapability.hasVideoEncoder` and `WebCapability.hasWebGPU` at
runtime to branch between paths.

## Usage

```dart
import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_web/miniav_tools_web.dart'; // self-registers

final encoder = await MiniAVTools.createEncoder(EncoderConfig(
  codec: VideoCodec.h264,
  width: 1280, height: 720,
  bitrateBps: 4_000_000,
));
```

### MediaRecorder fallback

```dart
import 'package:miniav_tools_web/miniav_tools_web.dart';

if (!WebCapability.hasVideoEncoder) {
  final capture = MediaRecorderCapture(
    stream: videoElement.captureStream(),
    mimeType: 'video/webm;codecs=vp9',
  );
  await capture.start();
  // ...
  final blob = await capture.stop();
}
```

## Supported codecs

WebCodecs codec coverage varies by browser. The following are broadly available
in Chromium-based browsers:

| Codec | Encode | Decode |
|-------|--------|--------|
| H.264 / AVC | ✅ | ✅ |
| VP8 | ✅ | ✅ |
| VP9 | ✅ | ✅ |
| AV1 | ✅ (Chrome 113+) | ✅ |
| HEVC | ✅ (Chrome 106+, macOS/Windows) | ✅ |
| Opus | ✅ | ✅ |
| AAC | ✅ | ✅ |

## Dependencies

- [`web`](https://pub.dev/packages/web) — `dart:js_interop` Web API bindings
- [`miniav_tools_platform_interface`](../miniav_tools_platform_interface)
- [`minigpu_platform_interface`](../../../minigpu/minigpu_platform_interface) — optional GPU interop

## See also

- [miniav_tools](../miniav_tools) — user-facing facade
- [miniav_tools_ffmpeg](../miniav_tools_ffmpeg) — FFmpeg backend (native)
- [miniav_tools_minigpu](../miniav_tools_minigpu) — GPU compute backend
- [Design doc](../miniav_tools_design.MD)
