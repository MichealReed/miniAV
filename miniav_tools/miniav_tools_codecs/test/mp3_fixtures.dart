/// Pure-Dart MP3 fixture synthesis for the framing tests.
///
/// The frames are structurally valid — real header fields, real derived frame
/// lengths, real ID3/Xing layout — with a zeroed-ish payload. Demuxing never
/// decodes, so framing can be tested without an encoder, and a synthesised file
/// has an EXACT expected frame count, duration and byte layout, which no real
/// capture can give you.
///
/// Deliberately an independent implementation of the length/rate tables: if the
/// fixtures imported the demuxer's own tables, a wrong table would cancel out
/// and the tests would pass on it.
library;

import 'dart:typed_data';

/// MPEG-1 Layer III bitrates (kbps) by index.
const List<int> mpeg1L3Bitrates = [
  0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0, //
];

/// MPEG-2 / 2.5 Layer III bitrates (kbps) by index.
const List<int> mpeg2L3Bitrates = [
  0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0, //
];

const List<int> mpeg1Rates = [44100, 48000, 32000];
const List<int> mpeg2Rates = [22050, 24000, 16000];
const List<int> mpeg25Rates = [11025, 12000, 8000];

/// One frame's header parameters. Defaults: MPEG-1, 128 kbps, 44100, stereo,
/// no padding, no CRC — i.e. `FF FB` frames of 417 bytes.
class Mp3FrameSpec {
  const Mp3FrameSpec({
    this.versionBits = 3, // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
    this.bitrateIndex = 9, // 128 kbps on MPEG-1
    this.rateIndex = 0,
    this.padding = false,
    this.channelMode = 0, // 0 = stereo, 3 = mono
    this.fill = 0,
  });

  final int versionBits;
  final int bitrateIndex;
  final int rateIndex;
  final bool padding;
  final int channelMode;
  final int fill;

  bool get isMpeg1 => versionBits == 3;
  bool get isMono => channelMode == 3;
  int get channels => isMono ? 1 : 2;
  int get samplesPerFrame => isMpeg1 ? 1152 : 576;

  int get bitrateBps =>
      (isMpeg1 ? mpeg1L3Bitrates : mpeg2L3Bitrates)[bitrateIndex] * 1000;

  int get sampleRate => switch (versionBits) {
        3 => mpeg1Rates[rateIndex],
        2 => mpeg2Rates[rateIndex],
        _ => mpeg25Rates[rateIndex],
      };

  int get frameLength =>
      (isMpeg1 ? 144 : 72) * bitrateBps ~/ sampleRate + (padding ? 1 : 0);

  /// Bytes between the header and the Xing/Info magic (side info).
  int get sideInfoSize =>
      isMpeg1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17);

  Mp3FrameSpec copyWith({int? bitrateIndex, bool? padding, int? fill}) =>
      Mp3FrameSpec(
        versionBits: versionBits,
        bitrateIndex: bitrateIndex ?? this.bitrateIndex,
        rateIndex: rateIndex,
        padding: padding ?? this.padding,
        channelMode: channelMode,
        fill: fill ?? this.fill,
      );
}

/// One structurally valid Layer III frame (header + payload).
Uint8List mp3Frame(Mp3FrameSpec spec) {
  final f = Uint8List(spec.frameLength);
  f[0] = 0xFF;
  // sync | version | layer III (01) | protection_absent (no CRC)
  f[1] = 0xE0 | (spec.versionBits << 3) | (0x01 << 1) | 0x01;
  f[2] = (spec.bitrateIndex << 4) |
      (spec.rateIndex << 2) |
      (spec.padding ? 0x02 : 0x00);
  f[3] = spec.channelMode << 6;
  // Payload kept below 0x80 so it can never look like a sync word — a fixture
  // must fail the demuxer for the reason the test intends, not by accident.
  for (var i = 4; i < f.length; i++) {
    f[i] = (spec.fill + i) & 0x7F;
  }
  return f;
}

