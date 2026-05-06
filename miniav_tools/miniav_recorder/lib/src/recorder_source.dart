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

  const CameraRecorderSource({
    required this.deviceId,
    required this.codec,
    this.bitrateBps,
    this.width,
    this.height,
    this.fps,
    required this.hwAccel,
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
