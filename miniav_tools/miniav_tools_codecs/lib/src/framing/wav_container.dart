/// WAV (RIFF/WAVE) demuxer + muxer — pure Dart, FFmpeg-free.
///
/// Linear PCM. The demuxer reads plain `fmt` tags 1 (integer) and 3 (IEEE
/// float) and `WAVE_FORMAT_EXTENSIBLE` (0xFFFE), which is what essentially
/// every multichannel or >16-bit writer emits and which carries the real
/// format in a SubFormat GUID.
///
/// **Sample formats are converted here**, because the platform interface has
/// exactly two PCM codecs. 16-bit integer and 32-bit float pass through as
/// [AudioCodec.pcmS16le] / [AudioCodec.pcmF32le]; 8-bit UNSIGNED becomes
/// `pcmS16le` (`(b-128) << 8`, exact) and 24-bit packed becomes `pcmF32le`
/// (`v / 2^23`, exact — 24 bits fit a float32 mantissa). So the track's codec
/// describes the PACKETS this demuxer emits, not the bits on disk; the source
/// width is only visible in the byte/duration arithmetic.
///
/// Malformed or still-unsupported input (32-bit integer, 64-bit float, a
/// container wider than its valid bits) throws [CodecInitException], and the
/// negotiator falls through to FFmpeg.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

// dart:io on the VM, a no-op on web — this file must stay web-safe.
import 'file_sink_stub.dart' if (dart.library.io) 'file_sink_io.dart';
import 'muxer_file_sink.dart';

/// How the samples are stored in the `data` chunk — which is not always how
/// they leave [WavDemuxer.readPacket] (see the library doc).
enum _Src {
  /// Unsigned 8-bit, midpoint 128 → converted to s16.
  u8,

  /// Signed 16-bit little-endian → passthrough.
  s16,

  /// Signed 24-bit packed little-endian (3 bytes/sample) → converted to f32.
  s24,

  /// IEEE float32 little-endian → passthrough.
  f32,
}

int _srcBytes(_Src s) => switch (s) {
      _Src.u8 => 1,
      _Src.s16 => 2,
      _Src.s24 => 3,
      _Src.f32 => 4,
    };

/// WAV demuxer: RIFF/WAVE bytes → PCM packets.
class WavDemuxer implements PlatformDemuxer {
  WavDemuxer._(
    this.tracks,
    this._data,
    this._dataStart,
    this._dataSize,
    this._sampleRate,
    this._channels,
    this._src,
  );

  final ByteData _data;
  final int _dataStart;
  final int _dataSize;
  final int _sampleRate;
  final int _channels;
  final _Src _src;

  @override
  final List<TrackInfo> tracks;

  int _bytesRead = 0;
  bool _closed = false;

  /// Bytes per frame IN THE FILE. Not the emitted packet's frame size when a
  /// conversion is in play (u8 → s16 doubles it, s24 → f32 grows it by a third).
  int get _bytesPerFrame => _srcBytes(_src) * _channels;

