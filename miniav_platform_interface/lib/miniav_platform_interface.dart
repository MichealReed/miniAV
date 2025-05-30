import 'modules/miniav_camera_interface.dart';
import 'modules/miniav_screen_interface.dart';
import 'modules/miniav_audio_input_interface.dart';
import 'modules/miniav_loopback_interface.dart';

export 'miniav_platform_types.dart';
export 'modules/miniav_camera_interface.dart';
export 'modules/miniav_screen_interface.dart';
export 'modules/miniav_audio_input_interface.dart';
export 'modules/miniav_loopback_interface.dart';

// Conditional import for platform-specific implementation
import 'platform_stub/miniav_platform_stub.dart'
    if (dart.library.ffi) 'package:miniav_ffi/miniav_ffi.dart'
    if (dart.library.js) 'package:miniav_web/miniav_web.dart';

// Abstract interface
abstract class MiniAVPlatformInterface {
  MiniAVPlatformInterface();

  static MiniAVPlatformInterface? _instance;
  static MiniAVPlatformInterface get instance {
    _instance ??= registeredInstance();
    return _instance!;
  }

  static set instance(MiniAVPlatformInterface instance) {
    _instance = instance;
  }

  static MiniAVPlatformInterface createMiniAVPlatform() =>
      throw UnsupportedError('No platform implementation available.');

  MiniCameraPlatformInterface get camera;
  MiniScreenPlatformInterface get screen;
  MiniAudioInputPlatformInterface get audioInput;
  MiniLoopbackPlatformInterface get loopback;

  String getVersionString();
  void setLogLevel(int level);
  void dispose();
}
