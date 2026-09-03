// A recording is finalised ONCE, at the end, over media that is already on
// disk in full. The sample table is the only thing finish() can still get
// wrong — and refusing to build one destroys everything the session captured
// instead of the handful of frames that were actually bad.
//
// Field report (miniav_recorder 0.5.9): three tester sessions of 1.0–2.3 GB
// came back as ftyp + mdat with no moov. One reordered packet ~8 s in took a
// 31-minute recording with it and said nothing until stop. The media was
// intact throughout — 56 899 frames were recovered by hand out of the mdat.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/framing/mp4_container.dart'
    show Mp4TrackTimingReport;
import 'package:test/test.dart';

const _step = 21333; // ~1024 samples @ 48 kHz

Mp4Muxer _openAudio() => Mp4Muxer.open(MuxerConfig(
      container: Container.mp4,
      output: MuxerOutput.bytes(),
      tracks: const [
        AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2),
      ],
    ));

Future<void> _write(Mp4Muxer m, Iterable<int> decodeTimes, {bool dts = true}) async {
  await m.writeHeader();
  for (final t in decodeTimes) {
    await m.writePacket(EncodedPacket(
      data: Uint8List(16),
      ptsUs: t,
      dtsUs: dts ? t : 0,
      durationUs: _step,
      isKeyframe: true,
    ));
  }
}

/// Decode timestamps in arrival order with [swapAt] and its successor
/// delivered the wrong way round — the shape a producer makes when a stall
/// lets a late chunk overtake an earlier one.
List<int> _arrivalOrder(int n, {required int swapAt}) {
  final d = [for (var i = 0; i < n; i++) i * _step];
  final tmp = d[swapAt];
  d[swapAt] = d[swapAt + 1];
  d[swapAt + 1] = tmp;
  return d;
}

void main() {
  group('a backwards decode step is repaired, never fatal', () {
    test('the file still finalises, and every sample survives', () async {
      const n = 400;
      final m = _openAudio();
      await _write(m, _arrivalOrder(n, swapAt: 346));
      await m.finish();

      // The point of the whole exercise: a container a player will open.
      final d = Mp4Demuxer.open(Uint8List.fromList(m.getBytes()!));
      expect(d.durationUs, greaterThan(0));

      var count = 0;
      while (await d.readPacket() != null) {
        count++;
      }
      expect(count, n, reason: 'the repair loses no media');
    });

    test('only the reordered pair is skewed, and by the minimum', () async {
      const n = 400;
      const swap = 346;
      final m = _openAudio();
      await _write(m, _arrivalOrder(n, swapAt: swap));
      await m.finish();

      final r = m.timingReports.single;
      expect(r.outOfOrderPackets, 1);
      expect(r.firstOutOfOrderSample, swap + 1,
          reason: 'the SECOND of the swapped pair is the one that steps back');
      expect(r.firstOutOfOrderFromUs, (swap + 1) * _step);
      expect(r.firstOutOfOrderToUs, swap * _step);
      expect(r.repairedSamples, 1);
      expect(r.repairedSkewUs, _step + 1,
          reason: 'clamped to prev+1us — the whole step, plus the microsecond');
      expect(r.isClean, isFalse);
    });

    test('an in-order track is timed exactly as before and reports clean',
        () async {
      const n = 64;
      final m = _openAudio();
      await _write(m, [for (var i = 0; i < n; i++) i * _step]);
      await m.finish();

      expect(m.timingReports.single.isClean, isTrue);
      final d = Mp4Demuxer.open(Uint8List.fromList(m.getBytes()!));
      expect(d.durationUs, n * _step);
    });

    test('samples sharing a DTS still take their declared duration', () async {
      // A tie is a producer saying "use my durationUs", not a regression.
      // Clamping it to +1 us would silently shrink a real audio frame — the
      // repair has to stay off this path.
      final m = _openAudio();
      await _write(m, [0, 0, _step, 2 * _step]);
      await m.finish();

      final r = m.timingReports.single;
      expect(r.repairedSamples, 0, reason: 'a tie is not a step backwards');
      expect(r.outOfOrderPackets, 0);
    });

    test('a whole backlog draining backwards recovers on its own', () async {
      // 16 packets arrive in reverse — a stall's queue emptying the wrong way
      // round, which is what a 325 ms regression looks like from here.
      const n = 200;
      final d = [for (var i = 0; i < n; i++) i * _step];
      d.setRange(100, 116, d.sublist(100, 116).reversed.toList());

      final m = _openAudio();
      await _write(m, d);
      await m.finish();

      final r = m.timingReports.single;
      expect(r.outOfOrderPackets, 15, reason: 'every packet after the first');
      expect(r.repairedSamples, 15);

      final dm = Mp4Demuxer.open(Uint8List.fromList(m.getBytes()!));
      expect(dm.durationUs, n * _step,
          reason: 'the clamp is self-correcting: once the producer overtakes '
              'it again the timeline is exact, so the total is unchanged');
    });
  });

  group('the damage is reported where it happens', () {
    test('out-of-order is visible before finish(), not only after', () async {
      final m = _openAudio();
      await _write(m, _arrivalOrder(20, swapAt: 5));

      // No finish() yet — this is what makes a 31-minute session knowable at
      // second 8 instead of at stop.
      final Mp4TrackTimingReport r = m.timingReports.single;
      expect(r.outOfOrderPackets, 1);
      expect(r.firstOutOfOrderSample, 6);
      expect(r.repairedSamples, 0, reason: 'the index has not been built yet');
      await m.finish();
    });

    test('a producer that leaves dts at 0 is judged on its pts', () async {
      // "dts always 0" means decode order IS presentation order, so the
      // regression detector has to follow the same rule the index build does.
      final m = _openAudio();
      await _write(m, [0, _step, 3 * _step, 2 * _step], dts: false);
      await m.finish();

      final r = m.timingReports.single;
      expect(r.outOfOrderPackets, 1);
      expect(r.firstOutOfOrderSample, 3);
      expect(r.repairedSamples, 1);
    });
  });
}
