/// Ogg (RFC 3533) demuxer + muxer for Opus-in-Ogg (RFC 7845) — pure Dart,
/// FFmpeg-free.
///
/// The demuxer does REAL Ogg packet extraction: it walks every page's segment
/// (lacing) table, reassembling packets that span segments/pages, so it reads
/// genuine `.opus` files (which pack many Opus frames per page), not just
/// one-packet-per-page files. It skips the two Opus header packets (OpusHead +
/// OpusTags) and surfaces OpusHead as the track's [CodecExtraData] so the
/// decoder learns channels / sample-rate / pre-skip.
///
/// The muxer writes valid Ogg: one Opus packet per page (spec-legal), with a
/// correct Ogg CRC-32 so the output is a real, playable `.opus` stream.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

import '../opus/opus_bitstream.dart';

const List<int> _oggS = [0x4F, 0x67, 0x67, 0x53]; // "OggS"
const List<int> _opusHeadMagic = opusHeadMagic;
const List<int> _opusTagsMagic = [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73];

bool _startsWith(Uint8List d, List<int> magic) {
  if (d.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (d[i] != magic[i]) return false;
  }
  return true;
}

/// Ogg demuxer: parses all pages up-front (input is fully in memory) into a flat
/// list of Opus audio packets, skipping the header packets.
class OggDemuxer implements PlatformDemuxer {
  OggDemuxer._(
    this.tracks,
    this._packets,
    this._startSamples,
    this._durSamples,
    this._totalSamples,
  );

  @override
  final List<TrackInfo> tracks;

  final List<Uint8List> _packets;

  /// Per-audio-packet start position on the PLAYBACK timeline, in 48 kHz
  /// samples (pre-skip already removed, so packet 0 starts at 0).
  final List<int> _startSamples;

  /// Per-audio-packet duration in 48 kHz samples, from its TOC byte.
  final List<int> _durSamples;

  /// Playable length in 48 kHz samples: the final page's granule position minus
  /// the pre-skip, which is the one number that also accounts for end-trimming.
  final int _totalSamples;

  int _idx = 0;
  bool _closed = false;