/// A Xing/Info (or VBRI) metadata frame: a normal frame whose payload carries
/// the tag at the version/channel-dependent offset.
Uint8List mp3VbrFrame(
  Mp3FrameSpec spec, {
  String kind = 'Xing',
  int frameCount = 0,
  int byteCount = 0,
}) {
  final f = mp3Frame(spec);
  if (kind == 'VBRI') {
    // VBRI is always 32 bytes past the 4-byte header, regardless of side info.
    final at = 36;
    _magic(f, at, 'VBRI');
    _u32be(f, at + 10, byteCount);
    _u32be(f, at + 14, frameCount);
    return f;
  }
  final at = 4 + spec.sideInfoSize;
  _magic(f, at, kind);
  _u32be(f, at + 4, 0x03); // flags: frame count + byte count present
  _u32be(f, at + 8, frameCount);
  _u32be(f, at + 12, byteCount);
  return f;
}

/// An ID3v2.4 tag with a zero-filled body of [bodySize] bytes.
///
/// The size field is SYNCSAFE (7 bits per byte), so [bodySize] above 127
/// exercises the shift the naive "read a big-endian u32" bug gets wrong.
Uint8List id3v2Tag({int bodySize = 0, bool footer = false}) {
  final out = BytesBuilder();
  out.add('ID3'.codeUnits);
  out.addByte(4); // version 2.4
  out.addByte(0);
  out.addByte(footer ? 0x10 : 0x00); // bit 4 = a 10-byte footer follows
  out.addByte((bodySize >> 21) & 0x7F);
  out.addByte((bodySize >> 14) & 0x7F);
  out.addByte((bodySize >> 7) & 0x7F);
  out.addByte(bodySize & 0x7F);
  out.add(Uint8List(bodySize));
  if (footer) {
    out.add('3DI'.codeUnits);
    out.add(Uint8List(7));
  }
  return out.toBytes();
}

/// Frames built from [specs], concatenated — the whole audio part of a file.
Uint8List mp3Stream(List<Mp3FrameSpec> specs) =>
    concatBytes([for (final s in specs) mp3Frame(s)]);

/// [count] identical frames, each with a distinct payload fill.
List<Mp3FrameSpec> repeatSpec(Mp3FrameSpec spec, int count) =>
    [for (var i = 0; i < count; i++) spec.copyWith(fill: i * 5 + 1)];

Uint8List concatBytes(List<List<int>> parts) {
  final out = BytesBuilder();
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

/// Bytes that are not audio and contain no sync word.
Uint8List garbage(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 13 + 3) & 0x7F]);

/// A 7-byte ADTS (AAC) header — the format mp3 is most often confused with.
Uint8List adtsFrame({int payloadLength = 16}) {
  final len = 7 + payloadLength;
  final f = Uint8List(len);
  f[0] = 0xFF;
  f[1] = 0xF1; // MPEG-4, layer 00, no CRC
  f[2] = (1 << 6) | (4 << 2); // AAC-LC, sample-rate index 4 (44100)
  f[3] = (2 << 6) | ((len >> 11) & 0x03); // 2 channels
  f[4] = (len >> 3) & 0xFF;
  f[5] = ((len & 0x07) << 5) | 0x1F;
  f[6] = 0xFC;
  for (var i = 7; i < len; i++) {
    f[i] = (i * 3) & 0x7F;
  }
  return f;
}

void _magic(Uint8List d, int off, String s) {
  for (var i = 0; i < s.length; i++) {
    d[off + i] = s.codeUnitAt(i);
  }
}

void _u32be(Uint8List d, int off, int v) {
  d[off] = (v >> 24) & 0xFF;
  d[off + 1] = (v >> 16) & 0xFF;
  d[off + 2] = (v >> 8) & 0xFF;
  d[off + 3] = v & 0xFF;
}
