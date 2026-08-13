/// Pure-Dart MP3 demux — the half of the mp3/AAC disambiguation that lives in
/// [Mp3Demuxer], plus the shared sync helpers both parsers key off.
///
/// The fixtures are synthesised (see `mp3_fixtures.dart`), so every assertion
/// here is an exact expected value: frame count, duration, PTS, byte layout.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:miniav_tools_codecs/src/framing/mp3_container.dart';
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:test/test.dart';

import 'mp3_fixtures.dart';

Future<List<EncodedPacket>> _readAll(PlatformDemuxer d) async {
  final out = <EncodedPacket>[];
  for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
    out.add(p);
  }
  return out;
}

/// The demuxer's PTS rule, restated: cumulative samples → microseconds. Written
/// out here so a change in rounding strategy fails a test instead of silently
/// re-deriving itself.
int _ptsOf(int frameIndex, int samplesPerFrame, int sampleRate) =>
    frameIndex * samplesPerFrame * 1000000 ~/ sampleRate;

void main() {
  const cbr = Mp3FrameSpec(); // MPEG-1, 128 kbps, 44100, stereo → 417 B
  const mpeg2Mono = Mp3FrameSpec(
    versionBits: 2, // MPEG-2
    bitrateIndex: 8, // 64 kbps
    rateIndex: 0, // 22050
    channelMode: 3, // mono
  );

  group('sync discriminators', () {
    test('ADTS sync requires layer 00', () {
      // Real ADTS second bytes: MPEG-4/MPEG-2 × CRC/no-CRC.
      for (final b1 in [0xF0, 0xF1, 0xF8, 0xF9]) {
        expect(isAdtsSync(0xFF, b1), isTrue, reason: 'b1=$b1');
        expect(isMp3Sync(0xFF, b1), isFalse, reason: 'b1=$b1');
      }
    });

    test('bare mp3 sync bytes are NOT ADTS', () {
      // FF FB / FA (MPEG-1), FF F3 / F2 (MPEG-2), FF E3 (MPEG-2.5) — every one
      // of these passed the old `(b1 & 0xF0) == 0xF0` ADTS check.
      for (final b1 in [0xFB, 0xFA, 0xF3, 0xF2, 0xE3, 0xE2]) {
        expect(isMp3Sync(0xFF, b1), isTrue, reason: 'b1=$b1');
        expect(isAdtsSync(0xFF, b1), isFalse, reason: 'b1=$b1');
      }
    });

    test('Layer I/II and the reserved version are not mp3', () {
      expect(isMp3Sync(0xFF, 0xFF), isFalse); // layer I
      expect(isMp3Sync(0xFF, 0xFD), isFalse); // layer II
      expect(isMp3Sync(0xFF, 0xF9), isFalse); // layer reserved (ADTS shape)
      expect(isMp3Sync(0xFF, 0xEB), isFalse); // version reserved
      expect(isMp3Sync(0xFE, 0xFB), isFalse); // no sync word
    });

    test('no byte pair can be both', () {
      for (var b1 = 0; b1 <= 0xFF; b1++) {
        expect(isAdtsSync(0xFF, b1) && isMp3Sync(0xFF, b1), isFalse,
            reason: 'b1=$b1 satisfies both');
      }
    });

    test('ID3 magic', () {
      expect(isId3Magic(0x49, 0x44, 0x33), isTrue);
      expect(isId3Magic(0x49, 0x44, 0x34), isFalse);
    });
  });

  group('bare CBR', () {
    // Alternating padding — 417/418 byte frames, the real CBR 44100 pattern.
    final specs = [
      for (var i = 0; i < 10; i++) cbr.copyWith(padding: i.isOdd, fill: i * 5),
    ];
    final bytes = mp3Stream(specs);

    test('frame count, rate, channels and counted duration', () async {
      final dm = Mp3Demuxer.open(bytes);
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.codec, AudioCodec.mp3);
      expect(t.sampleRate, 44100);
      expect(t.channels, 2);
      expect(t.extraData, isNull); // mp3 has no out-of-band config
      expect(dm.frameCount, 10);
      expect(dm.resyncCount, 0);
      expect(dm.vbrHeader, isNull);
      expect(dm.firstFrameOffset, 0);
      expect(dm.isSeekable, isTrue);
      expect(dm.durationUs, 10 * 1152 * 1000000 ~/ 44100);
      await dm.close();
    });

    test('packets are whole frames and re-concatenate to the input', () async {
      final dm = Mp3Demuxer.open(bytes);
      final pkts = await _readAll(dm);
      expect(pkts.length, 10);
      final rebuilt = BytesBuilder();
      for (var i = 0; i < pkts.length; i++) {
        final p = pkts[i];
        expect(p.data.length, specs[i].frameLength); // 417 / 418
        expect(p.data[0], 0xFF, reason: 'header must be included');
        expect(isMp3Sync(p.data[0], p.data[1]), isTrue);
        expect(p.isKeyframe, isTrue);
        rebuilt.add(p.data);
      }
      expect(rebuilt.toBytes(), bytes);
      await dm.close();
    });

    test('PTS is monotonic with exact 1152-sample spacing', () async {
      final dm = Mp3Demuxer.open(bytes);
      final pkts = await _readAll(dm);
      for (var i = 0; i < pkts.length; i++) {
        expect(pkts[i].ptsUs, _ptsOf(i, 1152, 44100));
        expect(pkts[i].dtsUs, pkts[i].ptsUs);
        expect(pkts[i].durationUs, 1152 * 1000000 ~/ 44100);
        if (i > 0) expect(pkts[i].ptsUs, greaterThan(pkts[i - 1].ptsUs));
      }
      // Derived from the index, not accumulated: the last PTS is exactly the
      // rounded position of sample 9*1152, never 9 rounding errors deep.
      expect(pkts.last.ptsUs, 9 * 1152 * 1000000 ~/ 44100);
      await dm.close();
    });

    test('a single complete frame is a valid stream', () async {
      final dm = Mp3Demuxer.open(mp3Frame(cbr));
      expect(dm.frameCount, 1);
      expect((await _readAll(dm)).length, 1);
      await dm.close();
    });

    test('reading past the end returns null, repeatedly', () async {
      final dm = Mp3Demuxer.open(bytes);
      await _readAll(dm);
      expect(await dm.readPacket(), isNull);
      expect(await dm.readPacket(), isNull);
      await dm.close();
      await expectLater(
          dm.readPacket(), throwsA(isA<CodecRuntimeException>()));
    });
  });

  group('ID3v2 skipping', () {
    final audio = mp3Stream(repeatSpec(cbr, 6));

    test('a plain tag is skipped', () async {
      final f = concatBytes([id3v2Tag(bodySize: 40), audio]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.firstFrameOffset, 50); // 10-byte header + 40-byte body
      expect(dm.frameCount, 6);
      await dm.close();
    });

    test('a syncsafe size above 127 decodes as 7-bits-per-byte', () async {
      // 200 bytes: a big-endian read would see 0x48 (72) and land mid-tag.
      final f = concatBytes([id3v2Tag(bodySize: 200), audio]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.firstFrameOffset, 210);
      expect(dm.frameCount, 6);
      await dm.close();
    });

    test('the ID3v2.4 footer flag adds 10 bytes', () async {
      final f = concatBytes([id3v2Tag(bodySize: 32, footer: true), audio]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.firstFrameOffset, 52); // 10 + 32 + 10
      expect(dm.frameCount, 6);
      await dm.close();
    });

    test('multiple tags, and a trailing tag after the audio', () async {
      final f = concatBytes([
        id3v2Tag(bodySize: 16),
        id3v2Tag(bodySize: 300),
        audio,
        id3v2Tag(bodySize: 64), // some writers append one
      ]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.firstFrameOffset, 26 + 310);
      expect(dm.frameCount, 6);
      expect(dm.resyncCount, 0, reason: 'a trailing tag is not corruption');
      await dm.close();
    });

    test('a tag body full of zero padding does not fake a frame', () async {
      final f = concatBytes([id3v2Tag(bodySize: 1024), audio]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.frameCount, 6);
      await dm.close();
    });
  });

  group('Xing / Info / VBRI metadata frame', () {
    // Mixed bitrates — the case a bitrate-based duration estimate gets wrong.
    final vbrSpecs = [
      for (var i = 0; i < 12; i++)
        cbr.copyWith(bitrateIndex: 5 + (i % 6), fill: i * 3),
    ];
    final audio = mp3Stream(vbrSpecs);

    test('the Xing frame is parsed and excluded from packets', () async {
      final xing = mp3VbrFrame(cbr, frameCount: 12, byteCount: audio.length);
      final f = concatBytes([xing, audio]);
      final dm = Mp3Demuxer.open(f);

      expect(dm.vbrHeader, isNotNull);
      expect(dm.vbrHeader!.kind, 'Xing');
      expect(dm.vbrHeader!.frameCount, 12);
      expect(dm.vbrHeader!.byteCount, audio.length);
      // The index is authoritative and agrees with the tag.
      expect(dm.frameCount, 12);

      final pkts = await _readAll(dm);
      expect(pkts.length, 12);
      expect(pkts.first.ptsUs, 0, reason: 'audio time starts at the first '
          'AUDIO frame, not at the metadata frame');
      expect(pkts.first.data.length, vbrSpecs.first.frameLength);
      expect(dm.durationUs, 12 * 1152 * 1000000 ~/ 44100);
      await dm.close();
    });

    test('duration is counted, not derived from the first frame bitrate',
        () async {
      final f = concatBytes([
        mp3VbrFrame(cbr, frameCount: 12, byteCount: audio.length),
        audio,
      ]);
      final dm = Mp3Demuxer.open(f);
      // 12 frames at mixed bitrates: every frame is 1152 samples regardless of
      // its size, which is exactly what a byte-rate estimate cannot know.
      expect(dm.durationUs, 313469);
      await dm.close();
    });

    test('an Info (CBR) frame is treated the same way', () async {
      final f = concatBytes([
        mp3VbrFrame(cbr, kind: 'Info', frameCount: 6),
        mp3Stream(repeatSpec(cbr, 6)),
      ]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.vbrHeader!.kind, 'Info');
      expect(dm.frameCount, 6);
      await dm.close();
    });

    test('a VBRI frame is detected at its fixed offset', () async {
      final f = concatBytes([
        mp3VbrFrame(cbr, kind: 'VBRI', frameCount: 6, byteCount: 99),
        mp3Stream(repeatSpec(cbr, 6)),
      ]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.vbrHeader!.kind, 'VBRI');
      expect(dm.vbrHeader!.frameCount, 6);
      expect(dm.vbrHeader!.byteCount, 99);
      expect(dm.frameCount, 6);
      await dm.close();
    });

    test('a CBR file with no metadata frame keeps all of its frames', () async {
      final dm = Mp3Demuxer.open(mp3Stream(repeatSpec(cbr, 6)));
      expect(dm.vbrHeader, isNull);
      expect(dm.frameCount, 6, reason: 'nothing may be dropped as metadata');
      await dm.close();
    });

    test('ID3 + Xing together', () async {
      final f = concatBytes([
        id3v2Tag(bodySize: 128),
        mp3VbrFrame(cbr, frameCount: 6),
        mp3Stream(repeatSpec(cbr, 6)),
      ]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.firstFrameOffset, 138);
      expect(dm.vbrHeader!.kind, 'Xing');
      expect(dm.frameCount, 6);
      await dm.close();
    });
  });

  group('MPEG-2 mono (576 samples/frame)', () {
    test('rate, channels, frame length and timing', () async {
      final specs = repeatSpec(mpeg2Mono, 8);
      final dm = Mp3Demuxer.open(mp3Stream(specs));
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.sampleRate, 22050);
      expect(t.channels, 1);
      expect(dm.frameCount, 8);
      expect(dm.durationUs, 8 * 576 * 1000000 ~/ 22050);

      final pkts = await _readAll(dm);
      expect(pkts.first.data.length, 72 * 64000 ~/ 22050); // 208 bytes
      for (var i = 0; i < pkts.length; i++) {
        expect(pkts[i].ptsUs, _ptsOf(i, 576, 22050));
        expect(pkts[i].durationUs, 576 * 1000000 ~/ 22050);
      }
      await dm.close();
    });

    test('a mono Xing frame is found at its shorter side-info offset',
        () async {
      final f = concatBytes([
        mp3VbrFrame(mpeg2Mono, frameCount: 4),
        mp3Stream(repeatSpec(mpeg2Mono, 4)),
      ]);
      final dm = Mp3Demuxer.open(f);
      expect(dm.vbrHeader!.frameCount, 4);
      expect(dm.frameCount, 4);
      await dm.close();
    });
  });

  group('resync', () {
    test('garbage mid-stream is skipped and framing continues', () async {
      final head = mp3Stream(repeatSpec(cbr, 3));
      final tail = mp3Stream(repeatSpec(cbr, 3));
      final dm = Mp3Demuxer.open(concatBytes([head, garbage(300), tail]));

      expect(dm.frameCount, 6,
          reason: 'the stream must not end at the garbage');
      expect(dm.resyncCount, 1);
      final pkts = await _readAll(dm);
      expect(pkts.length, 6);
      // Time is continuous across the gap: the garbage carried no samples.
      for (var i = 0; i < pkts.length; i++) {
        expect(pkts[i].ptsUs, _ptsOf(i, 1152, 44100));
      }
      await dm.close();
    });

    test('several separate garbage runs are each counted', () async {
      final dm = Mp3Demuxer.open(concatBytes([
        mp3Stream(repeatSpec(cbr, 2)),
        garbage(64),
        mp3Stream(repeatSpec(cbr, 2)),
        garbage(97),
        mp3Stream(repeatSpec(cbr, 2)),
      ]));
      expect(dm.frameCount, 6);
      expect(dm.resyncCount, 2);
      await dm.close();
    });

    test('a garbage tail simply ends the stream', () async {
      final dm = Mp3Demuxer.open(
        concatBytes([mp3Stream(repeatSpec(cbr, 4)), garbage(500)]),
      );
      expect(dm.frameCount, 4);
      await dm.close();
    });
  });

  group('truncated input', () {
    test('a half-written final frame is dropped, not emitted', () async {
      final whole = mp3Stream(repeatSpec(cbr, 5));
      final partial = mp3Frame(cbr).sublist(0, 200); // header + half a frame
      final dm = Mp3Demuxer.open(concatBytes([whole, partial]));
      expect(dm.frameCount, 5);
      expect(dm.durationUs, 5 * 1152 * 1000000 ~/ 44100);
      final pkts = await _readAll(dm);
      expect(pkts.length, 5);
      for (final p in pkts) {
        expect(p.data.length, cbr.frameLength);
      }
      await dm.close();
    });
  });

  group('rejects non-mp3 input', () {
    test('a lone false sync with no second frame', () {
      // One plausible header, nothing that confirms it — the exact shape that
      // used to open as a track and then report EOF a packet or two later.
      final fake = Uint8List(120);
      fake[0] = 0xFF;
      fake[1] = 0xFB;
      fake[2] = 0x90;
      fake[3] = 0x00;
      expect(() => Mp3Demuxer.open(fake),
          throwsA(isA<CodecInitException>()));
    });

    test('a false sync buried in random bytes', () {
      final noise = garbage(4096);
      noise[1000] = 0xFF;
      noise[1001] = 0xFB;
      noise[1002] = 0x90;
      noise[1003] = 0x00;
      expect(() => Mp3Demuxer.open(noise),
          throwsA(isA<CodecInitException>()));
    });

    test('ADTS (AAC) bytes', () {
      final adts = concatBytes([
        for (var i = 0; i < 4; i++) adtsFrame(payloadLength: 32 + i),
      ]);
      expect(isAdtsSync(adts[0], adts[1]), isTrue);
      expect(isMp3Sync(adts[0], adts[1]), isFalse);
      expect(() => Mp3Demuxer.open(adts),
          throwsA(isA<CodecInitException>()));
    });

    test('empty and short input', () {
      expect(() => Mp3Demuxer.open(Uint8List(0)),
          throwsA(isA<CodecInitException>()));
      expect(() => Mp3Demuxer.open(Uint8List.fromList([0xFF, 0xFB])),
          throwsA(isA<CodecInitException>()));
    });

    test('a metadata frame with no audio behind it', () {
      // Opening this successfully would mean a track that reports EOF on the
      // first read, with no fall-through left to the next backend.
      expect(() => Mp3Demuxer.open(mp3VbrFrame(cbr, frameCount: 0)),
          throwsA(isA<CodecInitException>()));
    });

    test('free-format says so instead of "no sync"', () {
      final free = Uint8List(512);
      free[0] = 0xFF;
      free[1] = 0xFB;
      free[2] = 0x00; // bitrate index 0 = free format
      free[3] = 0x00;
      expect(
        () => Mp3Demuxer.open(free),
        throwsA(
          isA<CodecInitException>().having(
            (e) => e.message,
            'message',
            contains('free-format'),
          ),
        ),
      );
    });
  });

  group('seek', () {
    final bytes = mp3Stream(repeatSpec(cbr, 40));

    test('lands on the frame containing the timestamp', () async {
      final dm = Mp3Demuxer.open(bytes);
      for (final target in [0, 7, 23, 39]) {
        await dm.seek(_ptsOf(target, 1152, 44100));
        final p = await dm.readPacket();
        expect(p!.ptsUs, _ptsOf(target, 1152, 44100), reason: 'frame $target');
      }
      await dm.close();
    });

    test('a timestamp inside a frame rewinds to that frame start', () async {
      final dm = Mp3Demuxer.open(bytes);
      await dm.seek(_ptsOf(11, 1152, 44100) + 5000);
      expect((await dm.readPacket())!.ptsUs, _ptsOf(11, 1152, 44100));
      await dm.close();
    });

    test('negative and past-the-end targets clamp', () async {
      final dm = Mp3Demuxer.open(bytes);
      await dm.seek(-1);
      expect((await dm.readPacket())!.ptsUs, 0);
      await dm.seek(dm.durationUs! * 10);
      expect((await dm.readPacket())!.ptsUs, _ptsOf(39, 1152, 44100));
      expect(await dm.readPacket(), isNull);
      await dm.close();
    });

    test('seeking back replays the same bytes', () async {
      final dm = Mp3Demuxer.open(bytes);
      final first = await _readAll(dm);
      await dm.seek(0);
      final again = await _readAll(dm);
      expect(again.length, first.length);
      for (var i = 0; i < first.length; i++) {
        expect(again[i].data, first[i].data);
        expect(again[i].ptsUs, first[i].ptsUs);
      }
      await dm.close();
    });
  });

  group('real files', () {
    test('test/assets/tone.mp3 (ID3v2 + LAME Info frame)', () async {
      final f = File('test/assets/tone.mp3');
      if (!f.existsSync()) {
        markTestSkipped('test/assets/tone.mp3 not found');
        return;
      }
      final dm = Mp3Demuxer.open(f.readAsBytesSync());
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.codec, AudioCodec.mp3);
      expect(t.sampleRate, 48000);
      expect(t.channels, 2);
      expect(dm.firstFrameOffset, 44); // 10-byte header + 34-byte ID3v2.4 body
      expect(dm.vbrHeader, isNotNull);
      expect(dm.vbrHeader!.kind, 'Info');
      expect(dm.resyncCount, 0);
      // The tag's own frame count must agree with the counted index.
      expect(dm.frameCount, dm.vbrHeader!.frameCount);
      expect(dm.frameCount, 12);
      expect(dm.durationUs, 12 * 1152 * 1000000 ~/ 48000);

      final pkts = await _readAll(dm);
      expect(pkts.length, 12);
      var bytes = 0;
      for (var i = 0; i < pkts.length; i++) {
        expect(pkts[i].ptsUs, _ptsOf(i, 1152, 48000));
        expect(isMp3Sync(pkts[i].data[0], pkts[i].data[1]), isTrue);
        bytes += pkts[i].data.length;
      }
      // Every audio byte after the Info frame is accounted for.
      expect(bytes, f.lengthSync() - 44 - 384);
      await dm.close();
    });

    test('MINIAV_TEST_MP3 (set the env var to point at a real .mp3)', () async {
      final path = Platform.environment['MINIAV_TEST_MP3'];
      if (path == null || path.isEmpty) {
        markTestSkipped('MINIAV_TEST_MP3 not set');
        return;
      }
      final dm = Mp3Demuxer.open(File(path).readAsBytesSync());
      final t = dm.tracks.single as AudioTrackInfo;
      expect(t.sampleRate, greaterThan(0));
      expect(t.channels, inInclusiveRange(1, 2));
      expect(dm.frameCount, greaterThan(0));
      expect(dm.durationUs, greaterThan(0));

      final pkts = await _readAll(dm);
      expect(pkts.length, dm.frameCount);
      for (var i = 1; i < pkts.length; i++) {
        expect(pkts[i].ptsUs, greaterThan(pkts[i - 1].ptsUs));
      }
      // A real encoder's stream should need no resyncs at all.
      expect(dm.resyncCount, 0,
          reason: 'unexpected garbage in $path (${dm.resyncCount} resyncs)');
      await dm.close();
    });
  });
}
