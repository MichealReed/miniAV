/// Last-resort browser audio-decode backend, built on `decodeAudioData`.
///
/// Priority 40 — deliberately BELOW WebCodecs (80) and the pure-Dart container
/// framing (55), so it is only ever selected when nothing better claims the
/// codec. On web that means one of:
///   * the browser has no WebCodecs `AudioDecoder` at all (older Safari /
///     Firefox, many embedded webviews), or
///   * it has one that cannot configure this codec, which
///     [WebCodecsBackend.createAudioDecoder] now detects via
///     `AudioDecoder.isConfigSupported` and declines, letting the negotiator
///     fall through to here.
///
/// Decode-only: `decodeAudioData` has no encoder counterpart, and muxing /
/// demuxing belong to [ContainerFramingBackend].
library;

import 'dart:async';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'web_audio_fallback_decoder.dart';

class WebAudioFallbackBackend extends MiniAVToolsBackend {
  static const String backendName = 'webaudio_fallback';

  /// Below WebCodecs (80) and container framing (55): a floor, not a choice.
  static const int defaultPriority = 40;

  /// MP3 feeds `decodeAudioData` as-is; AAC is ADTS-wrapped from the
  /// AudioSpecificConfig (or passed through when packets already carry ADTS).
  /// AAC is the one that matters on WebKit: iOS shipped WebCodecs
  /// `VideoDecoder` (16.4) years before `AudioDecoder` (18.4), so without this
  /// an MP4's AAC track had no decoder and took the whole file down with it.
  /// FLAC/Vorbis stay out — their demuxed packets cannot be made
  /// self-contained (see [WebAudioFallbackDecoder]).
  static const _codecs = <AudioCodec>{AudioCodec.mp3, AudioCodec.aac};

  @override
  String get name => backendName;

  @override
  int get priority => defaultPriority;

  @override
  bool supportsEncode(VideoCodec codec, {bool hwAccel = false}) => false;

  @override
  bool supportsDecode(VideoCodec codec, {bool hwAccel = false}) => false;

  @override
  bool supportsAudioEncode(AudioCodec codec) => false;

  @override
  bool supportsAudioDecode(AudioCodec codec) => _codecs.contains(codec);

  @override
  bool supportsMux(Container container) => false;

  @override
  bool supportsDemux(Container container) => false;

  @override
  Set<FrameSourceKind> get acceptedFrameSources => const {};

  @override
  Future<PlatformAudioDecoder?> createAudioDecoder(
    AudioDecoderConfig config, {
    BackendContext? context,
  }) async {
    if (!_codecs.contains(config.codec)) return null;
    return WebAudioFallbackDecoder.create(config);
  }

  // Decode-only: `decodeAudioData` has no encode counterpart, and video /
  // container work belongs to WebCodecs and ContainerFramingBackend.

  @override
  Future<PlatformAudioEncoder?> createAudioEncoder(
    AudioEncoderConfig config, {
    BackendContext? context,
  }) async => null;

  @override
  Future<PlatformEncoder?> createEncoder(
    EncoderConfig config, {
    BackendContext? context,
  }) async => null;

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
