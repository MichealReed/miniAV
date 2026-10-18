@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:miniav_web/src/capture_mirror.dart';
import 'package:test/test.dart';

const int kCap = 8;
const int kCh = 1;

({Uint32List header, Float32List samples, CaptureMirrorReader reader}) mk() {
  final header = Uint32List(MirrorHeader.slots);
  final samples = Float32List(kCap * kCh);
  header[MirrorHeader.capacityFrames] = kCap;
  header[MirrorHeader.channels] = kCh;
  return (
    header: header,
    samples: samples,
    reader: CaptureMirrorReader(
        header: header, samples: samples, capacityFrames: kCap, channels: kCh),
  );
}

/// Mimic the C producer for [n] frames starting at value [from].
int produce(Uint32List header, Float32List samples, int w, int n, double from) {
  for (var i = 0; i < n; i++) {
    samples[(w + i) % kCap] = from + i;
  }
  return (w + n) & 0xFFFFFFFF;
}

void main() {
  group('CaptureMirrorReader', () {
    test('drains what the producer wrote, in order', () {
      final m = mk();
      final w = produce(m.header, m.samples, 0, 4, 1);
      final d = m.reader.drain(w);
      expect(d.frames, [1, 2, 3, 4]);
      expect(m.header[MirrorHeader.readCursor], 4);
    });

    test('an empty ring drains nothing and does not move the cursor', () {
      final m = mk();
      final d = m.reader.drain(0);
      expect(d.isEmpty, isTrue);
      expect(m.header[MirrorHeader.readCursor], 0);
    });

    test('🔴 a read that spans the ring seam is contiguous on the way out', () {
      final m = mk();
      // Fill, drain 6, then write 5 more so the data wraps past the end.
      var w = produce(m.header, m.samples, 0, 8, 1);
      m.reader.drain(w, maxFrames: 6);
      w = produce(m.header, m.samples, w, 5, 100);
      final d = m.reader.drain(w);
      // 2 left from the first batch (7,8) then the 5 new ones.
      expect(d.frames, [7, 8, 100, 101, 102, 103, 104]);
    });

    test('cursors are wrap-safe across 2^32', () {
      final m = mk();
      const near = 0xFFFFFFFE;
      m.header[MirrorHeader.readCursor] = near;
      var w = near;
      w = produce(m.header, m.samples, w, 4, 42);
      // 0xFFFFFFFE + 4 wraps to 2.
      expect(w, 2);
      final d = m.reader.drain(w);
      expect(d.frames, [42, 43, 44, 45],
          reason: 'unsigned difference must survive the wrap');
      expect(m.header[MirrorHeader.readCursor], 2);
    });

    test('available() never exceeds the ring, even if the producer lapped us',
        () {
      final m = mk();
      // Producer ran far ahead without us reading: occupancy is nonsense-large.
      expect(m.reader.available(1000), kCap);
    });

    test('overruns are reported as a DELTA, once', () {
      final m = mk();
      m.header[MirrorHeader.overrunFrames] = 7;
      expect(m.reader.drain(0).overrunFrames, 7);
      // Same total, already accounted: must not be re-reported.
      expect(m.reader.drain(0).overrunFrames, 0);
      m.header[MirrorHeader.overrunFrames] = 10;
      expect(m.reader.drain(0).overrunFrames, 3);
    });

    test('maxFrames bounds one drain and leaves the rest readable', () {
      final m = mk();
      final w = produce(m.header, m.samples, 0, 6, 1);
      expect(m.reader.drain(w, maxFrames: 2).frames, [1, 2]);
      expect(m.reader.drain(w).frames, [3, 4, 5, 6]);
    });

    test('multi-channel frames stay interleaved and aligned', () {
      final header = Uint32List(MirrorHeader.slots);
      final samples = Float32List(4 * 2);
      final r = CaptureMirrorReader(
          header: header, samples: samples, capacityFrames: 4, channels: 2);
      // two frames: (1,2) (3,4)
      samples.setAll(0, [1, 2, 3, 4]);
      final d = r.drain(2);
      expect(d.frames, [1, 2, 3, 4]);
      expect(header[MirrorHeader.readCursor], 2);
    });
  });
}
