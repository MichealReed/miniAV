import 'package:miniav_recorder/src/capture_rate_watch.dart';
import 'package:test/test.dart';

/// Feeds [watch] frames at the given steps, in microseconds, starting at
/// [startUs], and returns each change with the time of the frame it came on.
List<(int, CaptureRateChange)> _feed(
  CaptureRateWatch watch,
  Iterable<int> steps, {
  int startUs = 5000000,
}) {
  final changes = <(int, CaptureRateChange)>[];
  var t = startUs;
  watch.frame(t);
  for (final step in steps) {
    t += step;
    final change = watch.frame(t);
    if (change != null) changes.add((t - startUs, change));
  }
  return changes;
}

/// [seconds] of a camera alternating [a] and [b] microsecond steps.
Iterable<int> _alternating(int a, int b, double seconds) sync* {
  var elapsed = 0;
  for (var i = 0; elapsed < seconds * 1e6; i++) {
    final step = i.isEven ? a : b;
    elapsed += step;
    yield step;
  }
}

void main() {
  group('CaptureRateWatch', () {
    test('a camera at its rate reports nothing', () {
      final watch = CaptureRateWatch(nominalFps: 30);
      expect(_feed(watch, _alternating(33333, 33334, 60)), isEmpty);
      expect(watch.lastFps, closeTo(30, 0.01));
      expect(watch.low, isFalse);
    });

    test('a camera at 24 of 30 fps reports once it has lasted 10 s', () {
      // The Logitech C922 in a dim room: 32 and 48 ms steps.
      final watch = CaptureRateWatch(nominalFps: 30);
      final changes = _feed(watch, _alternating(32000, 48000, 60));
      expect(changes, hasLength(1));
      expect(changes.single.$2, CaptureRateChange.dropped);
      expect(changes.single.$1, inInclusiveRange(10000000, 12600000));
      expect(watch.lastFps, closeTo(25, 0.5));
      expect(watch.low, isTrue);
    });

    test('a dip shorter than 10 s reports nothing', () {
      final watch = CaptureRateWatch(nominalFps: 30);
      final steps = [
        ..._alternating(33333, 33334, 10),
        ..._alternating(66667, 66666, 6),
        ..._alternating(33333, 33334, 10),
      ];
      expect(_feed(watch, steps), isEmpty);
    });

    test('reports the recovery, and a later drop again', () {
      final watch = CaptureRateWatch(nominalFps: 30);
      final steps = [
        ..._alternating(66667, 66666, 15), // 15 fps
        ..._alternating(33333, 33334, 10),
        ..._alternating(66667, 66666, 15),
      ];
      expect(_feed(watch, steps).map((c) => c.$2), [
        CaptureRateChange.dropped,
        CaptureRateChange.recovered,
        CaptureRateChange.dropped,
      ]);
    });

    test('stalls and pauses are not a low rate', () {
      // A frame every 33 ms, but a 2 s gap every 3 s: the windows holding a
      // gap are skipped, and the rest are at the rate.
      final watch = CaptureRateWatch(nominalFps: 30);
      final steps = <int>[];
      for (var i = 0; i < 10; i++) {
        steps.addAll(_alternating(33333, 33334, 3));
        steps.add(2000000);
      }
      expect(_feed(watch, steps), isEmpty);
    });

    test('a capture time that goes back starts the measurement over', () {
      final watch = CaptureRateWatch(nominalFps: 30);
      expect(_feed(watch, _alternating(33333, 33334, 4)), isEmpty);
      // Re-anchored far earlier, then 24 fps for 9 s: not yet sustained.
      expect(
        _feed(watch, _alternating(32000, 48000, 9), startUs: 1000),
        isEmpty,
      );
    });
  });
}
