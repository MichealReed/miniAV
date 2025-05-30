import 'package:miniav_platform_interface/miniav_platform_interface.dart';

/// Loopback (system audio) capture functionality wrapper
class MiniLoopback {
  MiniLoopback();

  static MiniLoopbackPlatformInterface get _platform =>
      MiniAVPlatformInterface.instance.loopback;

  /// Enumerate available loopback devices
  static Future<List<MiniAVDeviceInfo>> enumerateDevices() =>
      _platform.enumerateDevices();

  /// Get default audio format for a loopback device
  static Future<MiniAVAudioInfo> getDefaultFormat(String deviceId) =>
      _platform.getDefaultFormat(deviceId);

  /// Create a loopback capture context
  static Future<MiniLoopbackContext> createContext() async {
    final context = await _platform.createContext();
    return MiniLoopbackContext._(context);
  }
}

/// Loopback capture context for configuration and capture operations
class MiniLoopbackContext {
  final MiniLoopbackContextPlatformInterface _context;

  MiniLoopbackContext._(this._context);

  /// Configure the loopback capture with a device and audio format
  Future<void> configure(String deviceId, MiniAVAudioInfo format) =>
      _context.configure(deviceId, format);

  /// Get the currently configured audio format
  Future<MiniAVAudioInfo> getConfiguredFormat() =>
      _context.getConfiguredFormat();

  /// Start loopback capture
  /// [onData] callback is called for each captured audio buffer
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) => _context.startCapture(onData, userData: userData);

  /// Stop loopback capture
  Future<void> stopCapture() => _context.stopCapture();

  /// Destroy the context and release resources
  Future<void> destroy() => _context.destroy();
}
