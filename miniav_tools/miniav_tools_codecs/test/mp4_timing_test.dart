/// Timing correctness for the first-party ISO-BMFF writer.
///
/// Four classes of bug that all produce a file which PARSES, so nothing short
/// of asserting on the boxes and re-demuxing catches them:
///
///  * B-frames. `stts` is a table of DECODE durations; deriving it from PTS
///    deltas means a reordered stream contributes a negative delta, which an
///    unsigned field turns into a ~4000-second sample.
///  * 32-bit wraps. At a microsecond timescale a u32 duration wraps after 71.6
///    minutes, so a 90-minute recording declares ~18 minutes.
///  * A/V sync. Dropping each track's absolute first PTS independently bakes
///    the gap between the tracks in as a permanent lip-sync error.
///  * `stss` with entry_count 0 means "NO sync samples", not "unknown".
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

import 'mp4_box_probe.dart';

/// An avcC record (starts with 0x01, so the muxer does NOT treat samples as
/// Annex-B and the payloads round-trip byte-for-byte).
final _avcC = Uint8List.fromList([1, 0x64, 0, 0x1f, 0xff, 0xe1]);

VideoTrackInfo _videoTrack() => VideoTrackInfo(
      codec: VideoCodec.h264,
      width: 320,
      height: 240,
      frameRateNumerator: 30,
      frameRateDenominator: 1,
      extraData: CodecExtraData.video(VideoCodec.h264, _avcC),
    );

const _audioTrack =
    AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2);

Uint8List _payload(int seed, [int len = 12]) =>
    Uint8List.fromList(List.generate(len, (i) => (seed * 31 + i) & 0xFF));

Future<Uint8List> _mux(
  List<TrackInfo> tracks,
  List<EncodedPacket> packets,
) async {
  final m = Mp4Muxer.open(MuxerConfig(
    container: Container.mp4,
    output: MuxerOutput.bytes(),
    tracks: tracks,
  ));
  await m.writeHeader();
  for (final p in packets) {
    await m.writePacket(p);
  }
  await m.finish();
  final bytes = Uint8List.fromList(m.getBytes()!);
  await m.close();
  return bytes;
}

Future<Map<int, List<EncodedPacket>>> _demuxByTrack(Uint8List mp4) async {
  final d = Mp4Demuxer.open(mp4);
  final out = <int, List<EncodedPacket>>{};
  for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
    (out[p.trackIndex] ??= []).add(p);
  }
  await d.close();
  return out;
}

