// ADTS framing against the files that actually exist in the wild: ID3-tagged
// and slightly corrupt.
//
// Three shipped bugs, all silent:
//   * open() parsed at byte 0 while the sniffer (container_backend._sniff)
//     steps over ID3v2 first, so a tagged `.aac` was ACCEPTED by the sniffer and
//     REJECTED by the parser. On the VM that wasted a fall-through to FFmpeg; on
//     web there is no second demuxer, so it was a hard failure.
//   * readPacket() returned null — a CLEAN eof — on the first header it could
//     not parse, so an ID3v1 trailer or one corrupt frame silently truncated the
//     rest of the file with no error anywhere.
//   * channel_configuration was read as if it were a channel COUNT. They differ
//     at 7 (= 7.1, EIGHT channels).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

const _frames = 12;

/// [n] ADTS frames of distinct, position-identifiable payload.
Future<Uint8List> _adts(int n, {int channels = 2, int sampleRate = 44100}) async {
  final mux = AdtsMuxer.open(MuxerConfig(
    container: Container.adts,
    output: MuxerOutput.bytes(),
    tracks: [
      AudioTrackInfo(
        codec: AudioCodec.aac,
        sampleRate: sampleRate,
        channels: channels,
      ),
    ],
  ));
  await mux.writeHeader();
  for (var i = 0; i < n; i++) {
    await mux.writePacket(EncodedPacket(
      data: Uint8List.fromList(List.generate(40, (k) => (i * 7 + k) & 0x7F)),
      ptsUs: 0,
      dtsUs: 0,
    ));
  }
  final bytes = Uint8List.fromList(mux.getBytes()!);
  await mux.close();
  return bytes;
}

/// A minimal ID3v2.3 tag with [bodyLen] bytes of (zero) body.
Uint8List _id3v2(int bodyLen) {
  final b = BytesBuilder();
  b.add([0x49, 0x44, 0x33, 3, 0]); // "ID3", v2.3.0
  b.addByte(0); // flags: no footer
  // Syncsafe size: 7 bits per byte.
  b.add([
    (bodyLen >> 21) & 0x7F,
    (bodyLen >> 14) & 0x7F,
    (bodyLen >> 7) & 0x7F,
    bodyLen & 0x7F,
  ]);
  b.add(Uint8List(bodyLen));
  return b.toBytes();
}

/// The 128-byte ID3v1 trailer writers append after the audio.
Uint8List _id3v1() {
  final b = Uint8List(128);
  b[0] = 0x54; // 'T'
  b[1] = 0x41; // 'A'
  b[2] = 0x47; // 'G'
  return b;
}

