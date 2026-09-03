import 'backend.dart';

/// Fallback for targets with neither `dart:ffi` nor `dart:js_interop`.
MediaSessionBackend createMediaSessionBackend({
  required String appName,
  int? hostWindowHandle,
}) => UnsupportedMediaSessionBackend(
  'no media-session backend for this compilation target',
);