  /// Open a WAV demuxer, or throw [CodecInitException] on malformed input.
  static WavDemuxer open(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (data.lengthInBytes < 12 ||
        !_fourcc(data, 0, 'RIFF') ||
        !_fourcc(data, 8, 'WAVE')) {
      throw const CodecInitException('wav', 'not a RIFF/WAVE file');
    }

    var fmtStart = -1, fmtSize = 0, dataStart = -1, dataSize = 0;
    var pos = 12;
    while (pos + 8 <= data.lengthInBytes) {
      final id = _readFourcc(data, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      if (id == 'fmt ') {
        fmtStart = pos + 8;
        fmtSize = size;
      } else if (id == 'data') {
        dataStart = pos + 8;
        // Clamp to the actual buffer (some writers leave size=0 or too large).
        dataSize = size;
        if (dataStart + dataSize > data.lengthInBytes) {
          dataSize = data.lengthInBytes - dataStart;
        }
        if (size == 0) {
          // A 0-length `data` chunk in front of real samples is what an
          // INTERRUPTED streaming recording looks like: WavMuxer reserves both
          // RIFF lengths at writeHeader and only patches them in finish(), so a
          // capture that is killed leaves the header saying "empty" over
          // megabytes of PCM. Taking the rest of the file (what FFmpeg does) is
          // what recovers it — reporting 0 frames here read back as an empty
          // file with no error anywhere, and since open() still succeeded the
          // negotiator never fell through to a demuxer that could recover it.
          dataSize = data.lengthInBytes - dataStart;
          // The remainder is samples, not chunks: continuing the walk would let
          // PCM that happens to spell 'fmt ' or 'data' overwrite the real ones.
          break;
        }
      }
      final next = (pos + 8 + size + 1) & ~1; // 2-byte aligned
      if (next <= pos) break; // guard against overflow / zero-size loop
      pos = next;
    }

    if (fmtStart < 0 || fmtSize < 16) {
      throw const CodecInitException('wav', 'missing/short fmt chunk');
    }
    if (dataStart < 0) {
      throw const CodecInitException('wav', 'missing data chunk');
    }

    var format = data.getUint16(fmtStart, Endian.little);
    final channels = data.getUint16(fmtStart + 2, Endian.little);
    final sampleRate = data.getUint32(fmtStart + 4, Endian.little);
    final bits = data.getUint16(fmtStart + 14, Endian.little);
    var validBits = bits;

    if (format == 0xFFFE) {
      // WAVE_FORMAT_EXTENSIBLE: a 22-byte extension holding the real valid-bit
      // count, a channel mask, and a SubFormat GUID whose first 2 bytes are the
      // format tag the file would have used if it fit in one. Required for >2
      // channels or >16 bits, so rejecting it rejected most 24-bit files.
      if (fmtSize < 40 || fmtStart + 40 > data.lengthInBytes) {
        throw const CodecInitException('wav', 'short WAVE_FORMAT_EXTENSIBLE');
      }
      validBits = data.getUint16(fmtStart + 18, Endian.little);
      if (!_isPcmSubFormatGuid(data, fmtStart + 24)) {
        throw const CodecInitException(
            'wav', 'EXTENSIBLE SubFormat is not a PCM/IEEE-float GUID');
      }
      format = data.getUint16(fmtStart + 24, Endian.little);
    }
    if (format != 1 && format != 3) {
      // 1 = PCM integer, 3 = IEEE float. Anything else is unsupported.
      throw CodecInitException('wav', 'unsupported WAVE format tag $format');
    }
    // 0 means "all of the container is valid" (writers do emit it). Anything
    // else narrower than the container leaves the samples justified inside a
    // wider word, which no writer agrees on — refuse rather than mis-scale.
    if (validBits == 0) validBits = bits;
    if (validBits != bits) {
      throw CodecInitException(
          'wav', 'valid bits $validBits != container $bits');
    }

    final _Src src;
    if (format == 1 && bits == 8) {
      src = _Src.u8;
    } else if (format == 1 && bits == 16) {
      src = _Src.s16;
    } else if (format == 1 && bits == 24) {
      src = _Src.s24;
    } else if (format == 3 && bits == 32) {
      src = _Src.f32;
    } else {
      throw CodecInitException('wav', 'unsupported PCM: fmt=$format bits=$bits');
    }
    // The codec names the packets this demuxer emits, after conversion.
    final codec = switch (src) {
      _Src.u8 || _Src.s16 => AudioCodec.pcmS16le,
      _Src.s24 || _Src.f32 => AudioCodec.pcmF32le,
    };
    if (channels < 1 || channels > 8 || sampleRate < 1) {
      throw CodecInitException('wav', 'bad ch=$channels sr=$sampleRate');
    }

    return WavDemuxer._(
      [AudioTrackInfo(codec: codec, sampleRate: sampleRate, channels: channels)],
      data,
      dataStart,
      dataSize,
      sampleRate,
      channels,
      src,
    );
  }

  @override
  Future<EncodedPacket?> readPacket() async {
    _checkOpen();
    if (_bytesRead >= _dataSize) return null;
    const maxFrames = 4096;
    final maxBytes = maxFrames * _bytesPerFrame;
    var toRead = _dataSize - _bytesRead;
    if (toRead > maxBytes) toRead = maxBytes;
    // Whole frames only.
    toRead -= toRead % _bytesPerFrame;
    if (toRead <= 0) return null;

    final out = _convert(_dataStart + _bytesRead, toRead);
    final frames = toRead ~/ _bytesPerFrame;
    final ptsUs = (_bytesRead ~/ _bytesPerFrame) * 1000000 ~/ _sampleRate;
    _bytesRead += toRead;
    return EncodedPacket(
      data: out,
      ptsUs: ptsUs,
      dtsUs: ptsUs,
      durationUs: frames * 1000000 ~/ _sampleRate,
      isKeyframe: true,
    );
  }

  /// [len] source bytes at [off] as one packet in the track's emitted format.
  Uint8List _convert(int off, int len) {
    final src = _data.buffer.asUint8List(_data.offsetInBytes + off, len);
    switch (_src) {
      case _Src.s16:
      case _Src.f32:
        return Uint8List.fromList(src); // already the emitted format
      case _Src.u8:
        // Unsigned midpoint-128 → signed 16-bit. Exact: the 8-bit value keeps
        // its full range in the high byte.
        final out = Uint8List(len * 2);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < len; i++) {
          bd.setInt16(i * 2, (src[i] - 128) << 8, Endian.little);
        }
        return out;
      case _Src.s24:
        // Packed 3-byte little-endian two's complement → float32 in [-1,1).
        // Exact: 24 significant bits fit a float32 mantissa.
        final n = len ~/ 3;
        final out = Uint8List(n * 4);
        final bd = ByteData.sublistView(out);
        for (var i = 0; i < n; i++) {
          final b0 = src[i * 3], b1 = src[i * 3 + 1], b2 = src[i * 3 + 2];
          var v = b0 | (b1 << 8) | (b2 << 16);
          if ((v & 0x800000) != 0) v -= 0x1000000; // sign-extend
          bd.setFloat32(i * 4, v / 8388608.0, Endian.little);
        }
        return out;
    }
  }

