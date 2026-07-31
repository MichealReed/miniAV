/// Pure-Dart container framing backend: WAV + Ogg + ADTS demux/mux.
///
/// Registered ABOVE FFmpeg (priority 55 > 50) so these three simple containers
/// are handled first-party (FFmpeg-free) by default; a parse failure returns
/// `null`, so the negotiator falls through to FFmpeg automatically for anything
/// these parsers can't handle. Bytes input/output only (file paths stay with
/// FFmpeg).
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'adts_container.dart';
// dart:io on the VM, a no-op on web -- ContainerFramingBackend is registered in
// both places and this file must stay web-safe.
import 'file_sink_stub.dart' if (dart.library.io) 'file_sink_io.dart';
import 'mp4_container.dart';
import 'ogg_container.dart';
import 'wav_container.dart';

class ContainerFramingBackend extends MiniAVToolsBackend {
  static const String backendName = 'container_framing';
  static const int defaultPriority = 55; // > FFmpeg (50)

  // WAV/Ogg/ADTS/MP4 mux + demux are all first-party here (Mp4Muxer handles
  // H.264/HEVC/AV1 video + AAC/Opus audio).
  static const _muxContainers = {
    Container.wav,
    Container.ogg,
    Container.adts,
    Container.mp4,
    Container.m4a, // audio-only MP4 — same ISO-BMFF writer
  };
  static const _demuxContainers = {
    Container.wav,
    Container.ogg,
    Container.adts,
    Container.mp4,
    Container.m4a,
  };

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
  bool supportsAudioDecode(AudioCodec codec) => false;

  @override
  bool supportsMux(Container container) => _muxContainers.contains(container);

  @override
  bool supportsDemux(Container container) =>
      _demuxContainers.contains(container);

  @override
  Set<FrameSourceKind> get acceptedFrameSources => const {};

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
  Future<PlatformAudioEncoder?> createAudioEncoder(
    AudioEncoderConfig config, {
    BackendContext? context,
  }) async => null;

  @override
  Future<PlatformAudioDecoder?> createAudioDecoder(
    AudioDecoderConfig config, {
    BackendContext? context,
  }) async => null;

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async {
    try {
      final PlatformMuxer? inner = switch (config.container) {
        Container.wav => WavMuxer.open(config),
        Container.ogg => OggMuxer.open(config),
        Container.adts => AdtsMuxer.open(config),
        Container.mp4 || Container.m4a => Mp4Muxer.open(config),
        _ => null,
      };
      if (inner == null) return null;
      // Every first-party muxer assembles bytes and exposes them through
      // getBytes(); none of them touch the filesystem. Handed a
      // FileMuxerOutput they therefore reported complete success and wrote
      // nothing at all -- the worst possible failure, because the caller has no
      // way to tell. Rather than teach each muxer about files, wrap them once.
      final out = config.output;
      return out is FileMuxerOutput ? _FileWritingMuxer(inner, out.path) : inner;
    } on CodecInitException {
      return null; // fall through to FFmpeg
    }
  }

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async {
    final input = config.input;
    if (input is! BytesDemuxerInput) return null; // bytes-only
    final bytes = input.bytes;
    try {
      final container = config.container ?? _sniff(bytes);
      switch (container) {
        case Container.wav:
          return WavDemuxer.open(bytes);
        case Container.ogg:
          return OggDemuxer.open(bytes);
        case Container.adts:
          return AdtsDemuxer.open(bytes);
        case Container.mp4:
        case Container.m4a:
          return Mp4Demuxer.open(bytes);
        default:
          return null;
      }
    } on CodecInitException {
      return null; // fall through to FFmpeg
    }
  }

  /// Sniff a container from magic bytes (RIFF / OggS / ADTS sync).
  static Container? _sniff(List<int> b) {
    if (b.length >= 4 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
      return Container.wav; // "RIFF"
    }
    if (b.length >= 4 && b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return Container.ogg; // "OggS"
    }
    if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xF0) == 0xF0) {
      return Container.adts; // ADTS sync
    }
    // ISO-BMFF: a 'ftyp' box at offset 4.
    if (b.length >= 8 &&
        b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return Container.mp4; // "ftyp"
    }
    return null;
  }
}


/// Writes an in-memory container to disk when it is finished.
///
/// The wrapped muxers are whole-file builders: they buffer packets and emit the
/// finished container from [PlatformMuxer.finish]. That makes them a good fit
/// for bounded output (a clip, a short asset) and a bad fit for an open-ended
/// recording, which should stream instead -- nothing here changes that, it only
/// makes the bounded case actually produce a file.
class _FileWritingMuxer implements PlatformMuxer {
  _FileWritingMuxer(this._inner, this._path);

  final PlatformMuxer _inner;
  final String _path;

  @override
  Future<void> writeHeader() => _inner.writeHeader();

  @override
  Future<void> writePacket(EncodedPacket packet) => _inner.writePacket(packet);

  @override
  Future<void> finish() async {
    await _inner.finish();
    // Ordered pieces where the muxer can provide them -- concatenating first
    // would double the peak memory of a large clip for no benefit, since the
    // bytes are going straight out to a sink either way.
    final inner = _inner;
    final List<List<int>>? parts = inner is Mp4Muxer
        ? inner.outputParts
        : (inner.getBytes() == null ? null : [inner.getBytes()!]);
    if (parts == null) {
      throw CodecRuntimeException(
        ContainerFramingBackend.backendName,
        'muxer finished without producing bytes; nothing to write to $_path',
      );
    }
    if (!await writeMuxerFileParts(_path, parts)) {
      throw CodecRuntimeException(
        ContainerFramingBackend.backendName,
        'this platform has no filesystem — use BytesMuxerOutput and write the '
        'result yourself (requested $_path)',
      );
    }
  }

  @override
  List<int>? getBytes() => _inner.getBytes();

  @override
  Future<void> close() => _inner.close();
}
