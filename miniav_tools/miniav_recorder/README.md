# miniav_recorder

High-level multi-source A/V recorder for Dart.  Combines screen, camera, microphone and loopback sources into one or more MP4/MKV outputs (or live chunked streams) with a shared master clock.

Built on [`miniav`](../miniAV/miniav/) + [`miniav_tools`](../miniav_tools/) + [`miniav_tools_ffmpeg`](../miniav_tools_ffmpeg/).

---

## Quick start

```dart
import 'package:miniav_recorder/miniav_recorder.dart';

final rec = (RecorderBuilder()
      ..addScreen(codec: VideoCodec.h264, scale: ScreenScalePolicy.h264Friendly)
      ..addMic(deviceId: mic.deviceId)
      ..addFileOutput('output.mkv'))
    .build();

await rec.start();
await Future.delayed(const Duration(seconds: 10));
await rec.stop();
```

---

## Sources

### Screen / display

```dart
builder.addScreen(
  displayId: display.deviceId,  // null = default display
  codec:     VideoCodec.h264,
  hwAccel:   HwAccelPreference.preferred,   // default
  scale:     ScreenScalePolicy.h264Friendly, // optional downscale
);
```

### Camera

```dart
builder.addCamera(
  deviceId: camera.deviceId,
  codec:    VideoCodec.h264,
);
```

### Microphone / Loopback

```dart
builder.addMic(deviceId: mic.deviceId, codec: AudioCodec.aac);
builder.addLoopback(deviceId: loopback.deviceId, codec: AudioCodec.aac);
```

---

## Sinks

```dart
// Write to a container file (MKV or MP4 auto-selected).
builder.addFileOutput('rec.mkv');

// Receive raw encoded packets for live streaming / network forwarding.
builder.addStreamOutput((TrackChunk chunk) {
  // chunk.bytes, chunk.kind, chunk.ptsUs, chunk.isKeyframe, …
});
```

---

## Zero-copy GPU path (Windows)

`RecorderBuilder.preferZeroCopy` defaults to **`true`**.

When recording a screen source on Windows with a compatible hardware encoder (NVENC, AMD VCE, Intel QSV, Media Foundation), the recorder:

1. Initialises a shared **Dawn D3D12** context via [minigpu](../../minigpu/minigpu/).
2. Creates a matching **`ID3D11Device`** on the same GPU adapter.
3. Requests **GPU output** (`MiniAVOutputPreference.gpu`) from the DXGI capture so each frame arrives as a D3D11 NT shared handle — no pixel data crosses PCIe.
4. Passes the shared device handle to the FFmpeg backend, which opens `FfmpegD3d11HwEncoder` with `existingD3d11Device`.  The encoder reads the texture directly without any CPU copy.

Falls back silently to the CPU-upload path on any failure (unsupported GPU, non-Windows, no HW encoder).

---

## GPU downscaling

Screen sources can be downscaled on the GPU before encoding using `ScreenScalePolicy`.

| Policy | Behaviour |
|---|---|
| `ScreenScalePolicy.none` | No scaling (default). |
| `ScreenScalePolicy.h264Friendly` | Auto-downscale so `max(width, height) ≤ 4096`, preserving aspect ratio. Avoids the automatic H.264 → HEVC codec promotion on ultrawide / 4K+ displays. |
| `ScreenScalePolicy.fixedSize(w, h)` | Encode at an explicit pixel size (rounded to even). |
| `ScreenScalePolicy.scaleFactor(f)` | Uniform fractional scale, e.g. `0.5` = half each axis (rounded to even). |

### How it works

When zero-copy is active **and** a non-`none` policy is set, a `GpuDownscaler` is created for the track.  Per frame:

```
MiniAVBuffer (D3D11 NT handle)
  → gpu.importVideoFrame()          VideoTexture  (BGRA, srcW×srcH)
  → VideoTexture.toRGBA()           Buffer        (RGBA u32[], srcW×srcH)
  → WGSL bilinear dispatch          Buffer        (RGBA u32[], dstW×dstH)
  → SharedOutputTexture.copyFromBuffer
                                    SharedOutputTexture (RGBA, dstW×dstH)
  → D3D11TextureFrameSource → FfmpegD3d11HwEncoder
```

All GPU memory — no pixel data reaches the CPU.

