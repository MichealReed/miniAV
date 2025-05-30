import 'package:miniav_platform_interface/miniav_platform_interface.dart';
import './src/miniav_audio_input.dart';
import './src/miniav_camera.dart';
import './src/miniav_loopback.dart';
import './src/miniav_screen.dart';

export 'package:miniav_platform_interface/miniav_platform_interface.dart';
export './src/miniav_audio_input.dart';
export './src/miniav_camera.dart';
export './src/miniav_loopback.dart';
export './src/miniav_screen.dart';

/// Main MiniAV library providing cross-platform audio/video capture functionality.
class MiniAV {
  static MiniAVPlatformInterface get _platform =>
      MiniAVPlatformInterface.instance;

  /// Camera capture functionality
  static MiniCamera get camera => MiniCamera();

  /// Screen capture functionality
  static MiniScreen get screen => MiniScreen();

  /// Audio input (microphone) capture functionality
  static MiniAudioInput get audioInput => MiniAudioInput();

  /// Loopback (system audio) capture functionality
  static MiniLoopback get loopback => MiniLoopback();

  /// Get the version string of the MiniAV library
  static String getVersion() => _platform.getVersionString();

  /// Set the log level for the MiniAV library
  static void setLogLevel(MiniAVLogLevel level) =>
      _platform.setLogLevel(level.index);

  /// Dispose of all MiniAV resources
  static void dispose() => _platform.dispose();

  /// Release a buffer previously obtained from MiniAV
  static Future<void> releaseBuffer(MiniAVBuffer buffer) async {
    return _platform.releaseBuffer(buffer);
  }
}
