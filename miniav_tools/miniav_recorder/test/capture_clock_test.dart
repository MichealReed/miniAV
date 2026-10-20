import 'package:miniav_recorder/src/capture_clock.dart';
import 'package:test/test.dart';

/// Master-clock time the source's clock reads zero at. Arbitrary: the clock
/// must not care where either timebase starts.
const _origin = 7000000;

void main() {
  group('CaptureClock', () {
    test('keeps the capture spacing of a thinned capture under even arrivals',
        () {
      // What Windows Graphics Capture does to a 30 fps recording of a 60 Hz
      // desktop under back-pressure: frames captured one, two or three
      // refreshes apart, delivered almost evenly.
      const refresh = 16667;
      const capturedAt = [1, 3, 4, 6, 9, 10, 12, 14, 17, 18];
      final clock = CaptureClock();
      final stamps = <int>[];
      for (var i = 0; i < capturedAt.length; i++) {
        final nativeUs = 1000000 + capturedAt[i] * refresh;
        // Delivered every 33 ms, give or take 3.
        final arrivalUs = _origin + 1000000 + i * 33340 + (i * 7919) % 3000;
        final stamped = clock.stamp(nativeUs, arrivalUs);
        expect(stamped, isNotNull);
        stamps.add(stamped!);
      }
      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i] - stamps[i - 1],
          (capturedAt[i] - capturedAt[i - 1]) * refresh,
          reason: 'frame $i: the step the picture actually took',
        );
      }
      expect(clock.outOfOrder, 0);
      expect(clock.reanchors, 0);
    });

    test('reports the source step and the delivery lag of each frame', () {
      final clock = CaptureClock();
      expect(clock.stamp(1000000, _origin + 1000000), _origin + 1000000);
      expect(clock.lastStepUs, -1, reason: 'no previous frame');
      expect(clock.lastLagUs, 0);
      expect(clock.stamp(1050000, _origin + 1062000), _origin + 1050000);
      expect(clock.lastStepUs, 50000);
      expect(clock.lastLagUs, 12000);
    });

    test('a faster delivery moves the offset without going back in time', () {
      final clock = CaptureClock();
      // First frame 20 ms slow: the offset starts 20 ms too large.
      final a = clock.stamp(1000000, _origin + 1020000)!;
      // Second frame delivered instantly: the true offset.
      final b = clock.stamp(1033333, _origin + 1033333)!;
      expect(b, _origin + 1033333);
      expect(b, greaterThanOrEqualTo(a));
      // From here on the mapping is exact.
      expect(clock.stamp(1066666, _origin + 1070000), _origin + 1066666);
      expect(clock.reanchors, 0);
    });

    test('refuses a frame captured before the previous one', () {
      final clock = CaptureClock();
      expect(clock.stamp(1000000, _origin + 1000000), isNotNull);
      expect(clock.stamp(1033333, _origin + 1040000), isNotNull);
      // Captured 16 ms before the frame already accepted.
      expect(clock.stamp(1016667, _origin + 1045000), isNull);
      // Same capture time again: not newer either.
      expect(clock.stamp(1033333, _origin + 1046000), isNull);
      expect(clock.outOfOrder, 2);
      // The next frame steps from the last ACCEPTED one.
      expect(clock.stamp(1066666, _origin + 1070000), _origin + 1066666);
      expect(clock.lastStepUs, 33333);
    });

    test('a frame without a timestamp takes its arrival time', () {
      final clock = CaptureClock();
      expect(clock.stamp(1000000, _origin + 1000000), _origin + 1000000);
      // DXGI reports no present time for a pointer-only update.
      expect(clock.stamp(0, _origin + 1030000), _origin + 1030000);
      expect(clock.missing, 1);
      expect(clock.lastStepUs, -1);
      // The mapping is untouched by it.
      expect(clock.stamp(1033333, _origin + 1040000), _origin + 1033333);
      expect(clock.lastStepUs, 33333);
    });

    test('a source clock that restarts starts the mapping over', () {
      final clock = CaptureClock();
      expect(clock.stamp(50000000, _origin + 1000000), _origin + 1000000);
      // Ten seconds back: not a late frame, a new clock.
      expect(clock.stamp(40000000, _origin + 1033333), _origin + 1033333);
      expect(clock.outOfOrder, 0);
      expect(clock.reanchors, 1);
      expect(clock.stamp(40033333, _origin + 1070000), _origin + 1066666);
    });

    test('a clock that falls behind real time is re-anchored', () {
      final clock = CaptureClock();
      var arrival = _origin + 1000000;
      var native = 1000000;
      var last = -1;
      for (var i = 0; i < 180; i++) {
        final stamped = clock.stamp(native, arrival)!;
        expect(stamped, greaterThan(last), reason: 'frame $i');
        last = stamped;
        arrival += 33333;
        // For a second the source's clock all but stops while its frames
        // keep coming, so every frame after it looks a second late.
        native += i >= 30 && i < 60 ? 1 : 33333;
      }
      expect(clock.reanchors, 1);
      // Back on the arrival grid once a whole window showed the lag is real.
      expect(clock.stamp(native, arrival), arrival);
      expect(clock.distrusted, isFalse);
    });

    test('a source corrected too often is distrusted for good', () {
      final clock = CaptureClock();
      var arrival = _origin + 1000000;
      var native = 90000000;
      // A first frame, then three restarts.
      for (var frame = 0; frame < 4; frame++) {
        clock.stamp(native, arrival);
        arrival += 33333;
        native -= 20000000;
      }
      expect(clock.distrusted, isTrue);
      // Every frame now takes its arrival time, whatever it carries.
      expect(clock.stamp(native, arrival), arrival);
      expect(clock.stamp(native + 500000, arrival + 33333), arrival + 33333);
      expect(clock.lastLagUs, 0);
    });
  });
}
