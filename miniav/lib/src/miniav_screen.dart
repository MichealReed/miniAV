import 'package:miniav_platform_interface/miniav_platform_interface.dart';

/// Screen capture functionality wrapper
class MiniScreen {
  MiniScreen();

  static MiniScreenPlatformInterface get _platform =>
      MiniAVPlatformInterface.instance.screen;

  /// Enumerate available display devices
  static Future<List<MiniAVDeviceInfo>> enumerateDisplays() =>
      _platform.enumerateDisplays();

  /// Enumerate available windows
  static Future<List<MiniAVDeviceInfo>> enumerateWindows() =>
      _platform.enumerateWindows();

  /// Get default formats for screen capture
  static Future<ScreenFormatDefaults> getDefaultFormats(String displayId) =>
      _platform.getDefaultFormats(displayId);

  /// Create a screen capture context
  static Future<MiniScreenContext> createContext() async {
    final context = await _platform.createContext();
    return MiniScreenContext._(context);
  }
}

/// Screen capture context for configuration and capture operations
class MiniScreenContext {
  final MiniScreenContextPlatformInterface _context;

  MiniScreenContext._(this._context);

  /// Configure screen capture for a display
  Future<void> configureDisplay(
    String screenId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) => _context.configureDisplay(screenId, format, captureAudio: captureAudio);

  /// Configure screen capture for a window
  Future<void> configureWindow(
    String windowId,
    MiniAVVideoInfo format, {
    bool captureAudio = false,
  }) => _context.configureWindow(windowId, format, captureAudio: captureAudio);

  /// Get the currently configured formats
  Future<ScreenFormatDefaults> getConfiguredFormats() =>
      _context.getConfiguredFormats();

  /// Start screen capture
  /// [onFrame] callback is called for each captured frame
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  }) => _context.startCapture(onFrame, userData: userData);

  /// Stop screen capture
  Future<void> stopCapture() => _context.stopCapture();

  /// Destroy the context and release resources
  Future<void> destroy() => _context.destroy();
}
