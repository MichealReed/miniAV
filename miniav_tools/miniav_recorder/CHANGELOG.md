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

- bump `miniav_tools_ffmpeg` to ^0.2.6 (fix missing `dart:convert` import that caused compile error in 0.2.5).

## 0.2.5

- bump `miniav_tools_ffmpeg` to ^0.2.5 to pick up the allowMalformed UTF-8 fix (FormatException on FFmpeg log messages with non-UTF-8 bytes such as Latin-1 filenames).
- fix: loopback/mixed audio crackles caused by the `_busyEncode` drop pattern. When `dispatchPacket` (file muxer write) yielded to the Dart event loop, the next 10 ms loopback chunk would fire, hit the busy guard, and be silently discarded — advancing `_framesOut` without emitting audio, creating a PTS hole heard as a pop/crackle. Replaced with a sequential `_encodeChain` future so chunks always queue in order and are never dropped.

## 0.2.4

- bump `miniav_tools_ffmpeg` to ^0.2.4 to pick up the FfmpegShim.tryLoad cache-poisoning fix (audio encoder failed when `Recorder.setLogLevel`/`setLogCallback` was called before FFmpeg was loaded).

## 0.2.3

- RecorderLogLevel and RecorderLogSource enums; Recorder.setLogLevel, setLogCallback; internal logs routed through callback; 30 new tests in log_level_test.dart
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

- Initial release.
- Multi-source A/V recorder built on `miniav` and `miniav_tools`.
- Synchronised capture from screen, camera, microphone, and loopback audio.
- FFmpeg-backed muxing to MP4/MKV files and chunked streams via `miniav_tools_ffmpeg`.
- Zero-copy GPU screen-capture path on Windows via shared D3D11 device.
