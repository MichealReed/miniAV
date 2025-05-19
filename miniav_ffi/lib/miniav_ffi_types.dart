import 'dart:convert';

import 'package:miniav_platform_interface/miniav_platform_types.dart';
import 'miniav_ffi_bindings.dart' as bindings;
import 'dart:ffi' as ffi;

import 'dart:typed_data';

// Helper function to convert ffi.Array<ffi.Char> to String
String _charArrayToUtf8String(ffi.Array<ffi.Char> charArray, int maxLength) {
  final bytes = <int>[];
  for (int i = 0; i < maxLength; ++i) {
    final int charCode = charArray[i]; // Accesses the int value (ffi.Char)

    if (charCode == 0) {
      break; // Null terminator
    }
    // Convert the potentially signed charCode to an unsigned byte (0-255)
    // by taking the lower 8 bits. This is crucial for UTF-8 decoding.
    bytes.add(charCode & 0xFF);
  }
  try {
    // Decode the list of UTF-8 bytes into a Dart string.
    return utf8.decode(bytes, allowMalformed: false);
  } catch (e) {
    // Optional: Handle decoding errors, e.g., log and return a placeholder or allow malformed.
    // print("UTF-8 decoding error: $e. Raw bytes: $bytes");
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Dart representation of MiniAVDeviceInfo.
class DeviceInfo {
  final String deviceId;
  final String name;
  final bool isDefault;

  DeviceInfo({
    required this.deviceId,
    required this.name,
    required this.isDefault,
  });

  factory DeviceInfo.fromNative(bindings.MiniAVDeviceInfo nativeInfo) {
    return DeviceInfo(
      deviceId: _charArrayToUtf8String(
        nativeInfo.device_id,
        bindings.MINIAV_DEVICE_ID_MAX_LEN,
      ),
      name: _charArrayToUtf8String(
        nativeInfo.name,
        bindings.MINIAV_DEVICE_NAME_MAX_LEN,
      ),
      isDefault: nativeInfo.is_default,
    );
  }

  @override
  String toString() =>
      'DeviceInfo(deviceId: $deviceId, name: $name, isDefault: $isDefault)';
}

/// Dart representation of MiniAVVideoInfo.
class VideoFormatInfo {
  final int width;
  final int height;
  final bindings.MiniAVPixelFormat pixelFormat;
  final int frameRateNumerator;
  final int frameRateDenominator;
  final bindings.MiniAVOutputPreference outputPreference;

  VideoFormatInfo({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    required this.outputPreference,
  });

  factory VideoFormatInfo.fromNative(
    bindings.MiniAVVideoInfo nativeInfo,
  ) {
    return VideoFormatInfo(
      width: nativeInfo.width,
      height: nativeInfo.height,
      pixelFormat: nativeInfo.pixel_format, // Uses the getter from bindings
      frameRateNumerator: nativeInfo.frame_rate_numerator,
      frameRateDenominator: nativeInfo.frame_rate_denominator,
      outputPreference:
          nativeInfo.output_preference, // Uses the getter from bindings
    );
  }

  @override
  String toString() =>
      'VideoFormatInfo(width: $width, height: $height, pixelFormat: ${pixelFormat.name}, frameRate: $frameRateNumerator/$frameRateDenominator, preference: ${outputPreference.name})';
}

extension MiniAVBufferFFI on MiniAVBuffer {
  /// Converts a bindings.MiniAVBuffer Pointer to a platform MiniAVBuffer.
  static MiniAVBuffer fromPointer(ffi.Pointer<bindings.MiniAVBuffer> ptr) {
    final native = ptr.ref;

    final type = bindings.MiniAVBufferType.fromValue(native.typeAsInt);
    final contentType = bindings.MiniAVBufferContentType.fromValue(
      native.content_typeAsInt,
    );
    final timestampUs = native.timestamp_us;
    final dataSizeBytes = native.data_size_bytes;

    MiniAVVideoBuffer? videoBuffer;
    MiniAVAudioBuffer? audioBuffer;

    if (type == bindings.MiniAVBufferType.MINIAV_BUFFER_TYPE_VIDEO) {
      final video = native.data.video;
      final pixelFormat = bindings.MiniAVPixelFormat.fromValue(
        video.pixel_formatAsInt,
      );

      // Planes and strides
      final numPlanes = 4; // Your struct has 4 planes/strides
      final strideBytes = List<int>.generate(
        numPlanes,
        (i) => video.stride_bytes[i],
      );
      final planes = List<Uint8List?>.generate(numPlanes, (i) {
        final planePtr = video.planes[i];
        if (planePtr == ffi.nullptr) return null;
        // You may need to know the plane size; here we use strideBytes[i] * height as a guess
        // If you have plane sizes, use them instead!
        // final width = video.info.width;
        final height = video.info.height;
        final sizeGuess = strideBytes[i] * height;
        try {
          return planePtr.cast<ffi.Uint8>().asTypedList(sizeGuess);
        } catch (_) {
          return null;
        }
      });

      videoBuffer = MiniAVVideoBuffer(
        width: video.info.width,
        height: video.info.height,
        pixelFormat: MiniAVPixelFormat.values[pixelFormat.value],
        strideBytes: strideBytes,
        planes: planes,
        nativeHandle:
            video.native_gpu_shared_handle.address != 0
                ? video.native_gpu_shared_handle
                : null,
      );
    } else if (type == bindings.MiniAVBufferType.MINIAV_BUFFER_TYPE_AUDIO) {
      final audio = native.data.audio;
      final info = audio.info;
      final format = bindings.MiniAVAudioFormat.fromValue(info.formatAsInt);

      // Audio data
      Uint8List audioData = Uint8List(0);
      if (audio.data != ffi.nullptr) {
        // You may need to know the correct size; here we use frame_count * channels * sample size
        // If you have a data_size field, use it!
        final channels = info.channels;
        final frames = info.num_frames;
        int bytesPerSample;
        switch (format) {
          case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_U8:
            bytesPerSample = 1;
            break;
          case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S16:
            bytesPerSample = 2;
            break;
          case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S32:
          case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_F32:
            bytesPerSample = 4;
            break;
          default:
            bytesPerSample = 1;
        }
        final dataSize = frames * channels * bytesPerSample;
        audioData = audio.data.cast<ffi.Uint8>().asTypedList(dataSize);
      }

      audioBuffer = MiniAVAudioBuffer(
        frameCount: audio.frame_count,
        info: MiniAVAudioInfo(
          format: MiniAVAudioFormat.values[format.value],
          sampleRate: info.sample_rate,
          channels: info.channels,
          numFrames: info.num_frames,
        ),
        data: audioData,
      );
    }

    return MiniAVBuffer(
      type: MiniAVBufferType.values[type.value],
      contentType: MiniAVBufferContentType.values[contentType.value],
      timestampUs: timestampUs,
      data: videoBuffer ?? audioBuffer,
      dataSizeBytes: dataSizeBytes,
    );
  }
}

// DeviceInfo conversion
extension DeviceInfoFFIToPlatform on DeviceInfo {
  MiniAVDeviceInfo toPlatformType() =>
      MiniAVDeviceInfo(deviceId: deviceId, name: name, isDefault: isDefault);

  static DeviceInfo fromNative(bindings.MiniAVDeviceInfo nativeInfo) =>
      DeviceInfo.fromNative(nativeInfo);

  // Not needed: DeviceInfo is not sent to native, only received.
}

// VideoFormatInfo conversion
extension VideoFormatInfoFFIToPlatform on VideoFormatInfo {
  MiniAVVideoInfo toPlatformType() => MiniAVVideoInfo(
    width: width,
    height: height,
    pixelFormat: pixelFormat.toPlatformType(),
    frameRateNumerator: frameRateNumerator,
    frameRateDenominator: frameRateDenominator,
    outputPreference: outputPreference.toPlatformType(),
  );

  static VideoFormatInfo fromNative(
    bindings.MiniAVVideoInfo nativeInfo,
  ) => VideoFormatInfo.fromNative(nativeInfo);

  static VideoFormatInfo fromPlatformType(MiniAVVideoInfo info) =>
      VideoFormatInfo(
        width: info.width,
        height: info.height,
        pixelFormat: MiniAVPixelFormatX.fromPlatformType(info.pixelFormat),
        frameRateNumerator: info.frameRateNumerator,
        frameRateDenominator: info.frameRateDenominator,
        outputPreference: MiniAVOutputPreferenceX.fromPlatformType(
          info.outputPreference,
        ),
      );

  /// Copies a platform type into a native struct (for FFI calls).
  static void copyToNative(
    MiniAVVideoInfo info,
    bindings.MiniAVVideoInfo native,
  ) {
    native.width = info.width;
    native.height = info.height;
    native.pixel_formatAsInt =
        MiniAVPixelFormatX.fromPlatformType(info.pixelFormat).value;
    native.frame_rate_numerator = info.frameRateNumerator;
    native.frame_rate_denominator = info.frameRateDenominator;
    native.output_preferenceAsInt =
        MiniAVOutputPreferenceX.fromPlatformType(info.outputPreference).value;
  }
}

// PixelFormat conversion
extension MiniAVPixelFormatX on bindings.MiniAVPixelFormat {
  MiniAVPixelFormat toPlatformType() {
    switch (this) {
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_I420:
        return MiniAVPixelFormat.i420;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_NV12:
        return MiniAVPixelFormat.nv12;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_NV21:
        return MiniAVPixelFormat.nv21;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_YUY2:
        return MiniAVPixelFormat.yuy2;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_UYVY:
        return MiniAVPixelFormat.uyvy;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_RGB24:
        return MiniAVPixelFormat.rgb24;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_BGR24:
        return MiniAVPixelFormat.bgr24;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_RGBA32:
        return MiniAVPixelFormat.rgba32;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_BGRA32:
        return MiniAVPixelFormat.bgra32;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_ARGB32:
        return MiniAVPixelFormat.argb32;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_ABGR32:
        return MiniAVPixelFormat.abgr32;
      case bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_MJPEG:
        return MiniAVPixelFormat.mjpeg;
      default:
        return MiniAVPixelFormat.unknown;
    }
  }

  static bindings.MiniAVPixelFormat fromPlatformType(MiniAVPixelFormat f) {
    switch (f) {
      case MiniAVPixelFormat.i420:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_I420;
      case MiniAVPixelFormat.nv12:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_NV12;
      case MiniAVPixelFormat.nv21:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_NV21;
      case MiniAVPixelFormat.yuy2:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_YUY2;
      case MiniAVPixelFormat.uyvy:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_UYVY;
      case MiniAVPixelFormat.rgb24:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_RGB24;
      case MiniAVPixelFormat.bgr24:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_BGR24;
      case MiniAVPixelFormat.rgba32:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_RGBA32;
      case MiniAVPixelFormat.bgra32:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_BGRA32;
      case MiniAVPixelFormat.argb32:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_ARGB32;
      case MiniAVPixelFormat.abgr32:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_ABGR32;
      case MiniAVPixelFormat.mjpeg:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_MJPEG;
      default:
        return bindings.MiniAVPixelFormat.MINIAV_PIXEL_FORMAT_UNKNOWN;
    }
  }
}

// OutputPreference conversion
extension MiniAVOutputPreferenceX on bindings.MiniAVOutputPreference {
  MiniAVOutputPreference toPlatformType() {
    switch (this) {
      case bindings.MiniAVOutputPreference.MINIAV_OUTPUT_PREFERENCE_CPU:
        return MiniAVOutputPreference.cpu;
      case bindings
          .MiniAVOutputPreference
          .MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE:
        return MiniAVOutputPreference.gpuIfAvailable;
    }
  }

  static bindings.MiniAVOutputPreference fromPlatformType(
    MiniAVOutputPreference p,
  ) {
    switch (p) {
      case MiniAVOutputPreference.cpu:
        return bindings.MiniAVOutputPreference.MINIAV_OUTPUT_PREFERENCE_CPU;
      case MiniAVOutputPreference.gpuIfAvailable:
        return bindings
            .MiniAVOutputPreference
            .MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE;
    }
  }
}

/// Dart FFI representation of MiniAVAudioInfo.
class AudioInfo {
  final bindings.MiniAVAudioFormat format;
  final int sampleRate;
  final int channels;
  final int numFrames; // Optional: if your C struct has it and it's useful

  AudioInfo({
    required this.format,
    required this.sampleRate,
    required this.channels,
    this.numFrames = 0, // Default if not always present or used
  });

  factory AudioInfo.fromNative(bindings.MiniAVAudioInfo nativeInfo) {
    return AudioInfo(
      format: nativeInfo.format, // Uses the getter from bindings
      sampleRate: nativeInfo.sample_rate,
      channels: nativeInfo.channels,
      numFrames: nativeInfo.num_frames,
    );
  }

  @override
  String toString() =>
      'AudioInfo(format: ${format.name}, sampleRate: $sampleRate, channels: $channels, numFrames: $numFrames)';
}

// AudioFormat conversion
extension MiniAVAudioFormatX on bindings.MiniAVAudioFormat {
  MiniAVAudioFormat toPlatformType() {
    switch (this) {
      case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_U8:
        return MiniAVAudioFormat.u8;
      case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S16:
        return MiniAVAudioFormat.s16;
      case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S32:
        return MiniAVAudioFormat.s32;
      case bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_F32:
        return MiniAVAudioFormat.f32;
      default:
        return MiniAVAudioFormat.unknown;
    }
  }

  static bindings.MiniAVAudioFormat fromPlatformType(MiniAVAudioFormat f) {
    switch (f) {
      case MiniAVAudioFormat.u8:
        return bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_U8;
      case MiniAVAudioFormat.s16:
        return bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S16;
      case MiniAVAudioFormat.s32:
        return bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_S32;
      case MiniAVAudioFormat.f32:
        return bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_F32;
      default:
        return bindings.MiniAVAudioFormat.MINIAV_AUDIO_FORMAT_UNKNOWN;
    }
  }
}

// AudioInfo conversion
extension AudioInfoFFIToPlatform on AudioInfo {
  MiniAVAudioInfo toPlatformType() => MiniAVAudioInfo(
    format: format.toPlatformType(),
    sampleRate: sampleRate,
    channels: channels,
    numFrames: numFrames,
  );

  static AudioInfo fromNative(bindings.MiniAVAudioInfo nativeInfo) =>
      AudioInfo.fromNative(nativeInfo);

  static AudioInfo fromPlatformType(MiniAVAudioInfo info) => AudioInfo(
    format: MiniAVAudioFormatX.fromPlatformType(info.format),
    sampleRate: info.sampleRate,
    channels: info.channels,
    numFrames: info.numFrames,
  );

  /// Copies a platform type into a native struct (for FFI calls).
  static void copyToNative(
    MiniAVAudioInfo info,
    bindings.MiniAVAudioInfo native,
  ) {
    native.formatAsInt = MiniAVAudioFormatX.fromPlatformType(info.format).value;
    native.sample_rate = info.sampleRate;
    native.channels = info.channels;
    native.num_frames = info.numFrames;
  }
}
