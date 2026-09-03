import 'dart:io';

import 'backend.dart';
import 'backend_ffi.dart';
import 'backend_mpris.dart';

/// Native targets.
///
/// Linux is the odd one out: its backend is pure Dart, because MPRIS is a
/// D-Bus wire protocol rather than an OS API, so there is nothing a native
/// translation unit could do that Dart cannot — and doing it here avoids a
/// `libdbus-1` system dependency. Everything else goes through the code asset.
MediaSessionBackend createMediaSessionBackend({
  required String appName,
  int? hostWindowHandle,
}) {
  if (Platform.isLinux) {
    return MprisMediaSessionBackend(appName: appName);
  }
  return FfiMediaSessionBackend(
    appName: appName,
    hostWindowHandle: hostWindowHandle,
  );
}
