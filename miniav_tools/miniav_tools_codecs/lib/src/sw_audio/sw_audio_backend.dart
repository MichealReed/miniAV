/// First-party software audio-decode backend: MP3 (FFmpeg-free, via dr_mp3 in
/// the codecs native asset).
library;

import 'dart:async';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'sw_audio_decoder.dart';

class SwAudioBackend extends MiniAVToolsBackend {
  static const String backendName = 'sw_audio';

  /// Above FFmpeg (50) so MP3 decode is first-party; [SwAudioDecoder.open]
  /// never fails (data arrives later), so whatever is claimed here is FINAL —
  /// there is no fall-through once this backend wins.
  static const int defaultPriority = 55;

  /// MP3 only, and that is a capability statement, not a shortlist of what the
  /// native asset can do.
  ///
  /// dr_flac and stb_vorbis are linked and [SwAudioDecoder] drives them, but
  /// their entry points (`drflac_open_memory` / `stb_vorbis_open_memory`) take
  /// a WHOLE CONTAINER, and this decoder ignores `AudioDecoderConfig.extraData`
  /// — which is exactly where a demuxer puts the FLAC STREAMINFO / Vorbis setup
  /// headers it stripped. So a DEMUXED flac/vorbis stream (the only way the
  /// negotiator is ever asked for one) has no headers in front of it and fails
  /// every batch. Claiming those codecs here therefore did not mean "decoded
  /// first-party", it meant "never decoded at all": priority 55 outranks FFmpeg
  /// and open() cannot decline, so nothing downstream could recover.
  /// Un-claiming them routes flac/vorbis to ffmpeg (50), whose decoders are
  /// incremental and take extraData. Reclaiming them needs header synthesis
  /// from extraData first — a later release.
  ///
  /// Whole-file feeds still work through [SwAudioDecoder] directly (it accepts
  /// all three, in one packet or chunked); this is about what the NEGOTIATOR
  /// may hand a packet stream to.
  static const _codecs = {AudioCodec.mp3};

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
  }) => SwAudioDecoder.open(config);

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
