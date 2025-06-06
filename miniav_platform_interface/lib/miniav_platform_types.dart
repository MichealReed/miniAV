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

class MiniAVBuffer {
  final MiniAVBufferType type;
  final MiniAVBufferContentType contentType;
  final int timestampUs;
  final Object? data; // MiniAVVideoBuffer or MiniAVAudioBuffer
  final int dataSizeBytes;
  final Object? _nativeHandle;

  const MiniAVBuffer({
    required this.type,
    required this.contentType,
    required this.timestampUs,
    required this.data,
    required this.dataSizeBytes,
    Object? nativeHandle,
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

  MiniAVVideoBuffer({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.strideBytes,
    required this.planes,
    this.nativeHandles = const [],
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