  @override
  Future<void> seek(int timestampUs) async {
    _checkOpen();
    final frame = timestampUs * _sampleRate ~/ 1000000;
    final byteOffset = (frame * _bytesPerFrame).clamp(0, _dataSize);
    _bytesRead = byteOffset - (byteOffset % _bytesPerFrame);
  }

  @override
  int? get durationUs => _sampleRate > 0
      ? (_dataSize ~/ _bytesPerFrame) * 1000000 ~/ _sampleRate
      : null;

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('wav', 'demuxer closed');
  }
}

/// WAV muxer: PCM packets → RIFF/WAVE.
///
/// Two output modes, same bytes:
///
///  * **In-memory** (`BytesMuxerOutput`, or any platform without a filesystem).
///    Packets are buffered and the container is assembled by
///    [PlatformMuxer.getBytes].
///  * **Streaming** (`FileMuxerOutput` where `dart:io` exists). The 44-byte
///    canonical header goes out at [writeHeader] with both lengths reserved,
///    every packet is appended as it arrives, and [finish] patches the two
///    32-bit lengths. An open-ended recording therefore costs nothing in RAM —
///    which is the whole difference, since a WAV is its PCM.
class WavMuxer implements PlatformMuxer {
  WavMuxer._(this._track, this._filePath);

  /// Byte offsets of the two lengths in the canonical 44-byte header: the RIFF
  /// chunk size and the `data` chunk size.
  static const int _riffSizeOffset = 4;
  static const int _dataSizeOffset = 40;
  static const int _headerLength = 44;

  final AudioTrackInfo _track;

  /// Set when this muxer owns a `FileMuxerOutput` and the platform has a
  /// filesystem — i.e. when it will stream rather than buffer.
  final String? _filePath;

  final BytesBuilder _pcm = BytesBuilder();
  MuxerFileSink? _sink;
  int _pcmLen = 0;
  bool _headerWritten = false;
  bool _finished = false;
  bool _closed = false;

  /// `true` when this muxer writes the configured `FileMuxerOutput` itself, so
  /// a caller must NOT also wrap it in a "collect the bytes and save them"
  /// adapter.
  bool get ownsFileOutput => _filePath != null;

  static WavMuxer open(MuxerConfig config) {
    if (config.tracks.isEmpty || config.tracks.first is! AudioTrackInfo) {
      throw const CodecInitException('wav', 'need one AudioTrackInfo');
    }
    final track = config.tracks.first as AudioTrackInfo;
    if (track.codec != AudioCodec.pcmS16le &&
        track.codec != AudioCodec.pcmF32le) {
      throw CodecInitException('wav', 'unsupported codec ${track.codec}');
    }
    final out = config.output;
    final path =
        (out is FileMuxerOutput && muxerFileSinkAvailable) ? out.path : null;
    return WavMuxer._(track, path);
  }

  @override
  Future<void> writeHeader() async {
    _checkOpen();
    if (_headerWritten) return;
    final path = _filePath;
    if (path != null) {
      final sink = await openMuxerFileSink(path);
      _sink = sink;
      // Both lengths are 0 for now; finish() patches them. A reader that sees
      // an unpatched file gets a well-formed but empty WAVE, not garbage.
      await sink.add(_header(0));
    }
    _headerWritten = true;
  }

