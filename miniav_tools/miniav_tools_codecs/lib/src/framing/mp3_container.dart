/// MP3 (MPEG-1 / MPEG-2 / MPEG-2.5 Audio **Layer III**) demuxer — pure Dart,
/// web-safe, FFmpeg-free.
///
/// An `.mp3` file has no container: it is a bare run of self-describing 4-byte
/// frame headers, optionally wrapped in ID3 tags. [Mp3Demuxer] indexes EVERY
/// frame at open (one linear pass — ~7000 entries for a 3-minute track), which
/// buys three things a streaming parser cannot have: a duration that is
/// COUNTED rather than estimated from a bitrate (the only way to be right about
/// a VBR file, with or without a Xing header), an exact seek, and a PTS that
/// cannot drift because it is derived from the frame's own cumulative sample
/// position instead of accumulated per-frame rounding.
///
/// Layer III only. [AudioCodec.mp3] means Layer III to both consumers of these
/// packets (dr_mp3 natively, and the WebCodecs `'mp3'` codec string), so Layer
/// I/II streams are rejected at open rather than handed to a decoder that would
/// mis-frame them.
///
/// Packets are WHOLE frames, 4-byte header included: dr_mp3 and WebCodecs both
/// parse that header themselves and cannot use a stripped payload.
/// Concatenating the emitted packets reproduces the audio bitstream exactly,
/// minus tags and the Xing/VBRI metadata frame.
///
/// Deliberately NOT implemented: LAME gapless playback (the encoder-delay /
/// end-padding counts in the LAME extension of the Xing frame). Dropping those
/// samples is a DECODER-side concern — the demuxer would have to carry the trim
/// counts downstream and no consumer reads them today. Deferred.
library;

import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

// ---------------------------------------------------------------------------
// Shared sync discriminators (also used by the ADTS parser + the sniffer).
// ---------------------------------------------------------------------------

/// True when [b0]/[b1] open an ADTS (AAC) frame header.
///
/// The discriminator is the 12-bit sync word PLUS `layer == 00`. ADTS reuses
/// the MPEG audio header shape, and the layer field is the ONLY thing that
/// separates it from MPEG Audio Layer I/II/III. Testing `(b1 & 0xF0) == 0xF0`
/// alone also accepts every bare mp3 frame (`FF FB`, `FF FA`, `FF F3`, `FF F2`
/// — layer bits `01`), which is how mp3 bytes could open as an AAC track that
/// desynced on the first frame length it read out of mp3 audio data.
bool isAdtsSync(int b0, int b1) => b0 == 0xFF && (b1 & 0xF6) == 0xF0;

/// True when [b0]/[b1] open an MPEG Audio **Layer III** frame header.
///
/// 11-bit sync word, a version that is not the reserved `01`, and layer `01`.
/// Symmetric with [isAdtsSync]: no byte pair can satisfy both, because ADTS
/// requires layer `00` and Layer III requires layer `01`.
bool isMp3Sync(int b0, int b1) =>
    b0 == 0xFF &&
    (b1 & 0xE0) == 0xE0 && // sync
    (b1 & 0x18) != 0x08 && // version != reserved
    (b1 & 0x06) == 0x02; // layer III

/// True when [b0]/[b1]/[b2] are the `ID3` magic of an ID3v2 tag.
///
/// Worth sniffing on its own: an ID3v2 tag can be megabytes of album art, so
/// the first frame sync may be nowhere near the start of the file.
bool isId3Magic(int b0, int b1, int b2) =>
    b0 == 0x49 && b1 == 0x44 && b2 == 0x33;

// ---------------------------------------------------------------------------
// Header parsing
// ---------------------------------------------------------------------------

/// MPEG-1 Layer III bitrates in kbps by index. 0 = free-format, 15 = invalid;
/// both are stored as 0 and rejected by [_parseHeader].
const List<int> _bitratesV1L3 = [
  0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0, //
];

/// MPEG-2 / MPEG-2.5 Layer III bitrates in kbps by index.
const List<int> _bitratesV2L3 = [
  0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0, //
];

const List<int> _ratesV1 = [44100, 48000, 32000];
const List<int> _ratesV2 = [22050, 24000, 16000];
const List<int> _ratesV25 = [11025, 12000, 8000];

/// How far past a bad header the walker will hunt for the next real frame.
const int _resyncWindow = 1 << 17; // 128 KiB

class _Mp3Header {
  const _Mp3Header(
    this.versionBits,
    this.frameLength,
    this.sampleRate,
    this.channels,
    this.samplesPerFrame,
    this.hasCrc,
  );

