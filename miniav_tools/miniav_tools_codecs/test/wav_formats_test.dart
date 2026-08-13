// WAVE_FORMAT_EXTENSIBLE / 24-bit / 8-bit WAV decoding, and the RIFF sniffer's
// form type. Every expectation is against hand-computed sample values, not
// against a round-trip through the same code.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

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

/// KSDATAFORMAT_SUBTYPE_{PCM,IEEE_FLOAT}: the tag in Data1, then the fixed
/// `0000-0010-8000-00aa00389b71` tail.
List<int> _subFormatGuid(int tag) => [
      tag & 0xFF, (tag >> 8) & 0xFF, 0x00, 0x00, //
      0x00, 0x00, 0x10, 0x00,
      0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71,
    ];

/// A RIFF/WAVE file. [extensible] wraps the format in a 40-byte
/// WAVE_FORMAT_EXTENSIBLE `fmt ` chunk with the given valid-bit count.
Uint8List _wav({
  required int formatTag,
  required int bits,
  required int channels,
  required int sampleRate,
  required List<int> data,
  bool extensible = false,
  int? validBits,
}) {
  final fmt = BytesBuilder();
  final blockAlign = channels * (bits ~/ 8);
  _u16(fmt, extensible ? 0xFFFE : formatTag);
  _u16(fmt, channels);
  _u32(fmt, sampleRate);
  _u32(fmt, sampleRate * blockAlign);
  _u16(fmt, blockAlign);
  _u16(fmt, bits);
  if (extensible) {
    _u16(fmt, 22); // cbSize
    _u16(fmt, validBits ?? bits);
    _u32(fmt, 0); // channel mask
    fmt.add(_subFormatGuid(formatTag));
  }
  final fmtBytes = fmt.toBytes();

  final out = BytesBuilder();
  out.add('RIFF'.codeUnits);
  _u32(out, 4 + 8 + fmtBytes.length + 8 + data.length);
  out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits);
  _u32(out, fmtBytes.length);
  out.add(fmtBytes);
  out.add('data'.codeUnits);
  _u32(out, data.length);
  out.add(data);
  return out.toBytes();
}

/// Every packet the demuxer produces, concatenated.
Future<Uint8List> _drain(PlatformDemuxer d) async {
  final b = BytesBuilder();
  for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
    b.add(p.data);
  }
  return b.toBytes();
}

