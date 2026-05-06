/// WebCodecs backend for miniav_tools (browser only).
///
/// Wraps `VideoEncoder`, `VideoDecoder`, `AudioEncoder`, `AudioDecoder` from
/// the WebCodecs API, and provides a [MediaRecorderCapture] fallback for
/// browsers that lack WebCodecs.
///
/// ### Automatic degradation
///
/// - **WebGPU available** → GPU effects (WGSL via `minigpu_web`) + WebCodecs
///   encoding work.
/// - **No WebGPU** → GPU effects are skipped; WebCodecs encoding still works.
/// - **No WebCodecs** → Use [MediaRecorderCapture] directly as a fallback.
///
/// Check [WebCapability.hasVideoEncoder] and [WebCapability.hasWebGPU] at
/// runtime to branch between paths.
library;

export 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
export 'src/media_recorder_fallback.dart' show MediaRecorderCapture;
export 'src/web_backend.dart' show WebCodecsBackend;
export 'src/web_capability.dart' show WebCapability;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'src/web_backend.dart';

// ignore: unused_element
final _registered = _register();

bool _register() {
  final existing = MiniAVToolsPlatform.instance.backends.any(
    (b) => b.name == WebCodecsBackend.backendName,
  );
  if (existing) return false;
  MiniAVToolsPlatform.instance.register(WebCodecsBackend());
  return true;
}

/// Forces lazy initialization of the auto-registration.
///
/// Call this once at app/test startup if you need the WebCodecsBackend to be
/// available in [MiniAVToolsPlatform.instance] before any other call does so.
// ignore: unused_element
void ensureInitialized() => _registered;
