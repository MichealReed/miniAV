# Changelog

## 0.1.0

- Initial release. FFmpeg-backed encoder, decoder, muxer and demuxer
  registered against `miniav_tools_platform_interface`.
- Software encode for H.264 / HEVC / VP9 / VP8 / AV1 / MJPEG / ProRes via
  libavcodec.
- Stage A hardware encode (CPU frame in, encoded packet out) using
  NVENC / AMF / QSV / VideoToolbox / MediaFoundation / V4L2 M2M.
- Stage B zero-copy D3D11 encode on Windows: takes an `ID3D11Texture2D` NT
  shared handle directly without any PCIe transfer or colour conversion.
  - `FfmpegD3d11HwEncoder.openWith(cfg, vendor, existingD3d11Device, sourceTextureFormat)`
    lets callers inject their own `ID3D11Device*` so the encoder runs on the
    same DXGI adapter as an external GPU API (Dawn / WebGPU). Required for
    cross-API NT-handle sharing — different adapters fail with `E_INVALIDARG`.
  - `sourceTextureFormat` selects `bgra` (default; matches DXGI screen
    capture and minigpu `SharedOutputTexture`) or `rgba`. The hwframes pool
    is allocated with this `sw_format` so `CopySubresourceRegion` from the
    caller's texture stays in the same DXGI type group.
- MP4 / Matroska / MPEG-TS muxer with byte-buffer, file and streaming
  callback outputs. Container-level fragmenting for low-latency streaming.
- Auto-download of FFmpeg shared libraries (BtbN GPL builds) on first run;
  set `MINIAV_TOOLS_FFMPEG_NO_AUTODOWNLOAD=1` to opt out.
