import 'dart:typed_data';

/// Platform-agnostic types for MiniAV platform interface.
/// These are pure Dart types, not FFI structs.

enum MiniAVPixelFormat {
  unknown,
  rgb24,
  bgr24,
  rgba32,
  bgra32,
  argb32,
  abgr32,
  rgbx32,
  bgrx32,
  xrgb32,
  xbgr32,
  i420,
  yv12,
  nv12,
  nv21,
  yuy2,
  uyvy,
  rgb30,
  rgb48,
  rgba64,
  rgba64Half,
  rgba128Float,
  yuv420_10bit,
  yuv422_10bit,
  yuv444_10bit,
  gray8,
  gray16,
  bayerGrbg8,
  bayerRggb8,
  bayerBggr8,
  bayerGbrg8,
  bayerGrbg16,
  bayerRggb16,
  bayerBggr16,
  bayerGbrg16,
  mjpeg,
}

enum MiniAVAudioFormat { unknown, u8, s16, s32, f32 }

enum MiniAVOutputPreference { cpu, gpu }

enum MiniAVBufferType { unknown, video, audio }

enum MiniAVBufferContentType {
  cpu,
  gpuD3D11Handle,
  gpuMetalTexture,
  gpuDmabufFd,
  gpuAHardwareBuffer, // Android: planes[0].nativeHandle is AHardwareBuffer*
}

enum MiniAVLogLevel { none, trace, debug, info, warn, error }

class MiniAVDeviceInfo {
  final String deviceId;
  final String name;
  final bool isDefault;

  MiniAVDeviceInfo({
    required this.deviceId,
    required this.name,
    required this.isDefault,
  });
}

/// Type of device-change event reported via device-change listeners.
enum MiniAVDeviceChangeEvent { added, removed, defaultChanged }

/// A single device-change notification.
class MiniAVDeviceChangeNotification {
  final MiniAVDeviceChangeEvent event;
  final MiniAVDeviceInfo device;

  const MiniAVDeviceChangeNotification(this.event, this.device);

  @override
  String toString() =>
      'MiniAVDeviceChangeNotification($event, ${device.deviceId})';
}

/// Listener type for device-change events. Always invoked on the platform's
/// background watcher thread on native; on web, on the main isolate.
typedef MiniAVDeviceChangeListener =
    void Function(MiniAVDeviceChangeNotification notification);

/// Listener type for per-context device-lost events. The integer is a
/// `MiniAVResultCode`-compatible reason code.
typedef MiniAVContextLostListener = void Function(int reason);

class MiniAVVideoInfo {
  final int width;
  final int height;
  final MiniAVPixelFormat pixelFormat;
  final int frameRateNumerator;
  final int frameRateDenominator;
  final MiniAVOutputPreference outputPreference;

  MiniAVVideoInfo({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.outputPreference,
  });
}

class MiniAVAudioInfo {
  final MiniAVAudioFormat format;
  final int sampleRate;
  final int channels;
  final int numFrames;

  MiniAVAudioInfo({
    required this.format,
    required this.sampleRate,
    required this.channels,
    required this.numFrames,
  });
}

/// GPU sync fence information for zero-copy buffer handoff.
class MiniAVNativeFence {
  /// Linux/Android: sync_file fd, or -1 if none.
  final int syncFd;

  /// Windows: ID3D11Fence* as integer address, or 0 if none.
  final int d3d11FencePtr;

  /// macOS/iOS: id<MTLSharedEvent> as integer address, or 0 if none.
  final int metalSharedEventPtr;

  /// macOS/iOS: signaled fence value.
  final int metalFenceValue;

  const MiniAVNativeFence({
    this.syncFd = -1,
    this.d3d11FencePtr = 0,
    this.metalSharedEventPtr = 0,
    this.metalFenceValue = 0,
  });
}

class MiniAVBuffer {
  final MiniAVBufferType type;
  final MiniAVBufferContentType contentType;
  final int timestampUs;
  final Object? data; // MiniAVVideoBuffer or MiniAVAudioBuffer
  final int dataSizeBytes;
  final Object? _nativeHandle;
  final MiniAVNativeFence nativeFence;

  const MiniAVBuffer({
    required this.type,
    required this.contentType,
    required this.timestampUs,
    required this.data,
    required this.dataSizeBytes,
    Object? nativeHandle,
    this.nativeFence = const MiniAVNativeFence(),
  }) : _nativeHandle = nativeHandle;

  // Add getter for native handle
  Object? get nativeHandle => _nativeHandle;
}

