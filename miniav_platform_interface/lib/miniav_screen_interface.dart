import 'miniav_platform_types.dart';

/// Abstract interface for screen capture functionality on all platforms.
abstract class MiniScreenPlatformInterface {
  /// Enumerate available screens
  Future<List<MiniAVDeviceInfo>> enumerateScreens();

  /// Enumerate available windows
  Future<List<MiniAVDeviceInfo>> enumerateWindows();

  /// Get supported video formats for a given screen or window.
  Future<List<MiniAVVideoFormatInfo>> getSupportedFormats(String screenId);

  /// Create a screen capture context (for capture/configuration).
  Future<MiniScreenContextPlatformInterface> createContext();
}

/// Abstract screen context for configuring and capturing from a screen or window.
abstract class MiniScreenContextPlatformInterface {
  /// Configure the screen context with a screen/window and format.
  Future<void> configure(String screenId, MiniAVVideoFormatInfo format);

  /// Start screen capture.
  /// [onFrame] is called for each frame received.
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  });

  /// Stop screen capture.
  Future<void> stopCapture();

  /// Destroy this screen context and release resources.
  Future<void> destroy();
}
