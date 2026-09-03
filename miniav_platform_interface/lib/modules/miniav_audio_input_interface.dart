import '../miniav_platform_types.dart';

/// Abstract interface for audio input (microphone) capture functionality.
abstract class MiniAudioInputPlatformInterface {
  /// Enumerate available audio input (microphone) devices.
  Future<List<MiniAVDeviceInfo>> enumerateDevices();

  /// Get supported audio formats for a given input device.
  Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId);

  /// Get default audio format for a given input device.
  Future<MiniAVAudioInfo> getDefaultFormat(String deviceId);

  /// Create an audio input capture context.
  Future<MiniAudioInputContextPlatformInterface> createContext();

  /// Subscribe to audio input device add/remove notifications.
  void Function() addDeviceChangeListener(
    MiniAVDeviceChangeListener listener,
  ) => throw UnsupportedError('Device-change subscription not supported.');
}

/// Abstract audio input context for configuring and capturing from a microphone.
abstract class MiniAudioInputContextPlatformInterface {
  /// Configure the audio input context with a device and format.
  Future<void> configure(String deviceId, MiniAVAudioInfo format);

  /// Get the configured format.
  Future<MiniAVAudioInfo> getConfiguredFormat();

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

  /// Subscribe to a one-shot lost notification (microphone unplugged, etc.).
  void Function() addLostListener(MiniAVContextLostListener listener) =>
      throw UnsupportedError('Context-lost subscription not supported.');

  /// Hand captured audio to ANOTHER THREAD without going through [startCapture].
  ///
  /// 🔴 On web the callback path is drained by a timer on the MAIN thread, and
  /// that timer is the app's largest fixed cost — while the ring behind it is
  /// filled by an `AudioWorklet` on a real audio thread. A mirror is memory
  /// both threads can see, so a worker can take the audio directly and the
  /// main thread stops being in the path at all.
  ///
  /// **Opening a mirror makes it THE delivery path**: an implementation stops
  /// its own drain, so [startCapture]'s callback goes quiet. Close it to get
  /// the callback back.
  ///
  /// Answers null where there is no such thing — the caller's fallback is the
  /// ordinary callback path, so this is a capability question rather than an
  /// error. `capacityFrames` 0 asks for the implementation's default depth.
  Future<MiniAVCaptureMirrorHandle?> openCaptureMirror({
    int capacityFrames = 0,
  }) async =>
      null;

  /// Detach the mirror and resume the ordinary delivery path. Safe to call
  /// when none is open.
  Future<void> closeCaptureMirror() async {}
}
