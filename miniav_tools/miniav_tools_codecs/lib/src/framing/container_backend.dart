/// Pure-Dart container framing backend: WAV + Ogg + ADTS + MP4 demux/mux, and
/// MP3 demux.
///
/// Registered ABOVE FFmpeg (priority 55 > 50) so these containers are handled
/// first-party (FFmpeg-free) by default; a parse failure returns `null`, so the
/// negotiator falls through to FFmpeg automatically for anything these parsers
/// can't handle. Bytes input/output only (file paths stay with FFmpeg).
library;

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import 'adts_container.dart';
// dart:io on the VM, a no-op on web -- ContainerFramingBackend is registered in
// both places and this file must stay web-safe.
import 'file_sink_stub.dart' if (dart.library.io) 'file_sink_io.dart';
import 'mp3_container.dart';
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
  // MP3 is demux-only: a first-party mp3 ENCODER is a separate question, and
  // claiming the container for mux would advertise a writer that does not
  // exist.
  static const _demuxContainers = {
    Container.wav,
    Container.ogg,
    Container.adts,
    Container.mp4,
    Container.m4a,
    Container.mp3,
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

  /// Why the most recent [createMuxer] call declined, or `null` when it
  /// opened.
  ///
  /// [createMuxer] must answer `null` on a refusal so the negotiator can try
  /// the next backend — and `null` carries no reason. A caller that PINNED
  /// this backend therefore sees a bare `NoBackendForCodecException` while the
  /// real diagnostic ("h264 extraData is Annex-B but carries no usable SPS")
  /// is discarded. Recorded here so the decision site can report it. Read it
  /// immediately after the failed call: it is process-global and the next
  /// `createMuxer` overwrites it.
  static CodecInitException? lastMuxerInitFailure;

  @override
  Future<PlatformMuxer?> createMuxer(MuxerConfig config) async {
    lastMuxerInitFailure = null;
    final out = config.output;
    // Reject an impossible destination NOW, not at finish(). On web there is no
    // filesystem, and the old failure mode was to accept the config, buffer the
    // entire recording, and only then admit it could never be saved -- by which
    // point the caller has nothing left to fall back to. Deliberately outside
    // the catch below: this is not a "try the next backend" condition, FFmpeg
    // cannot write a file here either.
    if (out is FileMuxerOutput && !muxerFileSinkAvailable) {
      throw CodecInitException(
        backendName,
        'this platform has no filesystem, so FileMuxerOutput("${out.path}") '
        'can never be honoured — use BytesMuxerOutput and save the result '
        'yourself',
      );
    }
    try {
      final PlatformMuxer? inner = switch (config.container) {
        Container.wav => WavMuxer.open(config),
        Container.ogg => OggMuxer.open(config),
        Container.adts => AdtsMuxer.open(config),
        Container.mp4 || Container.m4a => Mp4Muxer.open(config),
        _ => null,
      };
      if (inner == null) return null;
      if (out is! FileMuxerOutput) return inner;
      // MP4/WAV/ADTS stream straight to the path they were configured with, so
      // the whole recording never sits in RAM. Wrapping them would undo that.
      if (inner is Mp4Muxer && inner.ownsFileOutput) return inner;
      if (inner is WavMuxer && inner.ownsFileOutput) return inner;
      if (inner is AdtsMuxer && inner.ownsFileOutput) return inner;
      // Ogg still assembles bytes and exposes them through getBytes(); it does
      // not touch the filesystem. Handed a FileMuxerOutput it would therefore
      // report complete success and write nothing at all -- the worst possible
      // failure, because the caller has no way to tell. Wrap it.
      return _FileWritingMuxer(inner, out.path);
    } on CodecInitException catch (e) {
      lastMuxerInitFailure = e;
      return null; // fall through to FFmpeg
    }
  }

  @override
  Future<PlatformDemuxer?> createDemuxer(DemuxerConfig config) async {
    final input = config.input;
    if (input is! BytesDemuxerInput) return null; // bytes-only
    final bytes = input.bytes;
    try {
      final container = config.container ?? sniff(bytes);
      switch (container) {
        case Container.wav:
          return WavDemuxer.open(bytes);
        case Container.ogg:
          return OggDemuxer.open(bytes);
        case Container.adts:
          return AdtsDemuxer.open(bytes);
        case Container.mp3:
          return Mp3Demuxer.open(bytes);
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

  /// Sniff a container from magic bytes (RIFF / OggS / ftyp / ID3 / MPEG sync).
  ///
  /// Order matters. The fixed magics are unambiguous and go first; the ADTS and
  /// MP3 tests come last because they key off a 2-byte sync that random data
  /// hits often. Those two are told apart ONLY by the layer bits — [isAdtsSync]
  /// requires layer `00`, [isMp3Sync] requires layer `01` — so no byte pair can
  /// satisfy both, and an mp3 can no longer be handed to the AAC parser.
  ///
  /// An `ID3` tag is deliberately NOT treated as the answer: it is legal in
  /// front of an ADTS stream as well, and it can be megabytes of album art, so
  /// the tag is stepped over and the sync behind it decides. Guessing wrong is
  /// merely slow on the VM (FFmpeg is still there to fall through to) and fatal
  /// on web, where there is no second demuxer.
  /// Public so the DECISION can be tested, not just its consequence: a wrong
  /// guess and a correct one both end in `createDemuxer` returning null on the
  /// VM (the parser simply refuses), which makes the two indistinguishable
  /// from outside — and on web the wrong guess is a hard failure.
  static Container? sniff(List<int> b) {
    // "RIFF" is a CONTAINER-OF-CONTAINERS magic — AVI, WebP, ANI and RMID all
    // start with it. The form type at bytes 8..11 is what says which, so
    // claiming wav on the magic alone handed every .avi to the WAV parser
    // (which then failed, and on web there is no second demuxer to fall to).
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45) {
      return Container.wav; // "RIFF"…"WAVE"
    }
    if (b.length >= 4 && b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
      return Container.ogg; // "OggS"
    }
    // ISO-BMFF: a 'ftyp' box at offset 4.
    if (b.length >= 8 &&
        b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return Container.mp4; // "ftyp"
    }

    // Step over ID3v2 tags (they repeat, and writers pad behind them).
    var pos = 0;
    for (var n = id3TagLength(b, pos); n > 0 && pos + n <= b.length;
        n = id3TagLength(b, pos)) {
      pos += n;
    }
    final tagged = pos > 0;
    if (tagged) {
      while (pos < b.length && b[pos] == 0x00) {
        pos++;
      }
    }
    if (pos + 2 <= b.length) {
      if (isAdtsSync(b[pos], b[pos + 1])) return Container.adts;
      if (isMp3Sync(b[pos], b[pos + 1])) return Container.mp3;
    }
    // A tag we could step over but no sync behind it: still worth handing to
    // the mp3 demuxer, which searches for its own first frame.
    if (tagged) return Container.mp3;
    return null;
  }
}


/// Writes an in-memory container to disk when it is finished.
///
/// Only OggMuxer needs this now. It is a whole-file builder: it buffers packets
/// and emits the finished container from [PlatformMuxer.getBytes]. That makes
/// it a good fit for bounded output (a clip, a short asset) and a bad fit for
/// an open-ended recording -- nothing here changes that, it only makes the
/// bounded case actually produce a file.
///
/// Ogg is deliberately NOT streamed: unlike WAV (two length fields) and ADTS
/// (nothing at all), an Ogg page carries a CRC over its own bytes plus a
/// granule position and sequence number, so streaming it means building whole
/// pages before writing and choosing a page-packing policy — real work, for a
/// container nothing in this repo records into open-endedly.
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
    final List<List<int>>? parts;
    if (inner is Mp4Muxer) {
      parts = inner.outputParts;
    } else {
      // ONE getBytes() call: OggMuxer rebuilds the entire container on every
      // call, so asking twice doubles the work and the peak memory.
      final bytes = inner.getBytes();
      parts = bytes == null ? null : [bytes];
    }
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
