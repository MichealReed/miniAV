import 'miniav_platform_types.dart';

/// Abstract interface for screen capture functionality on all platforms.
abstract class MiniScreenPlatformInterface {
  /// Enumerate available displays
  Future<List<MiniAVDeviceInfo>> enumerateDisplays();

  /// Enumerate available windows
  Future<List<MiniAVDeviceInfo>> enumerateWindows();

  /// Get default formats for display and loopback devices.
  Future<ScreenFormatDefaults> getDefaultFormats(String displayId);

  /// Create a screen capture context (for capture/configuration).
  Future<MiniScreenContextPlatformInterface> createContext();
}

/// Abstract screen context for configuring and capturing from a screen or window.
abstract class MiniScreenContextPlatformInterface {
  /// Configure the screen context with a display and format.
  Future<void> configureDisplay(
    String screenId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  });

  /// Configure the screen context with a window and format.
  Future<void> configureWindow(
    String windowId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  });

  Future<ScreenFormatDefaults> getConfiguredFormats();

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