  static OggDemuxer open(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (data.lengthInBytes < 27 || !_matchOggS(data, 0)) {
      throw const CodecInitException('ogg', 'not an Ogg stream');
    }

    // --- Reassemble packets across pages via the lacing table. -------------
    final rawPackets = <Uint8List>[];
    final pending = BytesBuilder();
    // The last page's granule position: total decoded 48 kHz samples, pre-skip
    // included (RFC 7845 §4). Authoritative for duration — an encoder shortens
    // it to trim the zero-padding it added to fill the final frame.
    var lastGranule = -1;
    var pos = 0;
    while (pos + 27 <= data.lengthInBytes) {
      if (!_matchOggS(data, pos)) {
        throw const CodecInitException('ogg', 'bad page capture pattern');
      }
      final segCount = data.getUint8(pos + 26);
      final segTableEnd = pos + 27 + segCount;
      if (segTableEnd > data.lengthInBytes) {
        throw const CodecInitException('ogg', 'truncated segment table');
      }
      var payloadOff = segTableEnd;
      for (var i = 0; i < segCount; i++) {
        final segLen = data.getUint8(pos + 27 + i);
        if (payloadOff + segLen > data.lengthInBytes) {
          throw const CodecInitException('ogg', 'truncated page payload');
        }
        pending.add(
          data.buffer.asUint8List(data.offsetInBytes + payloadOff, segLen),
        );
        payloadOff += segLen;
        if (segLen < 255) {
          // A segment < 255 ends the current packet.
          rawPackets.add(pending.toBytes());
          pending.clear();
        }
        // segLen == 255 → packet continues into the next segment/page.
      }
      // Granule position: 64-bit LE at byte 6. -1 (all ones) means "no packet
      // finishes on this page", so it is not a length.
      final gLo = data.getUint32(pos + 6, Endian.little);
      final gHi = data.getUint32(pos + 10, Endian.little);
      if (!(gLo == 0xFFFFFFFF && gHi == 0xFFFFFFFF)) {
        lastGranule = (gHi << 32) | gLo;
      }
      pos = payloadOff;
    }

    // --- Identify + strip the Opus header packets. -------------------------
    if (rawPackets.isEmpty || !_startsWith(rawPackets.first, _opusHeadMagic)) {
      throw const CodecInitException('ogg', 'first packet is not OpusHead');
    }
    final opusHead = rawPackets.first;
    var sampleRate = 48000;
    var channels = 2;
    if (opusHead.length >= 19) {
      channels = opusHead[9];
      sampleRate = opusHead[12] |
          (opusHead[13] << 8) |
          (opusHead[14] << 16) |
          (opusHead[15] << 24);
      if (sampleRate <= 0) sampleRate = 48000;
    }

    // Drop OpusHead + (optional) OpusTags; the rest are audio packets.
    var audioStart = 1;
    if (rawPackets.length > 1 && _startsWith(rawPackets[1], _opusTagsMagic)) {
      audioStart = 2;
    }
    final audio = rawPackets.sublist(audioStart);
    final preSkip = opusHeadPreSkip(opusHead);

    // Per-packet timing from the TOC byte, on the PLAYBACK timeline (pre-skip
    // removed). 20 ms is only the default frame size — 10/40/60 ms packets are
    // legal and common, so the old `index * 20000` was off by up to 3x on
    // ordinary files, and so was the matching seek.
    final starts = List<int>.filled(audio.length, 0);
    final durs = List<int>.filled(audio.length, 0);
    var cum = 0;
    for (var i = 0; i < audio.length; i++) {
      final d = opusPacketSamples48k(audio[i]);
      // A packet we cannot price would desynchronise everything after it; fall
      // back to the 20 ms default rather than stamping it zero-length.
      durs[i] = d > 0 ? d : 960;
      final start = cum - preSkip;
      starts[i] = start > 0 ? start : 0;
      cum += durs[i];
    }
    // The final granule is the encoder's own answer, and the only one that
    // knows about tail-trimming; the TOC sum is the fallback for a stream whose
    // last page carries no granule.
    final total =
        (lastGranule > preSkip ? lastGranule : cum) - preSkip;

    // Durations on the SAME timeline as the starts. The trimmed samples are not
    // playable, so charging a packet its full TOC length while its start has
    // already been pulled back makes the emitted timeline self-contradictory:
    // packet 0 would overlap packet 1, and the durations would sum past
    // [durationUs] — which a remuxer that builds its sample table out of
    // EncodedPacket.durationUs (MP4's stts) writes straight into the file.
    // Each packet spans up to the next one's start; the last spans to the end.
    for (var i = 0; i < audio.length; i++) {
      final end = i + 1 < audio.length ? starts[i + 1] : (total > 0 ? total : 0);
      final d = end - starts[i];
      durs[i] = d < 0 ? 0 : (d > durs[i] ? durs[i] : d);
    }

    final track = AudioTrackInfo(
      codec: AudioCodec.opus,
      sampleRate: sampleRate,
      channels: channels,
      extraData: CodecExtraData.audio(AudioCodec.opus, opusHead),
    );
    return OggDemuxer._([track], audio, starts, durs, total < 0 ? 0 : total);
  }

  static int _us(int samples48k) => samples48k * 1000000 ~/ 48000;

  @override
  Future<EncodedPacket?> readPacket() async {
    _checkOpen();
    if (_idx >= _packets.length) return null;
    final data = _packets[_idx];
    final ptsUs = _us(_startSamples[_idx]);
    final durUs = _us(_durSamples[_idx]);
    _idx++;
    return EncodedPacket(
      data: data,
      ptsUs: ptsUs,
      dtsUs: ptsUs,
      durationUs: durUs,
      isKeyframe: true,
    );
  }

  @override
  Future<void> seek(int timestampUs) async {
    _checkOpen();
    // Land on the packet that CONTAINS the target: the last one starting at or
    // before it. Dividing by a fixed 20 ms was wrong for every other frame size.
    var lo = 0, hi = _startSamples.length - 1, found = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_us(_startSamples[mid]) <= timestampUs) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    _idx = _startSamples.isEmpty ? 0 : found;
  }

  @override
  int? get durationUs => _packets.isEmpty ? null : _us(_totalSamples);

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('ogg', 'demuxer closed');
  }
}

bool _matchOggS(ByteData d, int off) {
  if (off + 4 > d.lengthInBytes) return false;
  for (var i = 0; i < 4; i++) {
    if (d.getUint8(off + i) != _oggS[i]) return false;
  }
  return true;
}

/// Ogg muxer: Opus packets → a valid Ogg/Opus byte stream. One packet per page
/// (spec-legal), with a real Ogg CRC-32 so players accept the output.
class OggMuxer implements PlatformMuxer {
  OggMuxer._(this._track);

  final AudioTrackInfo _track;
  final List<Uint8List> _packets = [];
  bool _headerWritten = false;
  bool _closed = false;
  int _serial = 1;

  static OggMuxer open(MuxerConfig config) {
    if (config.tracks.isEmpty || config.tracks.first is! AudioTrackInfo) {
      throw const CodecInitException('ogg', 'need one AudioTrackInfo');
    }
    final track = config.tracks.first as AudioTrackInfo;
    if (track.codec != AudioCodec.opus) {
      throw CodecInitException('ogg', 'unsupported codec ${track.codec}');
    }
    return OggMuxer._(track);
  }

