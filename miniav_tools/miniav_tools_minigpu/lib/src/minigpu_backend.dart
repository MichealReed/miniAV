/// minigpu compute-shader codec backend.
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'gpu_codec_pipeline.dart';
import 'minigpu_mjpeg_pipeline.dart';

class MinigpuBackend extends MiniAVToolsBackend {
  static const String backendName = 'minigpu';
  static const int defaultPriority = 30;

  @override
  String get name => backendName;

  @override
  int get priority => defaultPriority;

  // For now, advertise MJPEG as the primary target (compute-friendly DCT/VLC).
  static const _encodeCodecs = <VideoCodec>{VideoCodec.mjpeg};

  @override
  bool supportsEncode(VideoCodec codec, {bool hwAccel = false}) =>
      _encodeCodecs.contains(codec);

  @override
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false}) => false;

  @override
  bool supportsAudioEncode(AudioCodec codec) => false;
  @override
  bool supportsAudioDecode(AudioCodec codec) => false;

  @override
  bool supportsMux(Container container) => false;
  @override
  bool supportsDemux(Container container) => false;

  /// minigpu can natively consume miniav GPU buffers in zero-copy fashion
  /// once the WGSL textures are wired up.
  @override
  Set<FrameSourceKind> get acceptedFrameSources => const {
    FrameSourceKind.cpu,
    FrameSourceKind.miniavBufferCpu,
    FrameSourceKind.gpuTexture,
  };

  @override
  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  }) async {
    if (!_encodeCodecs.contains(config.codec)) return null;
    switch (config.codec) {
      case VideoCodec.mjpeg:
        return GpuCodecEncoder(MinigpuMjpegPipeline(config: config));
      default:
        return null;
    }
  }

  @override
  Future<PlatformDecoder?> createDecoder(
    DecoderConfig config, {
    BackendContext? context,
  }) async => null;

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async => null;

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async => null;
}
