import 'package:miniav_platform_interface/miniav_platform_interface.dart';

/// Input capture functionality wrapper
class MiniInput {
  MiniInput();

  static MiniInputPlatformInterface get _platform =>
      MiniAVPlatformInterface.instance.input;

  /// Enumerate available gamepad devices
  static Future<List<MiniAVDeviceInfo>> enumerateGamepads() =>
      _platform.enumerateGamepads();

  /// Create an input capture context
  static Future<MiniInputContext> createContext() async {
    final context = await _platform.createContext();
    return MiniInputContext._(context);
  }
}

/// Input capture context for configuration and capture operations
class MiniInputContext {
  final MiniInputContextPlatformInterface _context;

  MiniInputContext._(this._context);

  /// Configure the input capture with the given config.
  /// Must be called before [startCapture].
  Future<void> configure(MiniAVInputConfig config) =>
      _context.configure(config);

  /// Start input capture.
  /// Provide callbacks for each input type you want to receive.
  Future<void> startCapture({
    void Function(MiniAVKeyboardEvent event, Object? userData)? onKeyboard,
    void Function(MiniAVMouseEvent event, Object? userData)? onMouse,
    void Function(MiniAVGamepadEvent event, Object? userData)? onGamepad,
    Object? userData,
  }) => _context.startCapture(
    onKeyboard: onKeyboard,
    onMouse: onMouse,
    onGamepad: onGamepad,
    userData: userData,
  );

  /// Stop input capture
  Future<void> stopCapture() => _context.stopCapture();

  /// Destroy the context and release resources
  Future<void> destroy() => _context.destroy();
}
