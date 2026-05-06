## 0.1.0

- Initial release.
- Multi-source A/V recorder built on `miniav` and `miniav_tools`.
- Synchronised capture from screen, camera, microphone, and loopback audio.
- FFmpeg-backed muxing to MP4/MKV files and chunked streams via `miniav_tools_ffmpeg`.
- Zero-copy GPU screen-capture path on Windows via shared D3D11 device.
