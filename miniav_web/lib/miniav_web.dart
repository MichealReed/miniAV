import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import 'package:web/web.dart' as web;

export 'package:miniav_platform_interface/miniav_platform_interface.dart';

part 'modules/miniav_web_camera.dart';
part 'modules/miniav_web_screen.dart';
part 'modules/miniav_web_audio_input.dart';
part 'modules/miniav_web_loopback.dart';
part './miniav_web_utils.dart';

/// Web implementation of MiniAV platform interface
class MiniAVWebPlatform extends MiniAVPlatformInterface {
  MiniAVWebPlatform();

  final MiniCameraPlatformInterface _camera = MiniAVWebCameraPlatform();
  final MiniScreenPlatformInterface _screen = MiniAVWebScreenPlatform();
  final MiniAudioInputPlatformInterface _audioInput = MiniAVWebAudioInputPlatform();
  final MiniLoopbackPlatformInterface _loopback = MiniAVWebLoopbackPlatform();

  @override
  MiniCameraPlatformInterface get camera => _camera;

  @override
  MiniScreenPlatformInterface get screen => _screen;

  @override
  MiniAudioInputPlatformInterface get audioInput => _audioInput;

  @override
  MiniLoopbackPlatformInterface get loopback => _loopback;

  @override
  String getVersionString() => '1.0.0-web';

  @override
  void setLogLevel(int level) {
    // Web implementation uses console logging
    // Could be extended to filter based on level
  }

  @override
  void dispose() {}

  @override
  Future<void> releaseBuffer(MiniAVBuffer buffer) async {
    // Web does not require explicit buffer release
    // This can be a no-op or implement custom logic if needed
  }
}

/// Registers the web implementation of MiniAV
MiniAVPlatformInterface registeredInstance() => MiniAVWebPlatform();
