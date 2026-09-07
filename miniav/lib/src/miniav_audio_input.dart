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

  /// Subscribe to audio input device add/remove notifications.
  /// Returns a disposer that must be called to unsubscribe.
  static void Function() addDeviceChangeListener(
    MiniAVDeviceChangeListener listener,
  ) => _platform.addDeviceChangeListener(listener);
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

  /// Subscribe to a context-lost notification (microphone unplugged, etc.).
  /// Fired from a capture thread; do NOT call [destroy] synchronously from
  /// inside the listener. Returns a disposer that must be called to
  /// unsubscribe.
  void Function() addLostListener(MiniAVContextLostListener listener) =>
      _context.addLostListener(listener);

  /// Hand captured audio to another thread instead of to [startCapture]'s
  /// callback. Null where the platform has no such thing — the caller's
  /// fallback is the callback path, so this is a capability question, not an
  /// error. See `MiniAudioInputContextPlatformInterface.openCaptureMirror`.
  Future<MiniAVCaptureMirrorHandle?> openCaptureMirror({
    int capacityFrames = 0,
  }) =>
      _context.openCaptureMirror(capacityFrames: capacityFrames);

  /// Detach the mirror and resume the ordinary delivery path.
  Future<void> closeCaptureMirror() => _context.closeCaptureMirror();
}
