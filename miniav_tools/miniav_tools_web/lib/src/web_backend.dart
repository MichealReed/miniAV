/// WebCodecs [MiniAVToolsBackend].
///
/// Uses `VideoEncoder` / `VideoDecoder` / `AudioEncoder` / `AudioDecoder`
/// from the browser WebCodecs API when available, and degrades gracefully
/// when they are not (returning `null` from factory methods so the backend
/// registry falls through to the next priority level).
///
/// GPU effects (WGSL shaders via `minigpu_web`) are an orthogonal opt-in:
/// they work when WebGPU is available and are silently skipped otherwise.
/// Use [WebCapability.hasWebGPU] to check before initialising minigpu.
library;

import 'dart:async';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'web_capability.dart';
import 'web_codecs_encoder.dart';

class WebCodecsBackend extends MiniAVToolsBackend {
  static const String backendName = 'webcodecs';
  static const int defaultPriority = 80; // browser-native, prefer over wasm.

  @override
  String get name => backendName;

  @override
  int get priority => defaultPriority;

  // WebCodecs codec coverage varies by browser — these are broadly available:
  // Chrome 94+, Safari 16.4+, Firefox 130+.
  static const _videoCodecs = <VideoCodec>{
    VideoCodec.h264,
    VideoCodec.vp8,
    VideoCodec.vp9,
    VideoCodec.av1,
    VideoCodec.hevc, // Safari + recent Chrome on supported HW
  };

  static const _audioCodecs = <AudioCodec>{
    AudioCodec.aac,
    AudioCodec.opus,
    AudioCodec.mp3,
    AudioCodec.flac,
    AudioCodec.vorbis,
  };

  @override
  bool supportsEncode(VideoCodec codec, {bool hwAccel = false}) =>
      _videoCodecs.contains(codec) && WebCapability.hasVideoEncoder;

  @override
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false}) =>
      _videoCodecs.contains(codec) && WebCapability.hasVideoEncoder;

  @override
  bool supportsAudioEncode(AudioCodec codec) =>
      _audioCodecs.contains(codec) && WebCapability.hasAudioEncoder;

  @override
  bool supportsAudioDecode(AudioCodec codec) =>
      _audioCodecs.contains(codec) && WebCapability.hasVideoEncoder;

  /// WebM and fragmented MP4 are the two containers MediaRecorder / WebCodecs
  /// can produce without a server-side muxer.
  @override
  bool supportsMux(Container container) =>
      container == Container.webm || container == Container.fmp4;

  @override
  bool supportsDemux(Container container) => false;

  @override
  Set<FrameSourceKind> get acceptedFrameSources => const {
    FrameSourceKind.cpu,
    FrameSourceKind.miniavBufferCpu,
    // Zero-copy path: VideoFrame from MediaStreamTrackProcessor.
    FrameSourceKind.webVideoFrame,
  };

  // ---------------------------------------------------------------------------
  // Factories
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  }) async {
    if (!_videoCodecs.contains(config.codec)) return null;
    if (!WebCapability.hasVideoEncoder) return null;

    // Probe the browser for this specific codec+resolution combination.
    final codecStr = config.backendOptions['codecString'] ??
        _defaultCodecString(config.codec);
    if (codecStr == null) return null;

    final supported = await WebCapability.isVideoEncoderSupported(
      codecStr,
      width: config.width,
      height: config.height,
    );
    if (!supported) return null;

    return WebCodecsVideoEncoder.create(config);
  }

  @override
  Future<PlatformDecoder?> createDecoder(
    DecoderConfig config, {
    BackendContext? context,
  }) async {
    // VideoDecoder implementation — deferred to a future iteration.
    if (!_videoCodecs.contains(config.codec)) return null;
    if (!WebCapability.hasVideoEncoder) return null;
    return null; // TODO: WebCodecsVideoDecoder
  }

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async => null;

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async => null;

  // ---------------------------------------------------------------------------

  static String? _defaultCodecString(VideoCodec codec) => switch (codec) {
    VideoCodec.h264 => 'avc1.42E01E',
    VideoCodec.hevc => 'hev1.1.6.L93.B0',
    VideoCodec.vp8  => 'vp8',
    VideoCodec.vp9  => 'vp09.00.10.08',
    VideoCodec.av1  => 'av01.0.04M.08',
    _               => null,
  };
}
