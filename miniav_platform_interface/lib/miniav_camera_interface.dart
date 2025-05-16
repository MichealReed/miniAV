import 'miniav_platform_types.dart';

/// Abstract interface for camera functionality on all platforms.
abstract class MiniCameraPlatformInterface {
  /// Enumerate available camera devices.
  Future<List<MiniAVDeviceInfo>> enumerateDevices();

  /// Get supported video formats for a given device.
  Future<List<MiniAVVideoFormatInfo>> getSupportedFormats(String deviceId);

  /// Get supported audio formats for a given device.
  Future<MiniAVVideoFormatInfo> getDefaultFormat(String deviceId);

  /// Create a camera context (for capture/configuration).
  Future<MiniCameraContextPlatformInterface> createContext();
}

/// Abstract camera context for configuring and capturing from a camera.
abstract class MiniCameraContextPlatformInterface {
  /// Configure the camera context with a device and format.
  Future<void> configure(String deviceId, MiniAVVideoFormatInfo format);

  Future<MiniAVVideoFormatInfo> getConfiguredFormat();

  /// Start camera capture.
  /// [onFrame] is called for each frame received.
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onFrame, {
    Object? userData,
  });

  /// Stop camera capture.
  Future<void> stopCapture();

  /// Destroy this camera context and release resources.
  Future<void> destroy();
}