  /// 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5 (1 is reserved and never parsed).
  final int versionBits;
  final int frameLength; // whole frame, header included
  final int sampleRate;
  final int channels;
  final int samplesPerFrame; // 1152 (MPEG-1) or 576 (MPEG-2/2.5)
  final bool hasCrc; // a 16-bit CRC sits between header and side info

  bool get isMpeg1 => versionBits == 3;

  /// Same stream format? Bitrate and padding change per frame in a VBR file and
  /// the channel mode may legally switch mid-stream; version and sample rate
  /// may not. Requiring those to match is what makes a resync trustworthy — a
  /// chance 0xFFE hit inside audio data almost never reproduces the stream's
  /// own version + sample-rate pair as well as landing a valid frame length.
  bool sameFormatAs(_Mp3Header other) =>
      versionBits == other.versionBits && sampleRate == other.sampleRate;
}

/// Parse a Layer III frame header at [off], or `null` if it is not one.
///
/// Free-format (bitrate index 0) is rejected here: its frame length is not
/// derivable from the header, so indexing it would need a whole second parsing
/// strategy. [Mp3Demuxer.open] reports it as its own error rather than a
/// generic "no sync".
_Mp3Header? _parseHeader(Uint8List d, int off) {
  if (off + 4 > d.length) return null;
  final b1 = d[off + 1];
  if (!isMp3Sync(d[off], b1)) return null;

  final b2 = d[off + 2];
  final versionBits = (b1 >> 3) & 0x03;
  final bitrateIndex = (b2 >> 4) & 0x0F;
  final rateIndex = (b2 >> 2) & 0x03;
  if (rateIndex == 3) return null; // reserved sample rate

  final mpeg1 = versionBits == 3;
  final kbps = (mpeg1 ? _bitratesV1L3 : _bitratesV2L3)[bitrateIndex];
  if (kbps == 0) return null; // free-format or invalid

  final sampleRate = switch (versionBits) {
    3 => _ratesV1[rateIndex],
    2 => _ratesV2[rateIndex],
    _ => _ratesV25[rateIndex],
  };
  final bitrateBps = kbps * 1000;
  final padding = (b2 >> 1) & 0x01;
  // MPEG-1 Layer III carries 1152 samples per frame, MPEG-2/2.5 carries 576 —
  // hence the 144 vs 72 byte-length coefficient (samples / 8 bits).
  final frameLength = mpeg1
      ? 144 * bitrateBps ~/ sampleRate + padding
      : 72 * bitrateBps ~/ sampleRate + padding;
  if (frameLength <= 4) return null;

  final channelMode = (d[off + 3] >> 6) & 0x03;
  return _Mp3Header(
    versionBits,
    frameLength,
    sampleRate,
    channelMode == 3 ? 1 : 2, // 3 = single channel
    mpeg1 ? 1152 : 576,
    (b1 & 0x01) == 0,
  );
}

/// True if a Layer III sync at [off] carries a free-format bitrate index.
bool _isFreeFormatSync(Uint8List d, int off) {
  if (off + 4 > d.length) return false;
  if (!isMp3Sync(d[off], d[off + 1])) return false;
  return ((d[off + 2] >> 4) & 0x0F) == 0 && ((d[off + 2] >> 2) & 0x03) != 3;
}

/// Total length of the ID3v2 tag at [off] (header + body + optional footer), or
/// 0 when there is no tag there.
///
/// Public because a container sniffer needs it: an ID3v2 tag can be megabytes
/// of album art, and it is legal in front of an ADTS stream too, so `starts
/// with 'ID3'` is not by itself an answer — the sniffer has to step over the
/// tag and let the bytes behind it decide.
int id3TagLength(List<int> b, [int off = 0]) {
  if (off < 0 || off + 10 > b.length) return 0;
  if (!isId3Magic(b[off], b[off + 1], b[off + 2])) return 0;
  // Version bytes 0xFF are invalid; the 4 size bytes are SYNCSAFE (7 bits
  // each, high bit always clear) so a tag body can never contain a sync word.
  if (b[off + 3] == 0xFF || b[off + 4] == 0xFF) return 0;
  var size = 0;
  for (var i = 6; i < 10; i++) {
    if (b[off + i] & 0x80 != 0) return 0; // not syncsafe → not a real tag
    size = (size << 7) | b[off + i];
  }
  final footer = (b[off + 5] & 0x10) != 0 ? 10 : 0; // ID3v2.4 footer
  return 10 + size + footer;
}

