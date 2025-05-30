import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:miniav_ffi/modules/miniav_ffi_audio_input.dart';
import 'package:miniav_ffi/modules/miniav_ffi_loopback.dart';
import 'miniav_ffi_bindings.dart' as bindings;
import 'modules/miniav_ffi_camera.dart';
import 'modules/miniav_ffi_screen.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';

// Export camera FFI implementation for external use
export 'modules/miniav_ffi_camera.dart';
export 'modules/miniav_ffi_screen.dart';
export 'modules/miniav_ffi_audio_input.dart';
export 'modules/miniav_ffi_loopback.dart';

// --- Platform Implementation ---

class MiniAVFFIPlatform extends MiniAVPlatformInterface {
  MiniAVFFIPlatform();

  final MiniFFICameraPlatform _camera = MiniFFICameraPlatform();
  final MiniFFIScreenPlatform _screen = MiniFFIScreenPlatform();
  final MiniAVFFILoopbackPlatform _loopback = MiniAVFFILoopbackPlatform();
  final MiniAVFFIAudioInputPlatform _audioInput = MiniAVFFIAudioInputPlatform();

  @override
  MiniCameraPlatformInterface get camera => _camera;

  @override
  MiniScreenPlatformInterface get screen => _screen;

  @override
  MiniAudioInputPlatformInterface get audioInput => _audioInput;

  @override
  MiniLoopbackPlatformInterface get loopback => _loopback;

  @override
  String getVersionString() {
    final ptr = bindings.MiniAV_GetVersionString();
    if (ptr == ffi.nullptr) return "Unknown Version";
    return ptr.cast<Utf8>().toDartString();
  }

  @override
  void setLogLevel(int level) {
    final result = bindings.MiniAV_SetLogLevel(
      bindings.MiniAVLogLevel.values[level],
    );
    if (result != bindings.MiniAVResultCode.MINIAV_SUCCESS) {
      throw Exception('Failed to set log level');
    }
  }

  @override
  void dispose() {
    // Implement any necessary cleanup here
  }
}

MiniAVPlatformInterface registeredInstance() => MiniAVFFIPlatform();
