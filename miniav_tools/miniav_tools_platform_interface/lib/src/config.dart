/// Configuration objects for encoders, decoders, muxers, and demuxers.
library;

import 'dart:typed_data';

import 'package:miniav_platform_interface/miniav_platform_types.dart';

import 'codec_types.dart';
import 'packet.dart';

/// Configuration for a video encoder.
class EncoderConfig {
  final VideoCodec codec;
  final int width;
  final int height;
  final int bitrateBps;

  /// Keyframe interval in frames. 0 = encoder default.
  final int gopLength;

  final int frameRateNumerator;
  final int frameRateDenominator;

  /// Pixel format the encoder will receive (post-upload). Most hardware
  /// encoders want NV12; software encoders often want YUV420P.
  final MiniAVPixelFormat inputPixelFormat;

  final HwAccelPreference hwAccel;
  final RateControl rateControl;

  /// CRF / ICQ quality (codec-dependent range, typically 0–51).
  final int? crfQuality;

  final EncoderProfile profile;
  final EncoderLevel? level;

  /// Maximum number of B-frames between P-frames. 0 disables.
  final int bFrameCount;

  /// Backend-specific options as key-value strings (e.g. NVENC `preset=p4`).
  final Map<String, String> backendOptions;

  const EncoderConfig({
    required this.codec,
    required this.width,
    required this.height,
    required this.bitrateBps,
    this.gopLength = 0,
    this.frameRateNumerator = 30,
    this.frameRateDenominator = 1,
    this.inputPixelFormat = MiniAVPixelFormat.nv12,
    this.hwAccel = HwAccelPreference.preferred,
    this.rateControl = RateControl.vbr,
    this.crfQuality,
    this.profile = EncoderProfile.high,
    this.level,
    this.bFrameCount = 0,
    this.backendOptions = const {},
  });
}

/// Configuration for a video decoder.
class DecoderConfig {
  final VideoCodec codec;

  /// Codec-private extra-data (SPS/PPS for H.264, codec-private for VP9, etc.).
  /// Required for some codecs/containers; pass `null` if the bitstream is
  /// self-contained (Annex-B).
  final Uint8List? extraData;

  final HwAccelPreference hwAccel;

  /// Preferred output pixel format. Decoder may ignore if not supported.
  final MiniAVPixelFormat outputPixelFormat;

  /// If true, request the decoder to output GPU-resident frames (D3D11
  /// texture, IOSurface, dmabuf) for zero-copy onward processing.
  final bool requestGpuOutput;

  final Map<String, String> backendOptions;

  const DecoderConfig({
    required this.codec,
    this.extraData,
    this.hwAccel = HwAccelPreference.preferred,
    this.outputPixelFormat = MiniAVPixelFormat.nv12,
    this.requestGpuOutput = false,
    this.backendOptions = const {},
  });
}

/// Description of a single track to be written by a muxer.
sealed class TrackInfo {
  const TrackInfo();
}

class VideoTrackInfo extends TrackInfo {
  final VideoCodec codec;
  final int width;
  final int height;
  final int frameRateNumerator;
  final int frameRateDenominator;
  final CodecExtraData? extraData;

  const VideoTrackInfo({
    required this.codec,
    required this.width,
    required this.height,
    required this.frameRateNumerator,
    required this.frameRateDenominator,
    this.extraData,
  });
}

class AudioTrackInfo extends TrackInfo {
  final AudioCodec codec;
  final int sampleRate;
  final int channels;
  final CodecExtraData? extraData;

  const AudioTrackInfo({
    required this.codec,
    required this.sampleRate,
    required this.channels,
    this.extraData,
  });
}

/// Where a muxer writes its output.
sealed class MuxerOutput {
  const MuxerOutput();

  factory MuxerOutput.file(String path) = FileMuxerOutput;
  factory MuxerOutput.bytes() = BytesMuxerOutput;
  factory MuxerOutput.callback(void Function(Uint8List chunk) onChunk) =
      CallbackMuxerOutput;
}

class FileMuxerOutput extends MuxerOutput {
  final String path;
  const FileMuxerOutput(this.path);
}

class BytesMuxerOutput extends MuxerOutput {
  const BytesMuxerOutput();
}

class CallbackMuxerOutput extends MuxerOutput {
  final void Function(Uint8List chunk) onChunk;
  const CallbackMuxerOutput(this.onChunk);
}

/// Configuration for a muxer (encoded packets → container file/stream).
class MuxerConfig {
  final Container container;
  final MuxerOutput output;
  final List<TrackInfo> tracks;

  /// For fragmented MP4 etc.: target fragment duration in microseconds.
  /// 0 = container default.
  final int fragmentDurationUs;

  final Map<String, String> backendOptions;

  const MuxerConfig({
    required this.container,
    required this.output,
    required this.tracks,
    this.fragmentDurationUs = 0,
    this.backendOptions = const {},
  });
}

/// Where a demuxer reads its input.
sealed class DemuxerInput {
  const DemuxerInput();

  factory DemuxerInput.file(String path) = FileDemuxerInput;
  factory DemuxerInput.bytes(Uint8List bytes) = BytesDemuxerInput;
}

class FileDemuxerInput extends DemuxerInput {
  final String path;
  const FileDemuxerInput(this.path);
}

class BytesDemuxerInput extends DemuxerInput {
  final Uint8List bytes;
  const BytesDemuxerInput(this.bytes);
}

/// Configuration for a demuxer (container file/stream → encoded packets).
class DemuxerConfig {
  final Container? container; // null = auto-probe
  final DemuxerInput input;
  final Map<String, String> backendOptions;

  const DemuxerConfig({
    required this.input,
    this.container,
    this.backendOptions = const {},
  });
}

/// Configuration for an audio encoder (AAC, Opus, …).
///
/// Sample format of the input PCM is supplied per [encode] call rather than
/// at config time so a single encoder instance can accept whichever PCM
/// format miniav delivers (u8/s16/s32/f32 interleaved).
class AudioEncoderConfig {
  final AudioCodec codec;
  final int sampleRate;
  final int channels;
  final int bitrateBps;
  final Map<String, String> backendOptions;

  const AudioEncoderConfig({
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitrateBps,
    this.backendOptions = const {},
  });
}
