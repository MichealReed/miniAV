# Changelog

## 0.1.0

- Initial release. Pure-WGSL codec backend for `miniav_tools` running entirely
  on minigpu's WebGPU compute pipeline.
- MJPEG encoder: RGBA → YCbCr → DCT → quantize → Huffman → JFIF emitted as a
  self-contained `.jpg` byte stream (plays in browsers, VLC, QuickTime,
  ffmpeg). No native FFmpeg dependency — works anywhere minigpu works,
  including web (WebGPU).
- `crfQuality` 1..31 maps to JPEG quality 90..10 for parity with FFmpeg's
  `-q:v` semantics.