Uint8List _cat(List<Uint8List> parts) {
  final b = BytesBuilder();
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

Future<List<EncodedPacket>> _drain(PlatformDemuxer dm) async {
  final out = <EncodedPacket>[];
  for (var p = await dm.readPacket(); p != null; p = await dm.readPacket()) {
    out.add(p);
  }
  return out;
}

void main() {
  test('an ID3v2-prefixed, ID3v1-trailed .aac demuxes EVERY frame', () async {
    final plain = await _adts(_frames);
    final tagged = _cat([_id3v2(600), plain, _id3v1()]);

    final dm = AdtsDemuxer.open(tagged);
    final t = dm.tracks.single as AudioTrackInfo;
    expect(t.codec, AudioCodec.aac);
    expect(t.sampleRate, 44100);
    expect(t.channels, 2);

    final got = await _drain(dm);
    await dm.close();
    expect(got, hasLength(_frames),
        reason: 'the tag prefix and the ID3v1 trailer are metadata; neither '
            'may cost a frame');

    // Byte-identical to the untagged file, frame for frame.
    final ref = await _drain(AdtsDemuxer.open(plain));
    expect(got.length, ref.length);
    for (var i = 0; i < got.length; i++) {
      expect(got[i].data, ref[i].data, reason: 'frame $i differs');
      expect(got[i].ptsUs, ref[i].ptsUs);
    }
  });

  test('a trailing ID3v2 block is a clean end, not a frame', () async {
    final bytes = _cat([await _adts(_frames), _id3v2(300)]);
    final got = await _drain(AdtsDemuxer.open(bytes));
    expect(got, hasLength(_frames));
  });

  test('sniff and open agree on a tagged .aac (the web hard-failure)',
      () async {
    final tagged = _cat([_id3v2(600), await _adts(_frames)]);
    // The sniffer's verdict: no container hint, so it must decide from bytes.
    final dm = await ContainerFramingBackend().createDemuxer(
      DemuxerConfig(input: DemuxerInput.bytes(tagged)),
    );
    expect(dm, isNotNull,
        reason: 'the sniffer accepted this file; the parser must too — on web '
            'there is no FFmpeg to fall through to');
    expect((dm!.tracks.single as AudioTrackInfo).codec, AudioCodec.aac);
    expect(await _drain(dm), hasLength(_frames));
    await dm.close();
  });

  test('mid-stream garbage resyncs instead of truncating the file', () async {
    final plain = await _adts(_frames);
    // Find frame 6's start so the damage lands on a frame boundary we know.
    final ref = AdtsDemuxer.open(plain);
    final refPkts = await _drain(ref);
    await ref.close();

    // 24 bytes of junk that is not an ADTS sync, spliced over the middle. The
    // frames after it are intact and must still come out.
    final damaged = Uint8List.fromList(plain);
    final mid = plain.length ~/ 2;
    for (var i = 0; i < 24; i++) {
      damaged[mid + i] = 0x5A;
    }

    final got = await _drain(AdtsDemuxer.open(damaged));
    expect(got.length, greaterThan(_frames ~/ 2),
        reason: 'one damaged frame must not discard the rest of the stream — '
            'the old parser returned a clean EOF at the first bad header');
    expect(got.length, lessThan(_frames),
        reason: 'the damaged frame(s) really are lost; this is resync, not '
            'magic');
    // The tail is byte-identical to the undamaged run.
    expect(got.last.data, refPkts.last.data);
  });

  test('a resync keeps the timeline: surviving frames keep their own PTS',
      () async {
    // The frames a resync hunts over still HAPPENED. PTS is derived from the
    // count of frames emitted, so skipping the damage without charging for it
    // stamped every later packet early by the lost frames' duration — a
    // permanent shift (~116 ms for the 5-frame burst a broadcast capture drops)
    // that a muxer or a clock trusting these timestamps runs audio ahead with.
    final plain = await _adts(_frames);
    final ref = await _drain(AdtsDemuxer.open(plain));
    expect(ref, hasLength(_frames));
    // Every frame here is the same size (fixed 40-byte payload + 7-byte header).
    final frameLen = plain.length ~/ _frames;
    expect(frameLen * _frames, plain.length, reason: 'CBR fixture');

    // Wipe frames 4-6 whole, so the demuxer must hunt from frame 4's header to
    // frame 7's and the gap is exactly three frames of time.
    const lost = [4, 5, 6];
    final damaged = Uint8List.fromList(plain);
    for (var i = lost.first * frameLen; i < (lost.last + 1) * frameLen; i++) {
      damaged[i] = 0x5A; // not a sync word, so no false resync inside
    }

    final got = await _drain(AdtsDemuxer.open(damaged));
    final expected = [
      for (var i = 0; i < ref.length; i++)
        if (!lost.contains(i)) ref[i],
    ];
    expect(got, hasLength(expected.length),
        reason: 'only the damaged frames are lost');
    for (var i = 0; i < got.length; i++) {
      expect(got[i].data, expected[i].data, reason: 'payload $i');
      expect(got[i].ptsUs, expected[i].ptsUs,
          reason: 'packet $i is stamped as if the lost frames never existed');
    }

    // seek() and the linear read must still agree — and agree on the CORRECTED
    // timeline, not merely with each other.
    final dm = AdtsDemuxer.open(damaged);
    await dm.seek(ref[lost.last + 1].ptsUs);
    final p = await dm.readPacket();
    await dm.close();
    expect(p!.data, ref[lost.last + 1].data);
    expect(p.ptsUs, ref[lost.last + 1].ptsUs);
  });

  test('garbage everywhere still terminates instead of opening a track',
      () async {
    final junk = Uint8List.fromList(List.generate(4096, (i) => (i * 37) & 0xFF));
    expect(() => AdtsDemuxer.open(junk), throwsA(isA<CodecInitException>()));
  });

  test('seek respects the ID3v2 prefix', () async {
    final tagged = _cat([_id3v2(600), await _adts(_frames)]);
    final dm = AdtsDemuxer.open(tagged);
    final all = await _drain(dm);
    // Mid-frame, so the frame-index arithmetic can't land on a neighbour
    // through integer truncation.
    await dm.seek(all[5].ptsUs + all[5].durationUs ~/ 2);
    final p = await dm.readPacket();
    await dm.close();
    expect(p, isNotNull);
    expect(p!.data, all[5].data,
        reason: 'seeking from byte 0 instead of past the tag lands on the '
            'wrong frame (or on tag bytes)');
  });

  group('channel_configuration is not a channel count', () {
    test('config 7 is EIGHT channels, and round-trips', () async {
      final bytes = await _adts(3, channels: 8);
      // The written header must carry configuration 7, not the count 8.
      final chanCfg = ((bytes[2] & 0x01) << 2) | ((bytes[3] >> 6) & 0x03);
      expect(chanCfg, 7);

      final dm = AdtsDemuxer.open(bytes);
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.channels, 8, reason: 'configuration 7 denotes 7.1 = 8 channels');
      // The AudioSpecificConfig carries the CONFIGURATION, not the count.
      final asc = t.extraData!.bytes;
      expect((asc[1] >> 3) & 0x0F, 7);
      expect(await _drain(dm), hasLength(3));
      await dm.close();
    });

    test('configurations 1-6 are their own count', () async {
      for (final ch in [1, 2, 3, 4, 5, 6]) {
        final dm = AdtsDemuxer.open(await _adts(2, channels: ch));
        expect((dm.tracks.single as AudioTrackInfo).channels, ch);
        await dm.close();
      }
    });

    test('configuration 0 stays rejected (it needs an out-of-band config)',
        () async {
      // Hand-built: config 0 means "described by the AOT specific config",
      // which ADTS alone cannot answer, so opening would invent a channel
      // count.
      final good = await _adts(2);
      final bad = Uint8List.fromList(good);
      bad[2] &= ~0x01; // chanCfg high bit
      bad[3] &= ~0xC0; // chanCfg low bits
      expect(() => AdtsDemuxer.open(bad), throwsA(isA<CodecInitException>()));
    });
  });
}
