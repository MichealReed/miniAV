import 'package:miniav_platform_interface/miniav_platform_interface.dart';

/// Audio input (microphone) capture functionality wrapper
class MiniAudioInput {
  MiniAudioInput();

  static MiniAudioInputPlatformInterface get _platform =>
      MiniAVPlatformInterface.instance.audioInput;

  /// Enumerate available audio input devices
  static Future<List<MiniAVDeviceInfo>> enumerateDevices() =>
      _platform.enumerateDevices();

  /// Get supported audio formats for an input device
  static Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId) =>
      _platform.getSupportedFormats(deviceId);

  /// Get default audio format for an input device
  static Future<MiniAVAudioInfo> getDefaultFormat(String deviceId) =>
      _platform.getDefaultFormat(deviceId);

  /// Create an audio input capture context
  static Future<MiniAudioInputContext> createContext() async {
    final context = await _platform.createContext();
    return MiniAudioInputContext._(context);
  }
}

/// Audio input capture context for configuration and capture operations
class MiniAudioInputContext {
  final MiniAudioInputContextPlatformInterface _context;

  MiniAudioInputContext._(this._context);

  /// Configure the audio input with a device and audio format
  Future<void> configure(String deviceId, MiniAVAudioInfo format) =>
      _context.configure(deviceId, format);

  /// Get the currently configured audio format
  Future<MiniAVAudioInfo> getConfiguredFormat() =>
      _context.getConfiguredFormat();

  /// Start audio input capture
  /// [onData] callback is called for each captured audio buffer
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) => _context.startCapture(onData, userData: userData);

  /// Stop audio input capture
  Future<void> stopCapture() => _context.stopCapture();

  /// Destroy the context and release resources
  Future<void> destroy() => _context.destroy();
}
