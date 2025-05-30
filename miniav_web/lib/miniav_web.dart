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

/// Registers the web implementation of MiniAV
MiniAVPlatformInterface registeredInstance() => MiniAVWebImpl();

/// Web implementation of MiniAV platform interface
class MiniAVWebImpl extends MiniAVPlatformInterface {
  static bool _isRegistered = false;

  late final MiniCameraPlatformInterface _camera;
  late final MiniScreenPlatformInterface _screen;
  late final MiniAudioInputPlatformInterface _audioInput;
  late final MiniLoopbackPlatformInterface _loopback;

  MiniAVWebImpl() {
    if (!_isRegistered) {
      _register();
      _isRegistered = true;
    }

    _camera = CameraControllerWeb();
    _screen = ScreenControllerWeb();
    _audioInput = AudioControllerWeb();
    _loopback = LoopbackControllerWeb();
  }

  static void _register() {
    MiniAVPlatformInterface.instance = MiniAVWebImpl();
  }

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
}
