# Changelog

## 0.6.0

- Requires miniav_platform_interface 0.8.0 and
  miniav_tools_platform_interface 0.6.0. No other changes.

## 0.5.9

- Requires spawn ^0.1.1: native transfers actually transfer, and a web message
  the worker cannot deserialize is reported instead of vanishing.

## 0.5.8

- Increment downstream deps

## 0.5.7

- New `Muxer.platform`, like `AudioEncoder.platform`, for backend-specific
  diagnostics such as `Mp4Muxer.timingReports`.

## 0.5.6

- Version bump so the dependency on miniav_tools_platform_interface can move
  to ^0.5.4. No API or behaviour change.

## 0.5.5

- Declares `miniav_platform_interface` as a direct dependency; it was imported
  directly but resolved only through another package's dependency.

## 0.5.4

- Internal dependencies are caret ranges instead of exact pins, which made each
  patch release unsatisfiable next to already-published packages.
- Republished: 0.5.3 pinned `miniav_tools_platform_interface: 0.5.2` exactly and
  could not resolve next to packages needing 0.5.3.

## 0.5.3

- `MiniAVTools.createAudioDecoder` and an `AudioDecoder` facade, routed by
  `supportsAudioDecode` like `createAudioEncoder`.
- The `Demuxer` facade exposes `durationUs` and `isSeekable`; `seek` throws on
  non-seekable (live) inputs.

## 0.5.2

## 0.5.1

## 0.5.0

- Version bump to keep the miniav_tools family in lockstep; no changes in this
  package.

## 0.4.10

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Increment to keep in step with others.

## 0.4.6

- Increment to keep in step with others.

## 0.4.5

- Version bump for coordinated release with `miniav_recorder` 0.4.5.

## 0.4.4

- fixing recorder loopback drift

## 0.4.3

- audio data issue, increment miniav

## 0.4.2

- fix timing issue

## 0.4.1

- fix audio timing, add frame duplication

## 0.4.0

- fix frame rate scheduling

## 0.3.12

- fused shader cache fix

## 0.3.11

- Use GPU until we cant.

## 0.3.9

- AMF Fix, fix unknown audio error

## 0.3.8

- Fix vendor Order

## 0.3.7

- fix NV12 path

## 0.3.6

- fix cpu path

## 0.3.5

- fix recorder sync drift

## 0.3.4

- attempt fix resolution issue

## 0.3.3

- fix precheck

## 0.3.2

- fix property

## 0.3.1

- fix scaling crazy, attempt fix other HW encoders

## 0.3.0

- fix recorder logging, Tier A path, deps to 1.5.0

## 0.2.21

- increments minigpu to 1.4.15

## 0.2.20

- increments minigpu to 1.4.14

## 0.2.19

- increments minigpu to 1.4.12

## 0.2.18

- increments minigpu to 1.4.11

## 0.2.17

- increments minigpu to 1.4.9

## 0.2.16

- increments minigpu to 1.4.8, hopefully fix cpu fallback

## 0.2.15

- increments minigpu to 1.4.7

## 0.2.14

- fixes unicode, increments minigpu to 1.4.7

## 0.2.12

- Increment minigpu to 1.4.6

## 0.2.11

## 0.2.9

## 0.2.8

## 0.2.7

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- Increment minigpu to 1.4.4
- Add `RecorderLogSource.minigpu`, routing native minigpu/Dawn log lines through
  the unified `Recorder` log callback, and the public `Recorder.minigpuLevelFor`
  helper.

## 0.2.5

## 0.2.4

## 0.2.3

- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all
  native logs (MiniAV + FFmpeg) through a single Dart callback

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

## 0.1.0 — 2026-05-02

- Initial release. Provides `MiniAVTools` facade routing
  `createEncoder` / `createDecoder` / `createMuxer` / `createDemuxer` calls
  to registered backends.
