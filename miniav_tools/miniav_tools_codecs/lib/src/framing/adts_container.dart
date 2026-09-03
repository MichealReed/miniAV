/// ADTS (ISO/IEC 13818-7) demuxer + muxer for AAC — pure Dart, FFmpeg-free.
///
/// ADTS frames are self-describing (7-byte header, or 9 with CRC): profile,
/// sample-rate index, channel config, frame length. The demuxer emits raw AAC
/// packets + a 2-byte AudioSpecificConfig ([CodecExtraData]) so an AAC decoder
/// (a later OS-AAC epic) can init. [adtsToAsc] / [ascToAdtsParams] bridge the
/// two representations. The framing carries no codec logic, so it round-trips
/// any AAC payload today, ahead of a first-party AAC codec.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

// dart:io on the VM, a no-op on web — this file must stay web-safe.
import 'file_sink_stub.dart' if (dart.library.io) 'file_sink_io.dart';
import 'mp3_container.dart' show id3TagLength, isAdtsSync;
import 'muxer_file_sink.dart';

/// The 13 ADTS sampling-frequency-index → rate table (indexes 13-15 reserved).
const List<int> adtsSampleRates = [
  96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
  16000, 12000, 11025, 8000, 7350, 0, 0, 0, //
];

int _sampleRateIndex(int rate) {
  final i = adtsSampleRates.indexOf(rate);
  return i < 0 ? 4 : i; // default 44100
}

/// Build a 2-byte AAC-LC AudioSpecificConfig from ADTS params.
/// `[objType(5)=2 | srIndex(4) | chanCfg(4) | 0(3)]`.
Uint8List ascToAdtsParams(int sampleRateIndex, int channelConfig) {
  const objectType = 2; // AAC-LC
  final asc = Uint8List(2);
  asc[0] = (objectType << 3) | ((sampleRateIndex >> 1) & 0x07);
  asc[1] = ((sampleRateIndex & 0x01) << 7) | ((channelConfig & 0x0F) << 3);
  return asc;
}

class _AdtsHeader {
  _AdtsHeader(
    this.frameLength,
    this.srIndex,
    this.channelConfig,
    this.headerSize,
  );
  final int frameLength; // total frame incl. header
  final int srIndex;

  /// The raw `channel_configuration` field (0-7), NOT a channel count — the
  /// two differ at 7. Kept raw because the AudioSpecificConfig this demuxer
  /// emits carries the field, not the count.
  final int channelConfig;
  final int headerSize; // 7 (no CRC) or 9 (CRC)

  /// Channels the configuration denotes: 1-6 are their own count, 7 is 7.1
  /// (EIGHT channels — front L/R/C, LFE, side L/R, back L/R), and 0 means
  /// "described by an out-of-band AOT-specific config", which ADTS alone cannot
  /// answer. 0 stays 0 so [AdtsDemuxer.open] rejects it.
  int get channels => channelConfig == 7 ? 8 : channelConfig;
}

/// Inverse of [_AdtsHeader.channels]: a channel COUNT → the
/// `channel_configuration` field to write. 8 channels is config 7; anything
/// outside 1-8 has no configuration and is written as-is (already masked to 4
/// bits by the caller).
int _channelConfigFor(int channels) => channels == 8 ? 7 : channels;

/// Parse an ADTS header at [off], or `null` if invalid/truncated.
_AdtsHeader? _parseHeader(ByteData d, int off) {
  if (off + 7 > d.lengthInBytes) return null;
  final b1 = d.getUint8(off + 1);
  // Sync = 12 bits of 1 (0xFFF) AND layer == 00. The layer test is not
  // optional: ADTS shares its header shape with MPEG Audio, so without it every
  // bare mp3 frame (FF FB / FA / F3 / F2 — layer 01) parses as ADTS, reads a
  // "frame length" out of mp3 audio data, and desyncs on the very next frame.
  if (!isAdtsSync(d.getUint8(off), b1)) return null;
  final protectionAbsent = b1 & 0x01; // 1 = no CRC → 7-byte header
  final headerSize = protectionAbsent == 1 ? 7 : 9;

  final b2 = d.getUint8(off + 2);
  final b3 = d.getUint8(off + 3);
  final b4 = d.getUint8(off + 4);
  final b5 = d.getUint8(off + 5);

  final srIndex = (b2 >> 2) & 0x0F;
  // channel_configuration = b2[0] << 2 | b3[7:6]. See _AdtsHeader.channels: it
  // is an enum, not a count — 7 means 8 channels.
  final channelConfig = ((b2 & 0x01) << 2) | ((b3 >> 6) & 0x03);
  // frame_length is 13 bits: b3[1:0] | b4 | b5[7:5].
  final frameLength =
      ((b3 & 0x03) << 11) | (b4 << 3) | ((b5 >> 5) & 0x07);
  if (frameLength < headerSize) return null;

  return _AdtsHeader(frameLength, srIndex, channelConfig, headerSize);
}

