part of '../miniav_web.dart';

/// Web implementation of [MiniLoopbackPlatformInterface]
class LoopbackControllerWeb implements MiniLoopbackPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    // Web doesn't support system audio loopback capture
    return [];
  }

  @override
  Future<MiniAVAudioInfo> getDefaultFormat(String targetId) async {
    // Web doesn't support system audio loopback capture
    throw UnsupportedError(
      'Loopback audio capture not supported on web platform',
    );
  }

  @override
  Future<MiniLoopbackContextPlatformInterface> createContext() async {
    throw UnsupportedError(
      'Loopback audio capture not supported on web platform',
    );
  }
}

/// Web stub for [MiniLoopbackContextPlatformInterface] (not actually used)
class WebLoopbackContext implements MiniLoopbackContextPlatformInterface {
  @override
  Future<void> configure(String targetId, MiniAVAudioInfo format) async {
    throw UnsupportedError(
      'Loopback audio capture not supported on web platform',
    );
  }

  @override
  Future<MiniAVAudioInfo> getConfiguredFormat() async {
    throw UnsupportedError(
      'Loopback audio capture not supported on web platform',
    );
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, dynamic userData) onData, {
    dynamic userData,
  }) async {
    throw UnsupportedError(
      'Loopback audio capture not supported on web platform',
    );
  }

  @override
  Future<void> stopCapture() async {
    // No-op since capture is not supported
  }

  @override
  Future<void> destroy() async {
    // No-op since no resources to clean up
  }
}