void main() {
  setUpAll(registerFirstPartyBackends);

  test('EXTENSIBLE 16-bit PCM decodes like the plain fmt-1 form', () async {
    // Four s16 frames, mono: -32768, -1, 0, 32767.
    final data = <int>[0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F];
    final d = WavDemuxer.open(_wav(
      formatTag: 1,
      bits: 16,
      channels: 1,
      sampleRate: 44100,
      data: data,
      extensible: true,
    ));
    final track = d.tracks.single as AudioTrackInfo;
    expect(track.codec, AudioCodec.pcmS16le);
    expect(track.sampleRate, 44100);
    expect(track.channels, 1);

    final pcm = await _drain(d);
    final s16 = Int16List.sublistView(pcm);
    expect(s16, [-32768, -1, 0, 32767]);
    expect(d.durationUs, 4 * 1000000 ~/ 44100);
  });

  test('EXTENSIBLE 32-bit float decodes to f32 packets', () async {
    final src = Float32List.fromList([-1.0, -0.25, 0.0, 0.5]);
    final d = WavDemuxer.open(_wav(
      formatTag: 3,
      bits: 32,
      channels: 2,
      sampleRate: 48000,
      data: Uint8List.view(src.buffer),
      extensible: true,
    ));
    expect((d.tracks.single as AudioTrackInfo).codec, AudioCodec.pcmF32le);
    final pcm = await _drain(d);
    expect(Float32List.sublistView(pcm), [-1.0, -0.25, 0.0, 0.5]);
  });

  test('24-bit packed PCM converts to exact f32', () async {
    // Packed little-endian 24-bit: min, -1, 0, +1, max.
    final data = <int>[
      0x00, 0x00, 0x80, // -8388608
      0xFF, 0xFF, 0xFF, // -1
      0x00, 0x00, 0x00, // 0
      0x01, 0x00, 0x00, // +1
      0xFF, 0xFF, 0x7F, // 8388607
    ];
    final d = WavDemuxer.open(_wav(
      formatTag: 1,
      bits: 24,
      channels: 1,
      sampleRate: 48000,
      data: data,
      extensible: true,
    ));
    expect((d.tracks.single as AudioTrackInfo).codec, AudioCodec.pcmF32le);
    final got = Float32List.sublistView(await _drain(d));
    // v / 2^23 — exact in float32, so these compare with ==.
    expect(got, [
      -1.0,
      -1.0 / 8388608.0,
      0.0,
      1.0 / 8388608.0,
      8388607.0 / 8388608.0,
    ]);
    expect(d.durationUs, 5 * 1000000 ~/ 48000,
        reason: 'duration is priced in SOURCE frames (3 bytes each)');
  });

  test('8-bit unsigned PCM converts to exact s16', () async {
    final data = <int>[0, 1, 127, 128, 129, 255];
    final d = WavDemuxer.open(_wav(
      formatTag: 1,
      bits: 8,
      channels: 1,
      sampleRate: 8000,
      data: data,
      extensible: false,
    ));
    expect((d.tracks.single as AudioTrackInfo).codec, AudioCodec.pcmS16le);
    final got = Int16List.sublistView(await _drain(d));
    // (b - 128) << 8
    expect(got, [-32768, -32512, -256, 0, 256, 32512]);
    expect(d.durationUs, 6 * 1000000 ~/ 8000);
  });

  test('a non-PCM EXTENSIBLE SubFormat is refused, not misread', () {
    // KSDATAFORMAT_SUBTYPE_ALAW ({00000006-...}) has the PCM tail but tag 6.
    expect(
      () => WavDemuxer.open(_wav(
        formatTag: 6,
        bits: 16,
        channels: 1,
        sampleRate: 8000,
        data: List<int>.filled(8, 0),
        extensible: true,
      )),
      throwsA(isA<CodecInitException>()),
    );
  });

  test('valid-bits narrower than the container is refused', () {
    expect(
      () => WavDemuxer.open(_wav(
        formatTag: 1,
        bits: 24,
        channels: 1,
        sampleRate: 48000,
        data: List<int>.filled(9, 0),
        extensible: true,
        validBits: 20,
      )),
      throwsA(isA<CodecInitException>()),
    );
  });

  test('an AVI-shaped RIFF is not sniffed as wav', () async {
    // "RIFF" + size + "AVI " + a plausible LIST/hdrl.
    final avi = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add([0x00, 0x10, 0x00, 0x00])
      ..add('AVI '.codeUnits)
      ..add('LIST'.codeUnits)
      ..add([0x40, 0x00, 0x00, 0x00])
      ..add('hdrl'.codeUnits)
      ..add(List<int>.filled(64, 0));
    final bytes = avi.toBytes();

    // The SNIFF is what matters. Both the right and the wrong guess end in a
    // null demuxer here (the WAV parser refuses AVI), so asserting on
    // createDemuxer alone cannot tell them apart.
    expect(ContainerFramingBackend.sniff(bytes), isNot(Container.wav));

    final backend = ContainerFramingBackend();
    final demuxer = await backend.createDemuxer(
      DemuxerConfig(input: DemuxerInput.bytes(bytes)),
    );
    expect(demuxer, isNull,
        reason: 'RIFF form type "AVI " must fall through, not open as WAVE');
  });

  test('a real WAVE still sniffs as wav through the backend', () async {
    final bytes = _wav(
      formatTag: 1,
      bits: 16,
      channels: 1,
      sampleRate: 8000,
      data: List<int>.filled(16, 0),
    );
    expect(ContainerFramingBackend.sniff(bytes), Container.wav);
    final backend = ContainerFramingBackend();
    final demuxer = await backend.createDemuxer(
      DemuxerConfig(input: DemuxerInput.bytes(bytes)),
    );
    expect(demuxer, isA<WavDemuxer>());
    await demuxer!.close();
  });
}
