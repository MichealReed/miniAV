/// Abstract backend contract.
///
/// Each `miniav_tools_*` backend package implements [MiniAVToolsBackend] and
/// registers an instance with [MiniAVToolsPlatform.instance.register].
library;

import 'backend_context.dart';
import 'codec_types.dart';
import 'config.dart';
import 'frame_source.dart';
import 'platform_codec.dart';

abstract class MiniAVToolsBackend {
  /// Human-readable backend name, e.g. `"ffmpeg"`, `"webcodecs"`, `"minigpu"`.
  String get name;

  /// Higher value = preferred when multiple backends support the same codec.
  /// Backends should default to 0 and let users override via
  /// [MiniAVToolsPlatform.setBackendPriority].
  int get priority;

  // --- Capability queries ----------------------------------------------------

  bool supportsEncode(VideoCodec codec, {bool hwAccel = false});
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false});
  bool supportsAudioEncode(AudioCodec codec);
  bool supportsAudioDecode(AudioCodec codec);
  bool supportsMux(Container container);
  bool supportsDemux(Container container);

  /// Which [FrameSource] variants this backend can consume directly (without
  /// the facade falling back to CPU readback).
  Set<FrameSourceKind> get acceptedFrameSources;

  // --- Factories -------------------------------------------------------------
  // Return `null` if this backend cannot satisfy the request — the facade
  // will try the next backend by priority.
  //
  // The optional [context] carries cross-backend resources (e.g. a shared
  // GPU device) that the caller has already initialised. Backends that do
  // not recognise anything in the context MUST behave exactly as if it were
  // null — contexts are purely additive opt-ins.

  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  });
  Future<PlatformDecoder?> createDecoder(
    DecoderConfig config, {
    BackendContext? context,
  });
  Future<PlatformMuxer?> createMuxer(MuxerConfig config);
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config);

  /// Construct an audio encoder. Default implementation returns `null` —
  /// backends without audio support don't need to override.
  Future<PlatformAudioEncoder?> createAudioEncoder(
    AudioEncoderConfig config, {
    BackendContext? context,
  }) async => null;
}