### Example: ultrawide display → H.264

```dart
builder.addScreen(
  displayId: display.deviceId,
  codec: VideoCodec.h264,                    // stays h264 after downscale
  scale: ScreenScalePolicy.h264Friendly,     // 5120×1440 → 4096×1152
);
```

### Example: custom scale

```dart
// Half resolution
builder.addScreen(
  displayId: display.deviceId,
  scale: ScreenScalePolicy.scaleFactor(0.5),
);

// Fixed 1920×1080
builder.addScreen(
  displayId: display.deviceId,
  scale: ScreenScalePolicy.fixedSize(1920, 1080),
);
```

---

## GPU effects pipeline

Screen sources support an ordered chain of GPU post-processing effects applied **after** downscaling. All effects run as WGSL compute shaders on the GPU — no CPU copies, no PCIe round-trips.

Effects are passed to `addScreen()` as a `List<ScreenEffect>`:

```dart
builder.addScreen(
  displayId: display.deviceId,
  scale: ScreenScalePolicy.h264Friendly,
  effects: [
    ScreenEffect.vignette(strength: 0.5),
  ],
);
```

### Built-in effects

| Factory | Description |
|---|---|
| `ScreenEffect.vignette({strength})` | Radial vignette + warm colour grade. `strength` 0–1 (default `0.4`). |

### Custom WGSL effects

Provide your own compute shader source via `ScreenEffect.wgsl()`:

```dart
ScreenEffect.wgsl(
  '''
  struct Params { width: u32, height: u32, gamma: f32, };
  @group(0) @binding(0) var<storage, read_write> pixels : array<u32>;
  @group(0) @binding(1) var<storage, read_write> params : Params;

  @compute @workgroup_size(8, 8, 1)
  fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    if (gid.x >= params.width || gid.y >= params.height) { return; }
    let idx = gid.y * params.width + gid.x;
    // ... transform pixels[idx] in place ...
  }
  ''',
  extraParams: [2.2], // passed as f32 fields from byte 8 in the Params struct
)
```

#### WGSL shader contract

| Binding | Type | Meaning |
|---|---|---|
| `@binding(0)` | `array<u32>` (read_write) | Packed RGBA8 pixels, row-major. Modify in-place. |
| `@binding(1)` | user-defined struct (read_write) | `width: u32` at offset 0, `height: u32` at offset 4, then the `extraParams` values as consecutive `f32` fields from byte 8. |

Workgroups are dispatched at 8×8 threads. Always guard against out-of-bounds: `if (gid.x >= params.width || gid.y >= params.height) { return; }`.

### Effects + scale together

```dart
builder.addScreen(
  displayId: display.deviceId,
  scale: ScreenScalePolicy.h264Friendly,   // 1. downscale on GPU
  effects: [
    ScreenEffect.vignette(strength: 0.4),  // 2. vignette on smaller buffer
  ],
);
```

Downscaling runs first (on the full-resolution buffer), then effects run on the already-smaller destination buffer — maximising efficiency.

### Requirements

- Zero-copy GPU path must be active (`preferZeroCopy = true`, Windows D3D12).  
- If the GPU context is unavailable at runtime, a warning is printed and effects are skipped (encoding continues normally without them).

---

## Builder options

```dart
final builder = RecorderBuilder()
  ..defaultVideoBitrate = 6_000_000   // bits/s
  ..defaultAudioBitrate = 128_000     // bits/s
  ..defaultFrameRate    = 30
  ..backendPreference   = BackendPreference.auto
  ..preferZeroCopy      = true;       // default — safe to leave on
```

---

## Codec selection

The recorder calls `FfmpegBackend.bestCodecForResolution` automatically.  When hardware encoding is preferred and the source (or downscaled) dimensions exceed 4096 px in any dimension, it promotes `h264 → hevc` to stay within hardware encoder limits.  Using `ScreenScalePolicy.h264Friendly` avoids this promotion.

---

## Examples

See [`examples/recorder/`](../examples/recorder/):

| Script | Description |
|---|---|
| `screen_mic.dart` | Screen + microphone → MKV (zero-copy + h264Friendly by default). |
| `camera_mic.dart` | Webcam + microphone → MP4. |
| `screen_mic_loopback_chunked.dart` | Screen + loopback → chunked stream packets. |
