import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'miniav_ffi_bindings.dart' as bindings;
import 'miniav_ffi_camera.dart';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';

// Export camera FFI implementation for external use
export 'miniav_ffi_camera.dart';

// --- Platform Implementation ---

class MiniAVFFIPlatform extends MiniAVPlatformInterface {
  MiniAVFFIPlatform();

  final MiniFFICameraPlatform _camera = MiniFFICameraPlatform();
  // TODO: Add screen/audio/loopback implementations as you create them

  @override
  MiniCameraPlatformInterface get camera => _camera;

  @override
  MiniScreenPlatformInterface get screen =>
      throw UnimplementedError('Screen capture not implemented for FFI');

  @override
  MiniAudioInputPlatformInterface get audioInput =>
      throw UnimplementedError('Audio input not implemented for FFI');

  @override
  MiniLoopbackPlatformInterface get loopback =>
      throw UnimplementedError('Loopback not implemented for FFI');

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

// --- Registration ---

MiniAVPlatformInterface registeredInstance() => MiniAVFFIPlatform();
