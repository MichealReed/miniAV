## 0.8.1-WIP

## 0.8.0

- Version alignment with the miniav 0.8.0 family release.

## 0.7.4

- Increment downstream deps

## 0.7.3

- Version alignment with the miniAV 0.7.3 family release.

## 0.7.2

- released 08/13/26 - MR

## 0.7.1

- Version bump to keep the miniav 0.7.1 family aligned; no API change in this
  package.

## 0.7.0

## 1.0.0

## 0.6.0

- Add `MiniAVAndroidScreenConsent`, the Android MediaProjection consent helper.
  Call `MiniAVAndroidScreenConsent.requestScreenCapture()` before starting
  screen capture on Android, and listen to `onProjectionStopped` for the user or
  the system revoking it. It runs a `mediaProjection` foreground service and
  hands the projection to the native layer
  (`MiniAV_Screen_SetAndroidMediaProjection`), which makes `miniav_flutter` an
  Android plugin (Dart-only elsewhere).

## 0.5.11

## 0.5.10

## 0.5.9

## 0.5.8

- fix audio buffer allocations and leak issue

## 0.5.7

- Fix logger noisiness

## 0.5.6

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- add setLogCallback and installStderrLogger to route native MiniAV C library
  logs to a Dart callback

## 0.5.5

- fix wasapi loopback issue

## 0.5.4

- adds bindings observer lib to fix crash on hot restart

## 0.5.3

- Initial release. Re-exports `miniav` and auto-registers a
  `WidgetsBindingObserver` that calls `MiniAV.dispose()` on hot restart.