class MiniAVVideoBuffer {
  final int width;
  final int height;
  final MiniAVPixelFormat pixelFormat;
  final List<int> strideBytes;
  final List<Uint8List?> planes;
  final List<Object?> nativeHandles; // platform-specific GPU handle, if any
  /// Per-plane DMA-BUF file descriptors (-1 if not applicable).
  final List<int> dmabufFds;

  /// Per-plane DRM format modifiers (0 = LINEAR).
  final List<int> drmFormatModifiers;

  MiniAVVideoBuffer({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.strideBytes,
    required this.planes,
    this.nativeHandles = const [],
    this.dmabufFds = const [],
    this.drmFormatModifiers = const [],
  });
}

class MiniAVAudioBuffer {
  final int frameCount;
  final MiniAVAudioInfo info;
  final Uint8List data;

  MiniAVAudioBuffer({
    required this.frameCount,
    required this.info,
    required this.data,
  });
}

typedef ScreenFormatDefaults = (
  MiniAVVideoInfo videoFormat,
  MiniAVAudioInfo? audioFormat,
);

// --- Input Capture Types ---

enum MiniAVInputType {
  keyboard(0x01),
  mouse(0x02),
  gamepad(0x04);

  final int value;
  const MiniAVInputType(this.value);
}

enum MiniAVKeyAction {
  down(0),
  up(1);

  final int value;
  const MiniAVKeyAction(this.value);

  static MiniAVKeyAction fromValue(int value) => switch (value) {
    0 => down,
    1 => up,
    _ => throw ArgumentError('Unknown MiniAVKeyAction value: $value'),
  };
}

enum MiniAVMouseAction {
  move(0),
  buttonDown(1),
  buttonUp(2),
  wheel(3);

  final int value;
  const MiniAVMouseAction(this.value);

  static MiniAVMouseAction fromValue(int value) => switch (value) {
    0 => move,
    1 => buttonDown,
    2 => buttonUp,
    3 => wheel,
    _ => throw ArgumentError('Unknown MiniAVMouseAction value: $value'),
  };
}

enum MiniAVMouseButton {
  none(0),
  left(1),
  right(2),
  middle(3),
  x1(4),
  x2(5);

  final int value;
  const MiniAVMouseButton(this.value);

  static MiniAVMouseButton fromValue(int value) => switch (value) {
    0 => none,
    1 => left,
    2 => right,
    3 => middle,
    4 => x1,
    5 => x2,
    _ => throw ArgumentError('Unknown MiniAVMouseButton value: $value'),
  };
}

class MiniAVKeyboardEvent {
  final int timestampUs;
  final int keyCode;
  final int scanCode;
  final MiniAVKeyAction action;

  MiniAVKeyboardEvent({
    required this.timestampUs,
    required this.keyCode,
    required this.scanCode,
    required this.action,
  });
}

class MiniAVMouseEvent {
  final int timestampUs;
  final int x;
  final int y;
  final int deltaX;
  final int deltaY;

  /// Vertical scroll wheel delta (+ = up/away).
  final int wheelDelta;

  /// Horizontal scroll wheel delta (+ = right).
  final int wheelDeltaX;
  final MiniAVMouseAction action;
  final MiniAVMouseButton button;

  /// Capture always reports absolute coords (true). For injection: true = move
  /// to absolute (x, y); false = move by (deltaX, deltaY). Ignored for
  /// button/wheel actions.
  final bool isAbsolute;

  MiniAVMouseEvent({
    required this.timestampUs,
    required this.x,
    required this.y,
    required this.deltaX,
    required this.deltaY,
    required this.wheelDelta,
    required this.action,
    required this.button,
    this.wheelDeltaX = 0,
    this.isAbsolute = true,
  });
}

class MiniAVGamepadEvent {
  final int timestampUs;
  final int gamepadIndex;
  final int buttons;
  final int leftStickX;
  final int leftStickY;
  final int rightStickX;
  final int rightStickY;
  final int leftTrigger;
  final int rightTrigger;
  final bool connected;

  MiniAVGamepadEvent({
    required this.timestampUs,
    required this.gamepadIndex,
    required this.buttons,
    required this.leftStickX,
    required this.leftStickY,
    required this.rightStickX,
    required this.rightStickY,
    required this.leftTrigger,
    required this.rightTrigger,
    required this.connected,
  });
}

class MiniAVInputConfig {
  final int inputTypes;
  final int mouseThrottleHz;
  final int gamepadPollHz;

  MiniAVInputConfig({
    required this.inputTypes,
    this.mouseThrottleHz = 60,
    this.gamepadPollHz = 60,
  });
}