void main() {
  group('B-frames (M1: stts from DTS + ctts)', () {
    // Decode order for a classic IBBP GOP, with DTS pulled back by the reorder
    // delay the way every real encoder emits it (so PTS >= DTS throughout).
    const dts = [-66666, -33333, 0, 33333, 66666, 99999, 133332];
    const pts = [0, 99999, 33333, 66666, 199998, 133332, 166665];
    const key = [true, false, false, false, false, false, false];

    List<EncodedPacket> packets() => [
          for (var i = 0; i < dts.length; i++)
            EncodedPacket(
              data: _payload(i),
              ptsUs: pts[i],
              dtsUs: dts[i],
              isKeyframe: key[i],
            ),
        ];

    test('a ctts box is written and PTS/DTS round-trip exactly', () async {
      final mp4 = await _mux([_videoTrack()], packets());

      expect(findAll(mp4, 'ctts'), hasLength(1),
          reason: 'PTS != DTS but no composition-offset table was written — '
              'the reorder is unrecoverable from this file');

      final got = (await _demuxByTrack(mp4))[0]!;
      expect(got.map((p) => p.ptsUs).toList(), pts);
      expect(got.map((p) => p.dtsUs).toList(), dts);
      expect(got.map((p) => p.isKeyframe).toList(), key);
      for (var i = 0; i < got.length; i++) {
        expect(got[i].data, _payload(i), reason: 'sample $i payload');
      }
    });

    test('no sample duration is a wrapped negative PTS delta', () async {
      final mp4 = await _mux([_videoTrack()], packets());
      final stts = findAll(mp4, 'stts').single;
      final d = ByteData.sublistView(mp4);
      final entries = d.getUint32(stts.payloadStart + 4, Endian.big);
      for (var e = 0; e < entries; e++) {
        final delta =
            d.getUint32(stts.payloadStart + 12 + e * 8, Endian.big);
        // A masked negative delta lands in the billions of microseconds.
        expect(delta, lessThan(10000000),
            reason: 'stts entry $e is $delta us — that is a negative PTS '
                'delta reinterpreted as unsigned');
      }
    });

    test('a track with no reordering writes no ctts at all', () async {
      final mp4 = await _mux([_videoTrack()], [
        for (var i = 0; i < 5; i++)
          EncodedPacket(
              data: _payload(i),
              ptsUs: i * 33333,
              dtsUs: i * 33333,
              isKeyframe: i == 0),
      ]);
      expect(findAll(mp4, 'ctts'), isEmpty);
    });

    test('genuinely non-monotonic DTS is rejected, not silently mangled',
        () async {
      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.bytes(),
        tracks: [_videoTrack()],
      ));
      await m.writeHeader();
      for (final t in const [0, 33333, 20000]) {
        await m.writePacket(
            EncodedPacket(data: _payload(t), ptsUs: t, dtsUs: t));
      }
      await expectLater(m.finish(), throwsA(isA<CodecRuntimeException>()));
      await m.close();
    });
  });

  group('wide values (M2: 32-bit wraps)', () {
    // ~5.5 hours of media in 200 tiny packets: the point is the TIMESTAMPS, so
    // this never writes more than a few kilobytes.
    const step = 100000000; // 100 s
    const count = 200;

    Future<Uint8List> longFile() => _mux(
          const [_audioTrack],
          [
            for (var i = 0; i < count; i++)
              EncodedPacket(
                data: _payload(i, 4),
                ptsUs: i * step,
                dtsUs: i * step,
                isKeyframe: true,
              ),
          ],
        );

    test('a duration past u32 promotes mvhd/tkhd/mdhd to version 1', () async {
      final mp4 = await longFile();
      expect((count - 1) * step, greaterThan(0xFFFFFFFF),
          reason: 'the fixture itself must exceed a 32-bit microsecond field');

      for (final type in const ['mvhd', 'tkhd', 'mdhd']) {
        final box = findAll(mp4, type).single;
        expect(fullBoxVersion(mp4, box), 1,
            reason: '$type is still version 0, so its duration wrapped — a '
                '5-hour file would declare minutes');
      }
    });

    test('the long duration survives a round trip', () async {
      final mp4 = await longFile();
      final d = Mp4Demuxer.open(mp4);
      // The LAST sample's own duration counts: the media ends at
      // lastPts + lastDuration, so `count` steps, not `count - 1`. (The muxer
      // gives the final sample the previous delta, 1 step.)
      expect(d.durationUs, count * step);
      final got = <int>[];
      for (var p = await d.readPacket(); p != null; p = await d.readPacket()) {
        got.add(p.ptsUs);
      }
      await d.close();
      expect(got, [for (var i = 0; i < count; i++) i * step]);
    });

    test('short files stay on the version-0 boxes every reader handles',
        () async {
      final mp4 = await _mux(const [_audioTrack], [
        for (var i = 0; i < 4; i++)
          EncodedPacket(
              data: _payload(i, 4),
              ptsUs: i * 21333,
              dtsUs: i * 21333,
              isKeyframe: true),
      ]);
      for (final type in const ['mvhd', 'tkhd', 'mdhd']) {
        expect(fullBoxVersion(mp4, findAll(mp4, type).single), 0);
      }
      // No 64-bit chunk table either: this file is nowhere near 4 GiB.
      expect(findAll(mp4, 'co64'), isEmpty);
      expect(findAll(mp4, 'stco'), hasLength(1));
    });
  });

  group('A/V start offsets (M3: edts/elst)', () {
    test('a video track starting 300ms late keeps that offset', () async {
      const gapUs = 300000;
      final mp4 = await _mux(
        [_videoTrack(), _audioTrack],
        [
          for (var i = 0; i < 6; i++)
            EncodedPacket(
              data: _payload(i),
              ptsUs: gapUs + i * 33333,
              dtsUs: gapUs + i * 33333,
              isKeyframe: i == 0,
              trackIndex: 0,
            ),
          for (var i = 0; i < 10; i++)
            EncodedPacket(
              data: _payload(100 + i, 5),
              ptsUs: i * 21333,
              dtsUs: i * 21333,
              isKeyframe: true,
              trackIndex: 1,
            ),
        ],
      );

      // The video trak must carry an edit list; the audio one starts at the
      // origin and needs none.
      expect(findAll(mp4, 'elst'), hasLength(1),
          reason: 'the later-starting track wrote no edit list, so its offset '
              'is gone');

      final got = await _demuxByTrack(mp4);
      final videoStart = got[0]!.first.ptsUs;
      final audioStart = got[1]!.first.ptsUs;
      expect(audioStart, 0, reason: 'the earliest track defines the origin');
      expect(videoStart - audioStart, gapUs,
          reason: 'the 300ms A/V offset did not survive the round trip — '
              'playback is out of lip-sync by exactly that much');

      // ...and the whole video track is shifted, not just its first sample.
      expect(got[0]!.map((p) => p.ptsUs).toList(),
          [for (var i = 0; i < 6; i++) gapUs + i * 33333]);
    });

    test('an audio track starting 300ms BEFORE video is symmetrical',
        () async {
      const gapUs = 300000;
      final mp4 = await _mux(
        [_videoTrack(), _audioTrack],
        [
          for (var i = 0; i < 6; i++)
            EncodedPacket(
              data: _payload(i),
              ptsUs: 5000000 + i * 33333,
              dtsUs: 5000000 + i * 33333,
              isKeyframe: i == 0,
              trackIndex: 0,
            ),
          for (var i = 0; i < 10; i++)
            EncodedPacket(
              data: _payload(100 + i, 5),
              ptsUs: 5000000 - gapUs + i * 21333,
              dtsUs: 5000000 - gapUs + i * 21333,
              isKeyframe: true,
              trackIndex: 1,
            ),
        ],
      );
      final got = await _demuxByTrack(mp4);
      // The common origin is rebased to 0, but the RELATIVE offset is the
      // thing that matters and it is preserved exactly.
      expect(got[1]!.first.ptsUs, 0);
      expect(got[0]!.first.ptsUs - got[1]!.first.ptsUs, gapUs);
    });

    test('tracks that start together write no edit list', () async {
      final mp4 = await _mux(
        [_videoTrack(), _audioTrack],
        [
          for (var i = 0; i < 4; i++)
            EncodedPacket(
                data: _payload(i),
                ptsUs: i * 33333,
                dtsUs: i * 33333,
                isKeyframe: i == 0,
                trackIndex: 0),
          for (var i = 0; i < 4; i++)
            EncodedPacket(
                data: _payload(50 + i, 5),
                ptsUs: i * 21333,
                dtsUs: i * 21333,
                isKeyframe: true,
                trackIndex: 1),
        ],
      );
      expect(findAll(mp4, 'elst'), isEmpty);
    });
  });

  group('negative-PTS preroll (clip trim)', () {
    // A clip cut mid-GOP anchors at the cut point, so the keyframe and the
    // frames between it and the cut — which the file still has to CARRY for
    // the decoder — arrive at negative PTS. That is a request to trim, not a
    // request to move the origin backwards.
    const prerollUs = 99999; // 3 frames at 30fps
    const videoFrames = 13; // 3 preroll + 10 in-window
    const audioFrames = 16;

    Future<Uint8List> clip() => _mux(
          [_videoTrack(), _audioTrack],
          [
            for (var i = 0; i < videoFrames; i++)
              EncodedPacket(
                data: _payload(i),
                ptsUs: i * 33333 - prerollUs,
                dtsUs: i * 33333 - prerollUs,
                isKeyframe: i == 0,
                trackIndex: 0,
              ),
            for (var i = 0; i < audioFrames; i++)
              EncodedPacket(
                data: _payload(100 + i, 5),
                ptsUs: i * 21333,
                dtsUs: i * 21333,
                isKeyframe: true,
                trackIndex: 1,
              ),
          ],
        );

    test('the preroll is trimmed by the video edit list, not presented',
        () async {
      final mp4 = await clip();
      final elsts = findAll(mp4, 'elst');
      expect(elsts, hasLength(1),
          reason: 'only the video track needs an edit list: taking the origin '
              'from the most negative PTS instead would present the preroll '
              'and push the audio track back by the same amount');

      // One entry, so no leading empty edit — the video starts at movie time
      // zero — and its media_time skips exactly the preroll.
      final e = elsts.single;
      final d = ByteData.sublistView(mp4);
      expect(d.getUint32(e.payloadStart + 4, Endian.big), 1,
          reason: 'entry_count');
      final segmentDurationUs = d.getUint32(e.payloadStart + 8, Endian.big);
      final mediaTimeUs = d.getInt32(e.payloadStart + 12, Endian.big);
      expect(mediaTimeUs, prerollUs,
          reason: 'the edit starts at the cut point, so the preroll is carried '
              'but never shown');
      expect(segmentDurationUs, (videoFrames - 3) * 33333,
          reason: 'the presented segment is the requested window only');
    });

    test('the clip is not lengthened by the preroll', () async {
      final mp4 = await clip();
      final mvhd = findBox(mp4, ['moov', 'mvhd'])!;
      final d = ByteData.sublistView(mp4);
      expect(fullBoxVersion(mp4, mvhd), 0);
      final movieDurationUs = d.getUint32(mvhd.payloadStart + 16, Endian.big);
      // Audio is the longer track (16 x 21333); anchoring on the preroll would
      // add another 99999us of empty audio edit on top of it.
      expect(movieDurationUs, audioFrames * 21333,
          reason: 'the movie is longer than the requested window — the preroll '
              'was presented instead of trimmed');
    });

    test('the preroll samples are still in the file, at negative PTS',
        () async {
      final got = await _demuxByTrack(await clip());
      expect(got[0]!, hasLength(videoFrames),
          reason: 'the preroll must still be decodable — trimming is a '
              'presentation decision, not a reason to drop samples');
      expect(got[0]!.first.ptsUs, -prerollUs);
      expect(got[0]!.first.isKeyframe, isTrue);
      expect(got[1]!.first.ptsUs, 0,
          reason: 'audio starts at the cut point with no head gap');
      // Relative A/V alignment survives the trim.
      expect(got[0]!.map((p) => p.ptsUs).toList(),
          [for (var i = 0; i < videoFrames; i++) i * 33333 - prerollUs]);
    });
  });

  group('sync samples (M4: empty stss)', () {
    test('a track with nothing flagged omits stss instead of writing an '
        'empty one', () async {
      // isKeyframe defaults to false on EncodedPacket, so this is what a
      // producer that never sets it looks like.
      final mp4 = await _mux([_videoTrack()], [
        for (var i = 0; i < 5; i++)
          EncodedPacket(data: _payload(i), ptsUs: i * 33333, dtsUs: i * 33333),
      ]);
      expect(findAll(mp4, 'stss'), isEmpty,
          reason: 'an stss with entry_count 0 declares that NO sample is a '
              'sync sample — the file becomes unseekable and some players '
              'refuse to start it');
      final got = (await _demuxByTrack(mp4))[0]!;
      expect(got.every((p) => p.isKeyframe), isTrue,
          reason: 'no stss means every sample is a sync sample');
    });

    test('an all-keyframe track omits stss too', () async {
      final mp4 = await _mux([_videoTrack()], [
        for (var i = 0; i < 5; i++)
          EncodedPacket(
              data: _payload(i),
              ptsUs: i * 33333,
              dtsUs: i * 33333,
              isKeyframe: true),
      ]);
      expect(findAll(mp4, 'stss'), isEmpty);
      final got = (await _demuxByTrack(mp4))[0]!;
      expect(got.every((p) => p.isKeyframe), isTrue);
    });

    test('a mixed track still writes stss and the flags round-trip', () async {
      final mp4 = await _mux([_videoTrack()], [
        for (var i = 0; i < 7; i++)
          EncodedPacket(
              data: _payload(i),
              ptsUs: i * 33333,
              dtsUs: i * 33333,
              isKeyframe: i % 3 == 0),
      ]);
      expect(findAll(mp4, 'stss'), hasLength(1));
      final got = (await _demuxByTrack(mp4))[0]!;
      expect(got.map((p) => p.isKeyframe).toList(),
          [for (var i = 0; i < 7; i++) i % 3 == 0]);
    });
  });

  group('lifecycle', () {
    test('writePacket after finish throws instead of dropping the data',
        () async {
      final m = Mp4Muxer.open(MuxerConfig(
        container: Container.mp4,
        output: MuxerOutput.bytes(),
        tracks: const [_audioTrack],
      ));
      await m.writeHeader();
      await m.writePacket(
          EncodedPacket(data: _payload(0, 4), ptsUs: 0, dtsUs: 0));
      await m.finish();
      await expectLater(
        m.writePacket(EncodedPacket(data: _payload(1, 4), ptsUs: 1, dtsUs: 1)),
        throwsA(isA<CodecRuntimeException>()),
      );
      await expectLater(m.writeHeader(), throwsA(isA<CodecRuntimeException>()));
      await m.close();
    });
  });

  group('audio sample-entry limits (M5f)', () {
    test('96 kHz AAC does not wrap the 16.16 samplerate field', () async {
      const hi = AudioTrackInfo(
          codec: AudioCodec.aac, sampleRate: 96000, channels: 2);
      final mp4 = await _mux(const [hi], [
        for (var i = 0; i < 3; i++)
          EncodedPacket(
              data: _payload(i, 4),
              ptsUs: i * 10000,
              dtsUs: i * 10000,
              isKeyframe: true),
      ]);
      final d = Mp4Demuxer.open(mp4);
      final at = d.tracks.single as AudioTrackInfo;
      await d.close();
      // 96000 << 16 overflows u32; the truncated value reads back as 30464.
      expect(at.sampleRate, 96000,
          reason: 'the rate was truncated into the 16.16 field — the whole '
              'track would play at the wrong speed');
    });

    test('a channel count AAC cannot encode is refused, not clamped', () {
      expect(
        () => Mp4Muxer.open(const MuxerConfig(
          container: Container.m4a,
          output: BytesMuxerOutput(),
          tracks: [
            AudioTrackInfo(
                codec: AudioCodec.aac, sampleRate: 48000, channels: 9),
          ],
        )),
        throwsA(isA<CodecInitException>()),
        reason: 'clamping 9 channels to the 7.1 code relabels the audio',
      );
    });

    test('7.1 (8 channels) maps to channelConfiguration 7', () async {
      final mp4 = await _mux(
        const [
          AudioTrackInfo(
              codec: AudioCodec.aac, sampleRate: 48000, channels: 8),
        ],
        [
          EncodedPacket(
              data: _payload(0, 4), ptsUs: 0, dtsUs: 0, isKeyframe: true),
        ],
      );
      final d = Mp4Demuxer.open(mp4);
      final at = d.tracks.single as AudioTrackInfo;
      await d.close();
      expect(at.channels, 8);
      // ASC: aot(5)=2, freqIdx(4)=3 (48000), channelConfig(4)=7.
      final asc = at.extraData!.bytes;
      expect(asc, hasLength(2));
      expect((asc[1] >> 3) & 0x0F, 7);
    });
  });
}
