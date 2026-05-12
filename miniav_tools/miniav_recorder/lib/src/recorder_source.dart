/// Sealed config types for recorder sources.
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'screen_effect.dart';
import 'screen_scale_policy.dart';

export 'screen_effect.dart';
export 'screen_scale_policy.dart';

sealed class RecorderSource {
  const RecorderSource();
}

class ScreenRecorderSource extends RecorderSource {
  final String? displayId;
  final String? windowId;
  final VideoCodec codec;
  final int? bitrateBps;
  final int? width;
  final int? height;
  final int? fps;
  final HwAccelPreference hwAccel;

  /// How to scale down the capture before encoding. Defaults to [ScreenScalePolicy.none].
  /// Use [ScreenScalePolicy.h264Friendly] to auto-downscale ultrawide / 4K+
  /// displays so H.264 HW encoders stay in range (max dim ≤ 4096).
  final ScreenScalePolicy scale;

  /// Zero or more GPU post-processing effects applied in order after downscaling.
  /// Effects run entirely on the GPU (WGSL compute) and add no CPU overhead.
  /// Requires the zero-copy GPU path to be active; ignored otherwise.
  final List<ScreenEffect> effects;

  /// Normalized quality target in the range **0.0 – 1.0**.
  ///
  /// When set, the encoder switches to constant-quality (CRF/ICQ) mode and
  /// [bitrateBps] is ignored. This is the recommended way to control file
  /// size: a static desktop clip will be far smaller than a fast-moving game
  /// at the same quality setting, whereas a fixed bitrate wastes bits on
  /// still content.
  ///
  /// | Value | Meaning |
  /// |-------|---------|
  /// | `1.0` | Best quality (large files) |
  /// | `0.7` | High quality — good for DVR clips (default when set) |
  /// | `0.5` | Balanced quality / size |
  /// | `0.0` | Smallest file (visibly degraded) |
  ///
  /// Leave `null` (the default) to use bitrate-based rate control instead
  /// ([bitrateBps] or [RecorderBuilder.defaultVideoBitrate]).
  final double? quality;

  /// Raw encoder options forwarded directly to the backend (FFmpeg av_opt or
  /// NVENC param name → string value). These override anything the recorder
  /// sets automatically and are intended as an expert escape hatch.
  ///
  /// Examples:
  /// ```dart
  /// encoderOptions: {'preset': 'p7', 'tune': 'hq'}   // NVENC
  /// encoderOptions: {'preset': 'slow', 'crf': '20'}  // libx264
  /// ```
  final Map<String, String> encoderOptions;

  const ScreenRecorderSource({
    this.displayId,
    this.windowId,
    required this.codec,
    this.bitrateBps,
    this.width,
    this.height,
    this.fps,
    required this.hwAccel,
    this.scale = ScreenScalePolicy.none,
    this.effects = const [],
    this.quality,
    this.encoderOptions = const {},
  });
}

class CameraRecorderSource extends RecorderSource {
  final String deviceId;
  final VideoCodec codec;
  final int? bitrateBps;
  final int? width;
  final int? height;
  final int? fps;
  final HwAccelPreference hwAccel;

  /// See [ScreenRecorderSource.quality].
  final double? quality;

  /// See [ScreenRecorderSource.encoderOptions].
  final Map<String, String> encoderOptions;

  const CameraRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.width,
    this.height,
    this.fps,
    required this.hwAccel,
    this.quality,
    this.encoderOptions = const {},
  });
}

class MicRecorderSource extends RecorderSource {
  final String deviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final int? sampleRate;
  final int? channels;

  const MicRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.sampleRate,
    this.channels,
  });
}

class LoopbackRecorderSource extends RecorderSource {
  final String deviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final int? sampleRate;
  final int? channels;

  const LoopbackRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.sampleRate,
    this.channels,
  });
}

/// Captures **mic + loopback simultaneously** and mixes the two PCM streams
/// into a single audio track in the output.
///
/// Use this instead of separate [MicRecorderSource] + [LoopbackRecorderSource]
/// when you want one audio track that every player will play (rather than
/// two tracks where most players auto-pick only the first).
///
/// Both inputs are converted to a common format
/// (48 kHz / stereo / float32) and summed sample-by-sample. The resulting
/// PCM is encoded with a single [AudioEncoder].
///
/// [micGainDb] / [loopbackGainDb] adjust each source's level before the sum
/// (use a negative value such as `-3` to avoid clipping when both are loud).
class MixedAudioRecorderSource extends RecorderSource {
  final String micDeviceId;
  final String loopbackDeviceId;
  final AudioCodec codec;
  final int? bitrateBps;
  final double micGainDb;
  final double loopbackGainDb;

  const MixedAudioRecorderSource({
    required this.micDeviceId,
    required this.loopbackDeviceId,
    this.codec = AudioCodec.aac,
    this.bitrateBps,
    this.micGainDb = 0.0,
    this.loopbackGainDb = 0.0,
  });
}
