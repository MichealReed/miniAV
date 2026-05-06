/// User-facing facade for miniav_tools.
///
/// Backends register themselves with [MiniAVToolsPlatform] when their package
/// is imported. This facade routes user requests to the
/// highest-priority backend that supports the request.
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'src/encoder.dart';
import 'src/audio_encoder.dart';
import 'src/decoder.dart';
import 'src/muxer.dart';
import 'src/demuxer.dart';

export 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

export 'src/encoder.dart';
export 'src/audio_encoder.dart';
export 'src/decoder.dart';
export 'src/muxer.dart';
export 'src/demuxer.dart';

/// Static facade. All factory methods route through
/// [MiniAVToolsPlatform.instance] and try each registered backend in priority
/// order until one succeeds.
class MiniAVTools {
  MiniAVTools._();

  /// All registered backends (snapshot; immutable).
  static List<MiniAVToolsBackend> get backends =>
      MiniAVToolsPlatform.instance.backends;

  /// Create a video encoder.
  ///
  /// Throws [NoBackendForCodecException] if no registered backend supports
  /// [config.codec]. Throws [CodecInitException] if a backend was selected
  /// but failed to initialise.
  static Future<Encoder> createEncoder(
    EncoderConfig config, {
    BackendPreference preference = BackendPreference.auto,
    BackendContext? context,
  }) async {
    final hwWanted =
        config.hwAccel == HwAccelPreference.required ||
        config.hwAccel == HwAccelPreference.preferred;

    Object? lastInitError;
    for (final backend in MiniAVToolsPlatform.instance.orderedBackends(
      preference,
    )) {
      if (!backend.supportsEncode(config.codec, hwAccel: hwWanted)) {
        // Allow falling back to SW within this backend if HW is only preferred.
        if (config.hwAccel != HwAccelPreference.preferred ||
            !backend.supportsEncode(config.codec, hwAccel: false)) {
          continue;
        }
      }
      try {
        final platform = await backend.createEncoder(config, context: context);
        if (platform == null) continue;
        return Encoder(platform, backend.name);
      } on CodecInitException catch (e) {
        lastInitError = e;
        if (config.hwAccel == HwAccelPreference.required) rethrow;
        continue;
      }
    }
    if (lastInitError is CodecInitException) {
      throw lastInitError;
    }
    throw NoBackendForCodecException.video(config.codec, hwAccel: hwWanted);
  }

  /// Create an audio encoder. Throws [NoBackendForCodecException] if no
  /// registered backend supports [config.codec].
  static Future<AudioEncoder> createAudioEncoder(
    AudioEncoderConfig config, {
    BackendPreference preference = BackendPreference.auto,
    BackendContext? context,
  }) async {
    Object? lastInitError;
    for (final backend in MiniAVToolsPlatform.instance.orderedBackends(
      preference,
    )) {
      if (!backend.supportsAudioEncode(config.codec)) continue;
      try {
        final platform = await backend.createAudioEncoder(
          config,
          context: context,
        );
        if (platform == null) continue;
        return AudioEncoder(platform, backend.name);
      } on CodecInitException catch (e) {
        lastInitError = e;
        continue;
      }
    }
    if (lastInitError is CodecInitException) {
      throw lastInitError;
    }
    throw NoBackendForCodecException.audio(config.codec);
  }

  /// Create a video decoder.
  static Future<Decoder> createDecoder(
    DecoderConfig config, {
    BackendPreference preference = BackendPreference.auto,
    BackendContext? context,
  }) async {
    final hwWanted =
        config.hwAccel == HwAccelPreference.required ||
        config.hwAccel == HwAccelPreference.preferred;

    Object? lastInitError;
    for (final backend in MiniAVToolsPlatform.instance.orderedBackends(
      preference,
    )) {
      if (!backend.supportsDecode(config.codec, hwAccel: hwWanted)) {
        if (config.hwAccel != HwAccelPreference.preferred ||
            !backend.supportsDecode(config.codec, hwAccel: false)) {
          continue;
        }
      }
      try {
        final platform = await backend.createDecoder(config, context: context);
        if (platform == null) continue;
        return Decoder(platform, backend.name);
      } on CodecInitException catch (e) {
        lastInitError = e;
        if (config.hwAccel == HwAccelPreference.required) rethrow;
        continue;
      }
    }
    if (lastInitError is CodecInitException) {
      throw lastInitError;
    }
    throw NoBackendForCodecException.video(config.codec, hwAccel: hwWanted);
  }

  /// Create a container muxer.
  static Future<Muxer> createMuxer(
    MuxerConfig config, {
    BackendPreference preference = BackendPreference.auto,
  }) async {
    for (final backend in MiniAVToolsPlatform.instance.orderedBackends(
      preference,
    )) {
      if (!backend.supportsMux(config.container)) continue;
      final platform = await backend.createMuxer(config);
      if (platform == null) continue;
      return Muxer(platform, backend.name);
    }
    throw NoBackendForCodecException.container(config.container);
  }

  /// Create a container demuxer.
  static Future<Demuxer> createDemuxer(
    DemuxerConfig config, {
    BackendPreference preference = BackendPreference.auto,
  }) async {
    for (final backend in MiniAVToolsPlatform.instance.orderedBackends(
      preference,
    )) {
      if (config.container != null &&
          !backend.supportsDemux(config.container!)) {
        continue;
      }
      final platform = await backend.createDemuxer(config);
      if (platform == null) continue;
      return Demuxer(platform, backend.name);
    }
    throw NoBackendForCodecException.container(
      config.container ?? Container.mp4,
    );
  }
}
