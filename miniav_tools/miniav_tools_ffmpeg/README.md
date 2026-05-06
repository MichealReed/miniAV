# miniav_tools_ffmpeg

FFmpeg backend for [`miniav_tools`](../miniav_tools).
Wraps `libavcodec` / `libavformat` / `libavutil` over FFI and self-registers
with the `miniav_tools_platform_interface` registry on import.

> Importing `package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart` is enough.
> Once registered, `MiniAVTools.createEncoder(...)` etc. will pick this
> backend whenever it can satisfy the requested codec/container.

## What it provides

- **Software encoders**: H.264 / HEVC / VP9 / VP8 / AV1 / MJPEG / ProRes via
  libx264, libx265, libvpx, libaom, etc.
- **Stage A hardware encoders** (CPU frame in → encoded packet out):
  NVENC, AMF, QSV, VideoToolbox, MediaFoundation, V4L2 M2M.
- **Stage B zero-copy D3D11 encoder** on Windows: takes an
  `ID3D11Texture2D` NT shared handle directly. No PCIe transfer, no colour
  conversion, no readback. See [Stage B](#stage-b--zero-copy-d3d11-windows).
- **Muxers**: MP4, Matroska/WebM, MPEG-TS — with file, byte-buffer, and
  streaming-callback outputs.
- **Decoder + demuxer** for the same set of codecs/containers.

## Auto-download of FFmpeg shared libraries

On first `ensureFFmpegLoaded()` (called implicitly by `createEncoder` etc.)
the package downloads BtbN's GPL-shared FFmpeg build for the current OS
into `${HOME}/.miniav_tools_ffmpeg/` and loads the DLLs / .so / .dylib from
there. Set:

| Variable | Effect |
|---|---|
| `MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD=1` | Disable auto-download — caller must set `FFMPEG_LIB_DIR` |
| `MINIAV_TOOLS_FFMPEG_CACHE=<path>` | Override the cache directory |
| `FFMPEG_LIB_DIR=<path>` | Use FFmpeg libs from a specific directory |

## Stage B — zero-copy D3D11 (Windows)

When the source frame already lives in a D3D11 texture (DXGI screen
capture, minigpu compute output, browser GPU canvas via D3D11 interop, …)
the encoder pulls it straight into the hwframes pool with a single
`CopySubresourceRegion` between two GPU-resident textures.

```dart
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';

await ensureFFmpegLoaded();

final enc = FfmpegD3d11HwEncoder.open(EncoderConfig(
  codec: VideoCodec.hevc,
  width: 1920, height: 1080,
  bitrateBps: 6_000_000,
  hwAccel: HwAccelPreference.required,
));

final pkt = await enc.encode(FrameSource.d3d11Texture(
  texturePtr: ntHandle.address,        // DXGI NT shared handle
  width: 1920, height: 1080,
  pixelFormat: MiniAVPixelFormat.bgra32,
  timestampUs: i * 33333,
));
```

### Vendor selection

`open(cfg, vendorOrder: ...)` walks the list in priority order, opens the
first vendor that succeeds, and returns the encoder. The default order is
**AMF → QSV → MediaFoundation**. NVENC has its own CUDA path and is
selected automatically by `FfmpegHwEncoder.open` when zero-copy is
requested with an NVIDIA GPU.

To force a single vendor and surface the raw failure, call:

```dart
final enc = FfmpegD3d11HwEncoder.openWith(cfg, D3d11HwVendor.amf);
```

### Sharing a `ID3D11Device` with another GPU API (`existingD3d11Device`)

Cross-API NT-handle sharing only works **when both producer and consumer
are on the same DXGI adapter.** Different adapters fail with
`E_INVALIDARG` from `OpenSharedResource1`. To pin FFmpeg's D3D11 device to
a specific adapter — typically the one Dawn / WebGPU is already using —
pass an existing `ID3D11Device*`:

```dart
// 1) Get the cached D3D11 device that minigpu created on the Dawn adapter.
final d3d11DevicePtr = gpu.createD3D11DeviceOnDawnAdapter();

// 2) Hand it to FFmpeg. FFmpeg AddRef's the device; you may continue to
//    use it for your own work.
final enc = FfmpegD3d11HwEncoder.openWith(
  cfg,
  D3d11HwVendor.nvenc,                  // or .amf / .qsv / .mediaFoundation
  existingD3d11Device: d3d11DevicePtr,  // address of an ID3D11Device*
);
```

When `existingD3d11Device == 0` (the default) FFmpeg creates its own
device on adapter 0 (the display adapter) — fine for the single-adapter
case.

### Source texture format (`sourceTextureFormat`)

The hwframes pool the encoder allocates is bound to a single DXGI format.
`CopySubresourceRegion` requires the source and destination textures to
be in the **same DXGI type group** (BGRA cannot be copied to RGBA), so
the pool's `sw_format` must match the format of the textures the caller
will hand the encoder in `encode(...)`.

| `sourceTextureFormat` | DXGI source format | Use for |
|---|---|---|
| `D3d11HwSourceFormat.bgra` (default) | `DXGI_FORMAT_B8G8R8A8_UNORM` | DXGI Desktop Duplication, Windows.Graphics.Capture, miniav screen capture, minigpu `SharedOutputTexture` (BGRA8 storage) |
| `D3d11HwSourceFormat.rgba` | `DXGI_FORMAT_R8G8B8A8_UNORM` | Direct copies from RGBA8 storage textures (some custom WebGPU pipelines) |

Not every driver accepts RGBA in a D3D11VA hwframes pool — if it doesn't,
`av_hwframe_ctx_init` returns an error and `openWith` raises a
`CodecInitException` describing the format. BGRA is universally supported
on AMF / QSV / NVENC / MediaFoundation, which is why it is the default.

## Tests

```pwsh
dart test                                 # full suite
dart test test/d3d11_hw_encoder_test.dart # Stage B only
```

Tests are tagged `windows-gpu` and skip cleanly on machines without
FFmpeg, the shim asset, or a D3D11VA-capable encoder. The end-to-end test
synthesises an NT-shared BGRA texture via the test-only shim helpers — no
display or capture device required.

## License

Apache 2.0
