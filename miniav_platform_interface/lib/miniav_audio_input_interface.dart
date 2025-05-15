import 'miniav_platform_types.dart';

/// Abstract interface for audio input (microphone) capture functionality.
abstract class MiniAudioInputPlatformInterface {
  /// Enumerate available audio input (microphone) devices.
  Future<List<MiniAVDeviceInfo>> enumerateDevices();

  /// Get supported audio formats for a given input device.
  Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId);

  /// Create an audio input capture context.
  Future<MiniAudioInputContextPlatformInterface> createContext();
}

/// Abstract audio input context for configuring and capturing from a microphone.
abstract class MiniAudioInputContextPlatformInterface {
  /// Configure the audio input context with a device and format.
  Future<void> configure(String deviceId, MiniAVAudioInfo format);

  /// Start audio input capture.
  /// [onData] is called for each audio buffer received.
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  });

  /// Stop audio input capture.
  Future<void> stopCapture();

  /// Destroy this audio input context and release resources.
  Future<void> destroy();
}
