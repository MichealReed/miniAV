# Changelog

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

- fix: add missing `dart:convert` import for `Utf8Decoder` (compilation error introduced in 0.2.5).

## 0.2.5

- fix: `FfmpegShim.setFfmpegLogCallback` now uses `Utf8Decoder(allowMalformed: true)` when decoding native C strings, so FFmpeg log messages containing non-UTF-8 bytes (Latin-1 filenames, Windows-1252 error strings, etc.) no longer throw `FormatException: Unexpected extension byte`.

## 0.2.4

- fix: `FfmpegShim.tryLoad()` no longer poisons its cache when called before FFmpeg has been loaded. The shim DLL imports avcodec/avutil; if those aren't loaded yet on Windows, the shim load fails and previously the failure was cached forever — breaking the audio encoder when `Recorder.setLogLevel`/`setLogCallback` was called early. tryLoad now skips silently (without caching) until FFmpeg is loaded.

## 0.2.3

- FFmpeg log forwarding shim bridge (miniav_shim_set_ffmpeg_log_callback, miniav_shim_set_ffmpeg_log_level); FfmpegShim.setFfmpegLogLevel, setFfmpegLogCallback; ABI bumped to 8; export FfmpegShim from barrel
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