/// Length of the tag starting at [off], or 0 if there is none.
///
/// Tags are not only a file prefix: writers append an ID3v2 block after the
/// audio, and ID3v1 always sits in the last 128 bytes. Recognising them at a
/// frame boundary keeps them out of the resync path, where they would be
/// charged as stream corruption.
int _tagLengthAt(Uint8List d, int off) {
  final id3 = id3TagLength(d, off);
  if (id3 > 0) return id3;
  // ID3v1 — only ever the final 128 bytes, so require exactly that placement
  // rather than skipping any 'TAG' that happens to fall on a frame boundary.
  if (off + 128 == d.length &&
      d[off] == 0x54 &&
      d[off + 1] == 0x41 &&
      d[off + 2] == 0x47) {
    return 128;
  }
  return 0;
}

/// Total PCM sample-frames the Layer III frames in [bytes] decode to.
///
/// Exact (it sums each frame header's own sample count) and one linear scan.
/// The software decoder uses it to trim a batch: whole-buffer decoders drop
/// their first frame while they sync, so a batch is decoded with some preceding
/// context and then cut back to exactly the frames the batch itself carries.
int mp3PcmFrameCount(Uint8List bytes) {
  var total = 0;
  var pos = 0;
  while (pos + 4 <= bytes.length) {
    final tag = _tagLengthAt(bytes, pos);
    if (tag > 0) {
      pos += tag;
      continue;
    }
    final h = _parseHeader(bytes, pos);
    if (h == null) {
      pos++; // not a frame boundary — step and keep looking
      continue;
    }
    if (pos + h.frameLength > bytes.length) break; // partial tail frame
    total += h.samplesPerFrame;
    pos += h.frameLength;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Xing / Info / VBRI metadata frame
// ---------------------------------------------------------------------------

/// The VBR metadata frame that most encoders put first: a normal, decodable
/// Layer III frame whose payload is a `Xing` / `Info` / `VBRI` blob instead of
/// audio. It is not audio, so it is skipped rather than emitted.
class Mp3VbrHeader {
  const Mp3VbrHeader({
    required this.kind,
    required this.frameCount,
    required this.byteCount,
  });

  /// `'Xing'` (VBR), `'Info'` (CBR, same layout) or `'VBRI'` (Fraunhofer).
  final String kind;

  /// Audio frames the tag claims, EXCLUDING itself; 0 when absent.
  final int frameCount;

  /// Audio bytes the tag claims; 0 when absent.
  final int byteCount;
}

int _u32be(Uint8List d, int off) =>
    (d[off] << 24) | (d[off + 1] << 16) | (d[off + 2] << 8) | d[off + 3];

bool _magicAt(Uint8List d, int off, String magic) {
  if (off + magic.length > d.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (d[off + i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}

/// Detect a Xing/Info/VBRI blob inside the frame at [frameOff].
Mp3VbrHeader? _parseVbrHeader(Uint8List d, int frameOff, _Mp3Header h) {
  // Xing/Info sits immediately after the side info, whose size depends on
  // version and channel mode; a CRC, when present, pushes it 2 bytes further.
  final sideInfo = h.isMpeg1
      ? (h.channels == 1 ? 17 : 32)
      : (h.channels == 1 ? 9 : 17);
  final base = frameOff + 4 + sideInfo + (h.hasCrc ? 2 : 0);
  for (final kind in const ['Xing', 'Info']) {
    if (!_magicAt(d, base, kind)) continue;
    if (base + 8 > d.length) {
      return Mp3VbrHeader(kind: kind, frameCount: 0, byteCount: 0);
    }
    final flags = _u32be(d, base + 4);
    var p = base + 8;
    var frames = 0, bytes = 0;
    if (flags & 0x01 != 0 && p + 4 <= d.length) {
      frames = _u32be(d, p);
      p += 4;
    }
    if (flags & 0x02 != 0 && p + 4 <= d.length) {
      bytes = _u32be(d, p);
    }
    return Mp3VbrHeader(kind: kind, frameCount: frames, byteCount: bytes);
  }
  // VBRI is always 32 bytes past the header, regardless of side-info size.
  final vbri = frameOff + 36;
  if (_magicAt(d, vbri, 'VBRI') && vbri + 18 <= d.length) {
    return Mp3VbrHeader(
      kind: 'VBRI',
      frameCount: _u32be(d, vbri + 14),
      byteCount: _u32be(d, vbri + 10),
    );
  }
  return null;
}

// ---------------------------------------------------------------------------
// Demuxer
// ---------------------------------------------------------------------------

/// MP3 demuxer: raw `.mp3` bytes → one [EncodedPacket] per Layer III frame.
class Mp3Demuxer implements PlatformDemuxer {
  Mp3Demuxer._(
    this.tracks,
    this._bytes,
    this._offsets,
    this._lengths,
    this._cumSamples,
    this._sampleRate,
    this._samplesPerFrame,
    this.firstFrameOffset,
    this.resyncCount,
    this.vbrHeader,
  );

  @override
  final List<TrackInfo> tracks;

  final Uint8List _bytes;

  /// Frame index: byte offset, byte length, and samples that precede each
  /// frame. A >4 GiB mp3 cannot be held in memory as a [Uint8List] anyway, and
  /// the sample counter covers ~27 hours at 44.1 kHz, so 32-bit entries are
  /// sufficient and keep a long album's index in tens of KB.
  final Uint32List _offsets;
  final Uint32List _lengths;
  final Uint32List _cumSamples;

  final int _sampleRate;
  final int _samplesPerFrame;

  /// Byte offset of the first frame (past any ID3v2 tag / leading padding).
  final int firstFrameOffset;

  /// How many times the walker had to hunt for a new sync. Non-zero means the
  /// file contains garbage between frames; the audio around it still plays.
  final int resyncCount;

  /// The Xing/Info/VBRI frame, if the stream starts with one. It is excluded
  /// from [readPacket] output — it is metadata, not audio.
  final Mp3VbrHeader? vbrHeader;

  int _idx = 0;
  bool _closed = false;

  /// Audio frames in the index (the Xing/VBRI frame is not one of them).
  int get frameCount => _offsets.length;

  /// Open an MP3 demuxer, or throw [CodecInitException] on input that is not a
  /// Layer III stream.
  static Mp3Demuxer open(Uint8List bytes) {
    // ID3v2 tags may repeat and may be followed by zero padding; the frame
    // search below walks past whatever the tag skip does not cover.
    var scan = 0;
    for (var skip = _tagLengthAt(bytes, scan);
        skip > 0 && scan + skip <= bytes.length;
        skip = _tagLengthAt(bytes, scan)) {
      scan += skip;
    }

    final firstOff = _findFirstFrame(bytes, scan);
    if (firstOff < 0) {
      // Distinguish "not mp3 at all" from "mp3 we decline to index", so the
      // negotiator's fall-through to another backend is an informed one.
      for (var i = scan; i + 4 <= bytes.length; i++) {
        if (_isFreeFormatSync(bytes, i)) {
          throw const CodecInitException(
            'mp3',
            'free-format MP3 (bitrate index 0) is not supported — its frame '
                'length is not derivable from the header',
          );
        }
      }
      throw const CodecInitException('mp3', 'no MPEG Layer III frame sync');
    }
    final first = _parseHeader(bytes, firstOff)!;

    // A leading Xing/Info/VBRI frame is metadata: index the audio after it.
    final vbr = _parseVbrHeader(bytes, firstOff, first);
    final walkStart = vbr == null ? firstOff : firstOff + first.frameLength;

    final offsets = <int>[];
    final lengths = <int>[];
    final cum = <int>[];
    var samples = 0;
    var resyncs = 0;
    var pos = walkStart;
    while (pos + 4 <= bytes.length) {
      final tag = _tagLengthAt(bytes, pos);
      if (tag > 0) {
        pos += tag;
        continue;
      }
      final h = _parseHeader(bytes, pos);
      if (h != null && h.sameFormatAs(first)) {
        // A truncated final frame is dropped: neither dr_mp3 nor WebCodecs can
        // do anything with a partial frame, and emitting one would make the
        // packet stream un-concatenable.
        if (pos + h.frameLength > bytes.length) break;
        offsets.add(pos);
        lengths.add(h.frameLength);
        cum.add(samples);
        samples += h.samplesPerFrame;
        pos += h.frameLength;
        continue;
      }
      final next = _resync(bytes, pos + 1, first);
      if (next < 0) break; // nothing recoverable left — stop, keep what we have
      resyncs++;
      pos = next;
    }

    // Refuse to hand back a track with nothing in it. A demuxer that opens
    // successfully and then reports EOF immediately is the worst outcome for
    // the caller: the negotiator has already committed to this backend, so it
    // never tries the next one, and the app plays silence instead of falling
    // through. Throwing keeps that fall-through available.
    if (offsets.isEmpty) {
      throw const CodecInitException('mp3', 'no MPEG Layer III audio frames');
    }

    return Mp3Demuxer._(
      [
        AudioTrackInfo(
          codec: AudioCodec.mp3,
          sampleRate: first.sampleRate,
          channels: first.channels,
          // No out-of-band config exists for mp3: every frame re-states the
          // format in its own header.
          extraData: null,
        ),
      ],
      bytes,
      Uint32List.fromList(offsets),
      Uint32List.fromList(lengths),
      Uint32List.fromList(cum),
      first.sampleRate,
      first.samplesPerFrame,
      firstOff,
      resyncs,
      vbr,
    );
  }

  /// First offset at/after [from] holding a frame that is CONFIRMED by a second
  /// frame at `offset + frameLength` (or by ending the data).
  ///
  /// The second-frame check is the whole point: `FF Ex` occurs constantly in
  /// compressed audio, ID3 art and random bytes, and a parser that trusts one
  /// sync opens garbage as a track and then reports EOF a packet or two later.
  static int _findFirstFrame(Uint8List d, int from) {
    for (var pos = from; pos + 4 <= d.length; pos++) {
      final tag = _tagLengthAt(d, pos);
      if (tag > 0) {
        pos += tag - 1; // -1: the loop's own increment covers the last byte
        continue;
      }
      if (_confirmed(d, pos, null)) return pos;
    }
    return -1;
  }

  /// Bounded forward hunt for the next confirmed frame of the same format.
  static int _resync(Uint8List d, int from, _Mp3Header ref) {
    final end = from + _resyncWindow;
    final limit = end < d.length ? end : d.length;
    for (var pos = from; pos + 4 <= limit; pos++) {
      if (_tagLengthAt(d, pos) > 0) return pos; // let the walker skip the tag
      if (_confirmed(d, pos, ref)) return pos;
    }
    return -1;
  }

  /// A frame at [pos] plus a matching frame right after it (or clean EOF).
  static bool _confirmed(Uint8List d, int pos, _Mp3Header? ref) {
    final h = _parseHeader(d, pos);
    if (h == null) return false;
    if (ref != null && !h.sameFormatAs(ref)) return false;
    final next = pos + h.frameLength;
    if (next > d.length) return false; // frame does not even fit
    if (next + 4 > d.length) return true; // last frame in the data
    final h2 = _parseHeader(d, next);
    return h2 != null && h2.sameFormatAs(h);
  }

  @override
  Future<EncodedPacket?> readPacket() async {
    _checkOpen();
    if (_idx >= _offsets.length) return null;
    final off = _offsets[_idx];
    final data = _bytes.sublist(off, off + _lengths[_idx]);
    // PTS from the frame's own cumulative sample position, so a long VBR file
    // cannot accumulate per-frame rounding error.
    final ptsUs = _cumSamples[_idx] * 1000000 ~/ _sampleRate;
    _idx++;
    return EncodedPacket(
      data: data,
      ptsUs: ptsUs,
      dtsUs: ptsUs,
      durationUs: _samplesPerFrame * 1000000 ~/ _sampleRate,
      // Every Layer III frame is a decoder entry point. It is not a perfect
      // one: the bit reservoir lets a frame's main data spill back up to 511
      // bytes into earlier frames, so the first frame or two after a seek can
      // be slightly wrong before the decoder converges. Marking frames as
      // non-key instead would be worse — consumers would have no sync point at
      // all and could not seek.
      isKeyframe: true,
    );
  }

  @override
  Future<void> seek(int timestampUs) async {
    _checkOpen();
    final target = timestampUs <= 0 ? 0 : timestampUs;
    // Last frame that STARTS at or before the target, compared in the same
    // microsecond domain [readPacket] reports. Converting the target back into
    // samples instead looks equivalent and is not: the emitted PTS is a
    // truncated microsecond value, so `pts * rate / 1e6` always lands just
    // under the frame's own sample position and `seek(pts(n))` returns frame
    // n-1. Past the end this clamps to the final frame, like the other framing
    // demuxers.
    var lo = 0, hi = _cumSamples.length - 1, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_cumSamples[mid] * 1000000 ~/ _sampleRate <= target) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    _idx = best;
  }

  /// Counted, not estimated: the last frame's start plus its own length. [open]
  /// guarantees a non-empty index, so there is no unknown case to report.
  @override
  int? get durationUs {
    final total = _cumSamples[_cumSamples.length - 1] + _samplesPerFrame;
    return total * 1000000 ~/ _sampleRate;
  }

  @override
  bool get isSeekable => true;

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw const CodecRuntimeException('mp3', 'demuxer closed');
  }
}
