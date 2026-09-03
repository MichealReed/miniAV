## 0.7.3

- New Release
- Version alignment with the miniAV 0.7.3 family release.
## 0.7.2

- released 08/13/26 - MR
## 0.7.1

- Version bump to keep the miniav 0.7.1 family aligned; inherits the Windows
  camera teardown and COM/MF lifetime fixes from miniav_ffi 0.7.1. No API
  change in this package.

## 0.7.0

## 1.0.0

## 0.6.0

- add Android MediaProjection consent helper (`MiniAVAndroidScreenConsent`):
  Kotlin MethodChannel plugin + typed `mediaProjection` foreground service +
  JNI handoff of the projection to the pure-FFI native layer
  (`MiniAV_Screen_SetAndroidMediaProjection`). Call
  `MiniAVAndroidScreenConsent.requestScreenCapture()` before starting MiniAV
  screen capture on Android; listen to `onProjectionStopped` for user/system
  revoke. This makes `miniav_flutter` an Android plugin (Dart-only elsewhere).

## 0.5.11

## 0.5.10

## 0.5.9

## 0.5.8

- fix audio buffer allocations and leak issue
## 0.5.7

- Fix logger noisiness
## 0.5.6

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- add setLogCallback and installStderrLogger to route native MiniAV C library logs to a Dart callback

## 0.5.5

- fix wasapi loopback issue

## 0.5.4

- adds bindings observer lib to fix crash on hot restart

## 0.5.3

- Initial release. Re-exports `miniav` and auto-registers a `WidgetsBindingObserver` that calls `MiniAV.dispose()` on hot restart.