/// Bounded forward hunt for the next CONFIRMED ADTS frame at/after [from], or
/// -1. Corruption in a broadcast/HLS capture is a byte or a packet, so a window
/// this size is generous while still terminating on a file that is not ADTS.
const int _resyncWindow = 1 << 16; // 64 KiB

int _resync(ByteData d, int from) {
  final end = from + _resyncWindow;
  final limit = end < d.lengthInBytes ? end : d.lengthInBytes;
  for (var pos = from; pos + 7 <= limit; pos++) {
    if (_confirmed(d, pos)) return pos;
  }
  return -1;
}

/// A frame at [pos] plus a matching frame right after it (or clean EOF).
///
/// The second-frame check is the whole point, exactly as in [Mp3Demuxer]: `FF
/// F1` occurs constantly inside compressed audio, so a resync that trusts one
/// sync word lands in the middle of a payload, reads a frame length out of
/// audio data and desyncs again on the next frame.
bool _confirmed(ByteData d, int pos) {
  final h = _parseHeader(d, pos);
  if (h == null) return false;
  final next = pos + h.frameLength;
  if (next > d.lengthInBytes) return false; // frame does not even fit
  if (next + 7 > d.lengthInBytes) return true; // last frame in the data
  return _parseHeader(d, next) != null;
}

/// ADTS demuxer: raw AAC-in-ADTS bytes → AAC packets.
class AdtsDemuxer implements PlatformDemuxer {
  AdtsDemuxer._(
    this.tracks,
    this._bytes,
    this._data,
    this._sampleRate,
    int start,
    this._frameLength,
  ) : _pos = start;

  @override
  final List<TrackInfo> tracks;

  final Uint8List _bytes;
  final ByteData _data;
  final int _sampleRate;
  int _pos;
  int _frame = 0;
  bool _closed = false;

  /// Length of the last header parsed, used to price a resync in FRAMES.
  /// Seeded from the first frame so a file that is damaged before its second
  /// good frame still has a yardstick.
  int _frameLength;

  /// First byte of audio: past any leading ID3v2 tags and the zero padding
  /// writers leave behind them.
  ///
  /// The sniffer ([ContainerFramingBackend]) already steps over tags before it
  /// decides a file is ADTS, so parsing from byte 0 here meant a tagged `.aac`
  /// was ACCEPTED by the sniffer and then rejected by the parser. On the VM
  /// that only wasted a fall-through to FFmpeg; on web there is no second
  /// demuxer, so it was a hard failure on a completely ordinary file.
  static int _audioStart(Uint8List b) {
    var pos = 0;
    for (var n = id3TagLength(b, pos); n > 0 && pos + n <= b.length;
        n = id3TagLength(b, pos)) {
      pos += n;
    }
    if (pos > 0) {
      while (pos < b.length && b[pos] == 0x00) {
        pos++;
      }
    }
    return pos;
  }

  static AdtsDemuxer open(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final start = _audioStart(bytes);
    final h = _parseHeader(data, start);
    if (h == null) throw const CodecInitException('adts', 'no ADTS sync');
    final sampleRate = adtsSampleRates[h.srIndex];
    if (sampleRate == 0 || h.channels < 1) {
      throw const CodecInitException('adts', 'bad ADTS sample-rate/channels');
    }
    // The ASC carries channel_configuration, not the channel count.
    final asc = ascToAdtsParams(h.srIndex, h.channelConfig);
    return AdtsDemuxer._(
      [
        AudioTrackInfo(
          codec: AudioCodec.aac,
          sampleRate: sampleRate,
          channels: h.channels,
          extraData: CodecExtraData.audio(AudioCodec.aac, asc),
        ),
      ],
      bytes,
      data,
      sampleRate,
      start,
      h.frameLength,
    );
  }

  /// A trailing ID3v1 block ('TAG' + 125 bytes, only ever the last 128 bytes of
  /// a file) — metadata, and the end of the audio.
  bool _isId3v1TrailerAt(int off) =>
      off + 128 == _bytes.length &&
      _bytes[off] == 0x54 &&
      _bytes[off + 1] == 0x41 &&
      _bytes[off + 2] == 0x47;