  @override
  Future<void> writePacket(EncodedPacket packet) async {
    _checkOpen();
    if (_finished) {
      throw const CodecRuntimeException('wav', 'writePacket after finish');
    }
    if (!_headerWritten) {
      throw const CodecRuntimeException('wav', 'writePacket before writeHeader');
    }
    final sink = _sink;
    if (sink == null) {
      _pcm.add(packet.data);
      return;
    }
    await sink.add(packet.data);
    _pcmLen += packet.data.length;
  }

  @override
  Future<void> finish() async {
    _checkOpen();
    if (_finished) return;
    _finished = true;
    final sink = _sink;
    if (sink == null) return;
    await sink.patchU32Le(_riffSizeOffset, 36 + _pcmLen);
    await sink.patchU32Le(_dataSizeOffset, _pcmLen);
    await sink.close();
    _sink = null;
  }

  @override
  Future<void> close() async {
    _closed = true;
    // An aborted recording still has to let go of the handle.
    final sink = _sink;
    _sink = null;
    if (sink != null) await sink.close();
    // The buffered PCM is NOT dropped here: in bytes mode it IS the recording,
    // close() auto-finishes, and getBytes() has no ordering guard — so dropping
    // it turned `close(); getBytes();` into a 44-byte silent WAVE that still
    // parses. Mp4Muxer keeps its finished bytes across close() for the same
    // reason.
  }

  /// The finished container, or `null` in streaming mode — where the bytes went
  /// to the file instead and were never retained.
  @override
  List<int>? getBytes() {
    if (_filePath != null) return null;
    final pcm = _pcm.toBytes();
    final out = BytesBuilder();
    out.add(_header(pcm.length));
    out.add(pcm);
    return out.toBytes();
  }

  /// The canonical 44-byte RIFF/WAVE header for [pcmLength] bytes of samples.
  Uint8List _header(int pcmLength) {
    final bytesPerSample = _track.codec == AudioCodec.pcmS16le ? 2 : 4;
    final formatTag = _track.codec == AudioCodec.pcmS16le ? 1 : 3;
    final blockAlign = _track.channels * bytesPerSample;

    final out = BytesBuilder();
    out.add('RIFF'.codeUnits);
    _u32(out, 36 + pcmLength);
    out.add('WAVE'.codeUnits);
    out.add('fmt '.codeUnits);
    _u32(out, 16);
    _u16(out, formatTag);
    _u16(out, _track.channels);
    _u32(out, _track.sampleRate);
    _u32(out, _track.sampleRate * blockAlign); // byte rate
    _u16(out, blockAlign);
    _u16(out, bytesPerSample * 8); // bits per sample
    out.add('data'.codeUnits);
    _u32(out, pcmLength);
    final b = out.toBytes();
    assert(b.length == _headerLength);
    return b;
  }

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('wav', 'muxer closed');
  }
}

// --- shared little-endian helpers -------------------------------------------

/// The fixed 14-byte tail every `KSDATAFORMAT_SUBTYPE_*` GUID shares:
/// `{XXXXXXXX-0000-0010-8000-00aa00389b71}`. Only the leading u32 varies, and
/// its low 16 bits are the classic format tag — so checking this tail is what
/// distinguishes a PCM/float SubFormat from, say, an AC-3 or ADPCM one.
const List<int> _ksGuidTail = [
  0x00, 0x00, // rest of Data1
  0x00, 0x00, // Data2
  0x10, 0x00, // Data3
  0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71, // Data4
];

bool _isPcmSubFormatGuid(ByteData d, int off) {
  if (off + 16 > d.lengthInBytes) return false;
  for (var i = 0; i < _ksGuidTail.length; i++) {
    if (d.getUint8(off + 2 + i) != _ksGuidTail[i]) return false;
  }
  return true;
}

bool _fourcc(ByteData d, int off, String s) {
  if (off + 4 > d.lengthInBytes) return false;
  for (var i = 0; i < 4; i++) {
    if (d.getUint8(off + i) != s.codeUnitAt(i)) return false;
  }
  return true;
}

String _readFourcc(ByteData d, int off) =>
    String.fromCharCodes([for (var i = 0; i < 4; i++) d.getUint8(off + i)]);

void _u16(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
}

void _u32(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}
