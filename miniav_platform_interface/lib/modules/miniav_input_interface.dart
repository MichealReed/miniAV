import '../miniav_platform_types.dart';

/// Abstract interface for input capture functionality on all platforms.
abstract class MiniInputPlatformInterface {
  /// Enumerate available gamepad devices.
  Future<List<MiniAVDeviceInfo>> enumerateGamepads();

  /// Create an input capture context.
  Future<MiniInputContextPlatformInterface> createContext();
}

/// Abstract input context for configuring and capturing input events.
abstract class MiniInputContextPlatformInterface {
  /// Configure the input context with the given config.
  Future<void> configure(MiniAVInputConfig config);

  /// Start input capture.
  /// Provide callbacks for each input type you want to receive.
  Future<void> startCapture({
    void Function(MiniAVKeyboardEvent event, Object? userData)? onKeyboard,
    void Function(MiniAVMouseEvent event, Object? userData)? onMouse,
    void Function(MiniAVGamepadEvent event, Object? userData)? onGamepad,
    Object? userData,
  });

  /// Stop input capture.
  Future<void> stopCapture();

  /// Destroy this input context and release resources.
  Future<void> destroy();
}