  @override
  Future<void> writeHeader() async {
    _checkOpen();
    _headerWritten = true;
  }

  @override
  Future<void> writePacket(EncodedPacket packet) async {
    _checkOpen();
    if (!_headerWritten) {
      throw const CodecRuntimeException('ogg', 'writePacket before writeHeader');
    }
    _packets.add(Uint8List.fromList(packet.data));
  }

  @override
  Future<void> finish() async => _checkOpen();

  @override
  Future<void> close() async => _closed = true;

  @override
  List<int>? getBytes() {
    final out = BytesBuilder();
    var seq = 0;

    // Page 0: OpusHead (BOS). Reuse the track's OpusHead if present.
    final head = _track.extraData?.bytes ?? _buildOpusHead();
    out.add(_page(head, headerType: 0x02, seq: seq++, granule: 0)); // BOS

    // Page 1: OpusTags.
    out.add(_page(_buildOpusTags(), headerType: 0x00, seq: seq++, granule: 0));

    // Audio packets, one per page. granulepos = total decoded 48 kHz samples so
    // far INCLUDING the pre-skip (RFC 7845 §4), read from each packet's own TOC
    // — a fixed 960 mistimed every stream that is not 20 ms per packet.
    var granule = 0;
    for (var i = 0; i < _packets.length; i++) {
      final d = opusPacketSamples48k(_packets[i]);
      granule += d > 0 ? d : 960;
      final last = i == _packets.length - 1;
      out.add(_page(
        _packets[i],
        headerType: last ? 0x04 : 0x00, // EOS on last
        seq: seq++,
        granule: granule,
      ));
    }
    return out.toBytes();
  }

  Uint8List _buildOpusHead() {
    final b = Uint8List(19);
    b.setRange(0, 8, _opusHeadMagic);
    b[8] = 1; // version
    b[9] = _track.channels;
    // pre-skip (10-11) = 0, output gain (16-17) = 0, mapping family (18) = 0
    final bd = ByteData.sublistView(b);
    bd.setUint32(12, _track.sampleRate, Endian.little);
    return b;
  }

  Uint8List _buildOpusTags() {
    const vendor = 'miniav_tools';
    final b = BytesBuilder();
    b.add(_opusTagsMagic);
    _u32(b, vendor.length);
    b.add(vendor.codeUnits);
    _u32(b, 0); // 0 user comments
    return b.toBytes();
  }

  /// Build one Ogg page carrying [payload] as a single packet, with a correct
  /// CRC. Assumes payload fits a page's 255-segment lacing budget (< 255*255 ≈
  /// 65 KB — always true for one Opus frame).
  Uint8List _page(
    Uint8List payload, {
    required int headerType,
    required int seq,
    required int granule,
  }) {
    final segs = <int>[];
    var rem = payload.length;
    do {
      final s = rem >= 255 ? 255 : rem;
      segs.add(s);
      rem -= s;
    } while (rem > 0 || (segs.isNotEmpty && segs.last == 255));
    // The trailing "< 255" segment (possibly 0) marks the packet boundary.

    final page = BytesBuilder();
    page.add(_oggS);
    page.addByte(0); // stream structure version
    page.addByte(headerType);
    _i64(page, granule);
    _u32(page, _serial);
    _u32(page, seq);
    _u32(page, 0); // CRC placeholder
    page.addByte(segs.length);
    for (final s in segs) {
      page.addByte(s);
    }
    page.add(payload);

    final bytes = page.toBytes();
    final crc = _oggCrc(bytes); // computed with CRC field = 0
    bytes[22] = crc & 0xFF;
    bytes[23] = (crc >> 8) & 0xFF;
    bytes[24] = (crc >> 16) & 0xFF;
    bytes[25] = (crc >> 24) & 0xFF;
    return bytes;
  }

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('ogg', 'muxer closed');
  }
}

/// Ogg CRC-32 (RFC 3533): poly 0x04C11DB7, init 0, no reflection, xorout 0.
int _oggCrc(Uint8List page) {
  var crc = 0;
  for (final b in page) {
    crc ^= b << 24;
    crc &= 0xFFFFFFFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x80000000) != 0) {
        crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
      } else {
        crc = (crc << 1) & 0xFFFFFFFF;
      }
    }
  }
  return crc & 0xFFFFFFFF;
}

void _u32(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}

void _i64(BytesBuilder b, int v) {
  _u32(b, v & 0xFFFFFFFF);
  _u32(b, (v >> 32) & 0xFFFFFFFF);
}