  /// Advance [_pos] onto the next complete ADTS frame and return its header,
  /// or `null` at a clean end of audio.
  ///
  /// A bad header is NOT necessarily the end of the stream. The old code
  /// returned null (a clean EOF, indistinguishable from a real one) on the first
  /// byte it couldn't parse, so an ID3v1 trailer or a single corrupt frame
  /// silently truncated the file — the caller saw a short track and no error at
  /// all.
  _AdtsHeader? _nextFrame() {
    for (;;) {
      if (_pos + 7 > _data.lengthInBytes) return null; // clean EOF
      // Tags are not only a file prefix: writers append an ID3v2 block after the
      // audio, and ID3v1 always sits in the last 128 bytes. Both are the end of
      // the audio, not corruption to hunt through.
      if (_isId3v1TrailerAt(_pos)) return null;
      final tag = id3TagLength(_bytes, _pos);
      if (tag > 0 && _pos + tag <= _bytes.length) {
        _pos += tag;
        continue;
      }
      final h = _parseHeader(_data, _pos);
      if (h != null) {
        // A frame that runs off the end is a truncated tail — nothing
        // downstream can use a partial frame, so stop.
        if (_pos + h.frameLength > _data.lengthInBytes) return null;
        _frameLength = h.frameLength;
        return h;
      }
      // Real corruption: hunt forward for the next confirmed frame instead of
      // discarding the rest of the file.
      final from = _pos;
      final next = _resync(_data, _pos + 1);
      if (next < 0) return null;
      _pos = next;
      // PTS is derived from the frame COUNT, so skipping the damage without
      // charging for it stamps every remaining packet early by the lost frames'
      // duration, permanently — the audio runs ahead of the video from the
      // corruption to the end of the file. Price the skipped span in frames.
      // The last good frame's length is the yardstick: exact for the CBR case
      // that dominates broadcast/HLS captures, an estimate under VBR (there is
      // nothing left in the damaged bytes to measure).
      _frame += _framesIn(next - from);
    }
  }

  /// Frames a [span] of skipped bytes stands for, rounded to nearest.
  int _framesIn(int span) =>
      _frameLength > 0 ? (span + _frameLength ~/ 2) ~/ _frameLength : 0;

  @override
  Future<EncodedPacket?> readPacket() async {
    _checkOpen();
    final h = _nextFrame();
    if (h == null) return null;

    final payloadOff = _pos + h.headerSize;
    final payloadLen = h.frameLength - h.headerSize;
    final out = Uint8List(payloadLen)
      ..setRange(
        0,
        payloadLen,
        _data.buffer.asUint8List(_data.offsetInBytes + payloadOff),
      );
    // Each AAC frame = 1024 samples.
    final ptsUs = _sampleRate > 0 ? _frame * 1024 * 1000000 ~/ _sampleRate : 0;
    _pos += h.frameLength;
    _frame++;
    return EncodedPacket(
      data: out,
      ptsUs: ptsUs,
      dtsUs: ptsUs,
      durationUs: _sampleRate > 0 ? 1024 * 1000000 ~/ _sampleRate : 0,
      isKeyframe: true,
    );
  }

  @override
  Future<void> seek(int timestampUs) async {
    _checkOpen();
    _pos = _audioStart(_bytes);
    _frame = 0;
    final target = _sampleRate > 0
        ? (timestampUs * _sampleRate ~/ 1000000) ~/ 1024
        : 0;
    // Same framing rules [readPacket] uses (tags skipped, corruption resynced),
    // so a seek and a linear read agree on where frame N is.
    while (_frame < target) {
      final h = _nextFrame();
      if (h == null) break;
      // A resync inside _nextFrame charges the damaged span to _frame, so it
      // can land ON or PAST the target. Consuming this frame as well would
      // overshoot the seek by the whole damaged region.
      if (_frame >= target) break;
      _pos += h.frameLength;
      _frame++;
    }
  }

  /// Total length, from a frame walk.
  ///
  /// ADTS carries no duration field, so the only honest answer is to count the
  /// frames — each is exactly 1024 samples. Returning `null` instead left the
  /// player with no seek bar at all on a perfectly ordinary `.aac`. The walk is
  /// O(n) over an in-memory buffer (header-hop only, no payload touched), done
  /// once on first read and cached, and it reuses [_nextFrame] so tags and
  /// corruption are priced exactly as playback prices them.
  int? _cachedDurationUs;

  @override
  int? get durationUs {
    // Deliberately NOT _checkOpen(): this is a plain getter over the in-memory
    // buffer, and the other three demuxers' durationUs never throw. A UI that
    // reads a player's duration during a rebuild after close() — an ordinary
    // teardown race — must get a value, not an exception out of build().
    final cached = _cachedDurationUs;
    if (cached != null) return cached;
    if (_sampleRate <= 0) return null;
    // The walk moves the read cursor, so borrow and restore it.
    final savedPos = _pos, savedFrame = _frame, savedLen = _frameLength;
    _pos = _audioStart(_bytes);
    _frame = 0;
    for (var h = _nextFrame(); h != null; h = _nextFrame()) {
      _pos += h.frameLength;
      _frame++;
    }
    final frames = _frame;
    _pos = savedPos;
    _frame = savedFrame;
    _frameLength = savedLen;
    return _cachedDurationUs = frames * 1024 * 1000000 ~/ _sampleRate;
  }

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('adts', 'demuxer closed');
  }
}

/// ADTS muxer: raw AAC packets → ADTS bytes (7-byte headers, no CRC, VBR).
///
/// Two output modes, same bytes. Handed a `FileMuxerOutput` (where `dart:io`
/// exists) it opens the file at [writeHeader] and appends each framed packet as
/// it arrives, so an open-ended recording never sits in RAM; otherwise it
/// buffers and emits from [PlatformMuxer.getBytes]. ADTS is the easy case:
/// there is no file header and no length field anywhere, so every byte written
/// is already final and nothing has to be patched at the end.
class AdtsMuxer implements PlatformMuxer {
  AdtsMuxer._(this._track, this._filePath);

  final AudioTrackInfo _track;

  /// Set when this muxer owns a `FileMuxerOutput` and the platform has a
  /// filesystem — i.e. when it will stream rather than buffer.
  final String? _filePath;

  final BytesBuilder _out = BytesBuilder();
  MuxerFileSink? _sink;
  bool _headerWritten = false;
  bool _finished = false;
  bool _closed = false;

  /// `true` when this muxer writes the configured `FileMuxerOutput` itself, so
  /// a caller must NOT also wrap it in a "collect the bytes and save them"
  /// adapter.
  bool get ownsFileOutput => _filePath != null;

  static AdtsMuxer open(MuxerConfig config) {
    if (config.tracks.isEmpty || config.tracks.first is! AudioTrackInfo) {
      throw const CodecInitException('adts', 'need one AudioTrackInfo');
    }
    final track = config.tracks.first as AudioTrackInfo;
    if (track.codec != AudioCodec.aac) {
      throw CodecInitException('adts', 'unsupported codec ${track.codec}');
    }
    final out = config.output;
    final path =
        (out is FileMuxerOutput && muxerFileSinkAvailable) ? out.path : null;
    return AdtsMuxer._(track, path);
  }

  @override
  Future<void> writeHeader() async {
    _checkOpen();
    if (_headerWritten) return;
    final path = _filePath;
    // No file-level header to write — opening the sink IS the header step.
    if (path != null) _sink = await openMuxerFileSink(path);
    _headerWritten = true;
  }

  @override
  Future<void> writePacket(EncodedPacket packet) async {
    _checkOpen();
    if (_finished) {
      throw const CodecRuntimeException('adts', 'writePacket after finish');
    }
    if (!_headerWritten) {
      throw const CodecRuntimeException('adts', 'writePacket before writeHeader');
    }
    final srIndex = _sampleRateIndex(_track.sampleRate);
    // channel_configuration, not a channel count (they differ at 8 channels) —
    // writing 8 here produced a header the demuxer reads back as config 0
    // ("out-of-band") and rejects.
    final chanCfg = _channelConfigFor(_track.channels) & 0x0F;
    final frameLen = packet.data.length + 7;

    // 7-byte ADTS header (MPEG-4, AAC-LC, protection_absent=1, VBR fullness).
    final frame = Uint8List(frameLen);
    frame[0] = 0xFF;
    frame[1] = 0xF1; // syncword low + MPEG-4 + layer 0 + no CRC
    frame[2] = (1 << 6) | (srIndex << 2) | ((chanCfg >> 2) & 0x01);
    frame[3] = ((chanCfg & 0x03) << 6) | ((frameLen >> 11) & 0x03);
    frame[4] = (frameLen >> 3) & 0xFF;
    frame[5] = ((frameLen & 0x07) << 5) | 0x1F; // + buffer_fullness hi (VBR)
    frame[6] = 0xFC; // buffer_fullness lo (VBR) + 0 raw-data-blocks
    frame.setRange(7, frameLen, packet.data);

    final sink = _sink;
    if (sink == null) {
      _out.add(frame);
      return;
    }
    await sink.add(frame);
  }

  @override
  Future<void> finish() async {
    _checkOpen();
    if (_finished) return;
    _finished = true;
    final sink = _sink;
    if (sink == null) return;
    await sink.close();
    _sink = null;
  }

  @override
  Future<void> close() async {
    _closed = true;
    final sink = _sink;
    _sink = null;
    if (sink != null) await sink.close();
    // The buffered stream is NOT dropped here: in bytes mode it IS the
    // recording, close() auto-finishes, and getBytes() has no ordering guard —
    // so dropping it turned `close(); getBytes();` into a zero-length file that
    // still parses as "no frames". WavMuxer and Mp4Muxer keep theirs too.
  }

  /// The finished stream, or `null` in streaming mode — where the bytes went to
  /// the file instead and were never retained.
  @override
  List<int>? getBytes() => _filePath != null ? null : _out.toBytes();

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('adts', 'muxer closed');
  }
}
