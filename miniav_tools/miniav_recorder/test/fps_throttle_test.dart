/// Tests for the SW fps throttle fix in [_VideoTrackRuntime.startCapture].
///
/// The fps throttle prevents a drop-every-other-frame problem that occurs when
/// the capture device delivers frames faster than the target fps. The fix
/// advances [_lastThrottleUs] by += minInterval (ideal schedule) instead of
/// resetting to actual clock time.
///
/// Background:
///   OLD (broken): _lastThrottleUs = rec.now()
///     → Every subsequent frame arrives ~31.75ms later when capture is 31.5fps
///     → Always below 33.33ms threshold for 30fps limit
///     → Drop, accept, drop, accept → 15fps (half the target)
///
///   NEW (fixed): _lastThrottleUs = _lastThrottleUs < 0 ? nowUs : _lastThrottleUs + minInterval
///     → Schedule advances by ideal 33.33ms regardless of actual arrival time
///     → After first drop, accumulated credit allows ~20 consecutive accepts
///     → Convergence to target rate over ~21-frame window → 30fps
///
/// Because [_VideoTrackRuntime] is private, these tests verify the behavior
/// through simulation and observable properties.
library;

import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helper: Throttle simulator that mirrors recorder.dart logic
// ---------------------------------------------------------------------------

/// Simulates the fps throttle logic from [_VideoTrackRuntime.startCapture].
///
/// This class extracts just the throttle state machine so we can test it
/// deterministically without needing to mock the full recorder pipeline.
class FpsThrottleSimulator {
  FpsThrottleSimulator({
    required this.frameRateNum,
    required this.frameRateDen,
  });

  final int frameRateNum;
  final int frameRateDen;

  int _lastThrottleUs = -1;
  int _frameCount = 0;
  int _droppedCount = 0;

  /// Minimum microseconds between encoded frames.
  int get minIntervalUs => frameRateDen > 0 && frameRateNum > 0
      ? (1000000 * frameRateDen) ~/ frameRateNum
      : 0;

  /// Simulates a frame arrival at the given timestamp (in microseconds).
  /// Returns true if the frame should be accepted, false if it should be dropped.
  bool processFrame(int nowUs) {
    final minInterval = minIntervalUs;

    // No throttle: always accept.
    if (minInterval <= 0) {
      _frameCount++;
      return true;
    }

    // Throttle check: drop if too soon after the last accepted frame.
    if (_lastThrottleUs >= 0 && nowUs - _lastThrottleUs < minInterval) {
      _droppedCount++;
      return false;
    }

    // Accept: advance the ideal schedule, not the actual clock.
    _lastThrottleUs = _lastThrottleUs < 0
        ? nowUs
        : _lastThrottleUs + minInterval;
    _frameCount++;
    return true;
  }

  /// Total frames (accepted + dropped).
  int get totalFrames => _frameCount + _droppedCount;

  /// Frames accepted by throttle.
  int get acceptedFrames => _frameCount;

  /// Frames dropped by throttle.
  int get droppedFrames => _droppedCount;

  /// Current ideal schedule timestamp.
  int get lastThrottleUs => _lastThrottleUs;

  /// Reset for next test.
  void reset() {
    _lastThrottleUs = -1;
    _frameCount = 0;
    _droppedCount = 0;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FPS Throttle — 30 fps target', () {
    late FpsThrottleSimulator throttle;

    setUp(() {
      // 30 fps = 30/1 → minInterval = 1000000 / 30 ≈ 33333 µs
      throttle = FpsThrottleSimulator(frameRateNum: 30, frameRateDen: 1);
    });

    test('first frame is always accepted', () {
      expect(throttle.processFrame(0), isTrue);
      expect(throttle.acceptedFrames, equals(1));
      expect(throttle.droppedFrames, equals(0));
      expect(throttle.lastThrottleUs, equals(0));
    });

    test('frame arriving exactly at minInterval is accepted', () {
      throttle.processFrame(0);
      final minInterval = throttle.minIntervalUs;
      expect(throttle.processFrame(minInterval), isTrue);
      expect(throttle.acceptedFrames, equals(2));
      expect(throttle.droppedFrames, equals(0));
    });

    test('frame arriving before minInterval is dropped', () {
      throttle.processFrame(0);
      final minInterval = throttle.minIntervalUs;
      expect(throttle.processFrame(minInterval - 1), isFalse);
      expect(throttle.acceptedFrames, equals(1));
      expect(throttle.droppedFrames, equals(1));
    });

    test('frame arriving after minInterval is accepted', () {
      throttle.processFrame(0);
      final minInterval = throttle.minIntervalUs;
      expect(throttle.processFrame(minInterval + 1000), isTrue);
      expect(throttle.acceptedFrames, equals(2));
      expect(throttle.droppedFrames, equals(0));
    });

    test('consecutive frames at ideal intervals are all accepted', () {
      const frameCount = 5;
      final minInterval = throttle.minIntervalUs;
      for (int i = 0; i < frameCount; i++) {
        expect(throttle.processFrame(i * minInterval), isTrue);
      }
      expect(throttle.acceptedFrames, equals(frameCount));
      expect(throttle.droppedFrames, equals(0));
    });

    test('no throttle when minInterval is 0', () {
      throttle = FpsThrottleSimulator(frameRateNum: 0, frameRateDen: 1);
      expect(throttle.minIntervalUs, equals(0));
      // All frames should be accepted regardless of timing.
      expect(throttle.processFrame(0), isTrue);
      expect(throttle.processFrame(0), isTrue); // Same timestamp
      expect(throttle.processFrame(1), isTrue);
      expect(throttle.acceptedFrames, equals(3));
      expect(throttle.droppedFrames, equals(0));
    });
  });

  group('FPS Throttle — 31.5 fps capture / 30 fps target (the fix case)', () {
    late FpsThrottleSimulator throttle;
    late int minInterval;

    setUp(() {
      // 30 fps target
      throttle = FpsThrottleSimulator(frameRateNum: 30, frameRateDen: 1);
      minInterval = throttle.minIntervalUs; // ~33333 µs
    });

    test('capture at 31.5 fps converges to 30 fps output', () {
      // 31.5 fps capture interval: ~31746 µs per frame
      const captureInterval = 31746;

      // Simulate 100 frames arriving at 31.5 fps.
      for (int i = 0; i < 100; i++) {
        throttle.processFrame(i * captureInterval);
      }

      // With the fix, we should see most frames accepted with occasional drops,
      // converging to the target rate.
      // Expected: ~30/31.5 ≈ 95.2% acceptance rate
      // Actual acceptance should be 95%+ (allowing for rounding).
      final acceptanceRatio = throttle.acceptedFrames / throttle.totalFrames;
      expect(acceptanceRatio, greaterThan(0.94));
      expect(acceptanceRatio, lessThan(0.96));

      // Sanity check: more frames accepted than dropped.
      expect(throttle.acceptedFrames, greaterThan(throttle.droppedFrames * 4));
    });

    test('capture at 31.5 fps does not drop every-other-frame', () {
      const captureInterval = 31746; // 31.5 fps

      List<bool> results = [];
      for (int i = 0; i < 50; i++) {
        final accepted = throttle.processFrame(i * captureInterval);
        results.add(accepted);
      }

      // With the OLD broken logic, we'd see alternating drop/accept pattern:
      //   [true, false, true, false, ...]
      // With the FIX, we should see clusters (e.g., ~20 trues then 1 false).

      // Count transitions (accept→drop or drop→accept).
      int transitions = 0;
      for (int i = 1; i < results.length; i++) {
        if (results[i] != results[i - 1]) {
          transitions++;
        }
      }

      // Perfect alternation would have 49 transitions.
      // With clustering, we expect far fewer (roughly 50 / 21 ≈ 2-3 transitions).
      expect(
        transitions,
        lessThan(10),
        reason:
            'Too many drop/accept transitions — looks like drop-every-other-frame bug',
      );
    });

    test('schedule stays on ideal track across 100 frames', () {
      const captureInterval = 31746; // 31.5 fps

      // Track schedule progression. With the fix, lastThrottleUs should
      // advance steadily by minInterval. We verify it doesn't stall or
      // accumulate unbounded drift from the capture timestamps.
      final scheduleSnapshots = <int>[];
      for (int i = 0; i < 100; i++) {
        throttle.processFrame(i * captureInterval);
        scheduleSnapshots.add(throttle.lastThrottleUs);
      }

      // Verify the schedule is monotonically increasing (never goes backward).
      for (int i = 1; i < scheduleSnapshots.length; i++) {
        expect(
          scheduleSnapshots[i],
          greaterThanOrEqualTo(scheduleSnapshots[i - 1]),
        );
      }

      // Verify the final schedule is ahead of the first capture time
      // but behind where we'd be if we accepted every frame at actual times.
      // With 95% acceptance, lastThrottleUs should be roughly 95 * minInterval.
      final expectedFinalSchedule = 95 * minInterval;
      expect(throttle.lastThrottleUs, greaterThan(expectedFinalSchedule * 0.9));
      expect(throttle.lastThrottleUs, lessThan(expectedFinalSchedule * 1.1));
    });
  });

  group('FPS Throttle — edge cases', () {
    late FpsThrottleSimulator throttle;

    setUp(() {
      throttle = FpsThrottleSimulator(frameRateNum: 30, frameRateDen: 1);
    });

    test('large gap between frames maintains schedule', () {
      const minInterval = 33333;
      throttle.processFrame(0);
      expect(throttle.lastThrottleUs, equals(0));

      // Simulate a large gap (e.g., 1 second) — e.g., window moved off-screen.
      const largeGap = 1000000;
      throttle.processFrame(largeGap);
      // Should be accepted because it's way past minInterval from 0.
      expect(throttle.acceptedFrames, equals(2));
      // The schedule advances by exactly one minInterval (not catching up to
      // actual time). NOTE: this leaves lastThrottleUs ≈ 33ms while actual time
      // is ≈ 1000ms — the deficit is ~29 frame intervals. As a known side-effect,
      // the next ~29 frames arriving at normal cadence will all pass the throttle
      // (burst-after-gap). In practice screen capture devices resume at their
      // normal hardware rate, so this is rarely observable.
      expect(throttle.lastThrottleUs, equals(minInterval));
    });

    test('zero fps (no throttle) accepts everything', () {
      throttle = FpsThrottleSimulator(frameRateNum: 0, frameRateDen: 1);
      for (int i = 0; i < 10; i++) {
        expect(throttle.processFrame(i), isTrue);
      }
      expect(throttle.acceptedFrames, equals(10));
      expect(throttle.droppedFrames, equals(0));
    });

    test('frames at exact boundaries are handled correctly', () {
      final minInterval = throttle.minIntervalUs;
      throttle.processFrame(0);

      // Frame at exactly minInterval boundary
      expect(throttle.processFrame(minInterval), isTrue);
      // Frame 1 µs before the next boundary
      expect(throttle.processFrame(2 * minInterval - 1), isFalse);
      // Frame at exactly the next boundary
      expect(throttle.processFrame(2 * minInterval), isTrue);

      expect(throttle.acceptedFrames, equals(3));
      expect(throttle.droppedFrames, equals(1));
    });

    test('negative timestamps (clock skew) are handled', () {
      throttle.processFrame(1000);
      expect(throttle.acceptedFrames, equals(1));
      expect(throttle.lastThrottleUs, equals(1000));

      // Negative relative time (could happen with clock skew on some platforms).
      // Since lastThrottleUs is 1000 and nowUs is 500, difference is -500,
      // which is < minInterval, so it should drop.
      expect(throttle.processFrame(500), isFalse);
      expect(throttle.droppedFrames, equals(1));
    });

    test('very high frame rate target', () {
      throttle = FpsThrottleSimulator(frameRateNum: 120, frameRateDen: 1);
      final minInterval = throttle.minIntervalUs; // ~8333 µs
      expect(minInterval, lessThan(10000));

      // Frames at 120 fps intervals
      for (int i = 0; i < 10; i++) {
        expect(throttle.processFrame(i * minInterval), isTrue);
      }
      expect(throttle.acceptedFrames, equals(10));
      expect(throttle.droppedFrames, equals(0));
    });

    test('fractional frame rate (23.976 fps)', () {
      // 23.976 fps = 24000/1001 frames per second
      throttle = FpsThrottleSimulator(frameRateNum: 24000, frameRateDen: 1001);
      final minInterval = throttle.minIntervalUs; // ~41708 µs

      // Simulate capture at exact 23.976 fps
      for (int i = 0; i < 50; i++) {
        expect(throttle.processFrame(i * minInterval), isTrue);
      }
      expect(throttle.acceptedFrames, equals(50));
      expect(throttle.droppedFrames, equals(0));
    });
  });

  group('FPS Throttle — comparison old vs new logic', () {
    /// OLD (broken) throttle: resets _lastThrottleUs to actual clock time.
    bool _processFrameOld(int nowUs, int minInterval, int lastThrottleUs) {
      if (minInterval <= 0) return true;
      if (lastThrottleUs >= 0 && nowUs - lastThrottleUs < minInterval) {
        return false; // Drop
      }
      // OLD: always reset to actual clock time.
      return true; // Accept (but would set lastThrottleUs = nowUs)
    }

    /// NEW (fixed) throttle: advances _lastThrottleUs by ideal interval.
    bool _processFrameNew(int nowUs, int minInterval, int lastThrottleUs) {
      if (minInterval <= 0) return true;
      if (lastThrottleUs >= 0 && nowUs - lastThrottleUs < minInterval) {
        return false; // Drop
      }
      // NEW: advance by ideal interval
      return true; // Accept (but would set lastThrottleUs += minInterval)
    }

    test('old logic with 31.5 fps capture / 30 fps target alternates drops', () {
      const minInterval = 33333;
      const captureInterval = 31746;

      int lastThrottleOld = -1;
      List<bool> resultsOld = [];

      for (int i = 0; i < 20; i++) {
        final nowUs = i * captureInterval;
        final accepted = _processFrameOld(nowUs, minInterval, lastThrottleOld);
        resultsOld.add(accepted);
        if (accepted) {
          lastThrottleOld = nowUs; // OLD logic: reset to actual time
        }
      }

      // With OLD logic: accept, drop, accept, drop, ...
      // Frame 0 (t=0):     lastThrottleOld=-1 → accept; set lastThrottleOld=0
      // Frame 1 (t=31746): 31746-0=31746 < 33333 → drop  (lastThrottleOld stays 0)
      // Frame 2 (t=63492): 63492-0=63492 ≥ 33333 → accept; set lastThrottleOld=63492
      // Frame 3 (t=95238): 95238-63492=31746 < 33333 → drop
      // ... strict ADAD alternation (19 transitions in 20 frames)

      int transitions = 0;
      for (int i = 1; i < resultsOld.length; i++) {
        if (resultsOld[i] != resultsOld[i - 1]) {
          transitions++;
        }
      }
      // Should have many transitions with OLD logic (nearly alternating).
      expect(transitions, greaterThan(12));
    });

    test('new logic with 31.5 fps capture / 30 fps target clusters drops', () {
      const minInterval = 33333;
      const captureInterval = 31746;

      int lastThrottleNew = -1;
      List<bool> resultsNew = [];
      int accepted = 0;

      for (int i = 0; i < 20; i++) {
        final nowUs = i * captureInterval;
        final shouldAccept = _processFrameNew(
          nowUs,
          minInterval,
          lastThrottleNew,
        );
        resultsNew.add(shouldAccept);
        if (shouldAccept) {
          accepted++;
          // NEW logic: advance by ideal interval
          lastThrottleNew = lastThrottleNew < 0
              ? nowUs
              : lastThrottleNew + minInterval;
        }
      }

      // With NEW logic: expect clusters (multiple accepts, then drops).
      int transitions = 0;
      for (int i = 1; i < resultsNew.length; i++) {
        if (resultsNew[i] != resultsNew[i - 1]) {
          transitions++;
        }
      }
      // Should have fewer transitions with NEW logic (clustered).
      expect(transitions, lessThan(8));

      // NEW logic should also accept roughly 95% of frames (30/31.5).
      expect(accepted / resultsNew.length, greaterThan(0.90));
    });
  });

  group('FPS Throttle — real-world scenarios', () {
    late FpsThrottleSimulator throttle;

    setUp(() {
      throttle = FpsThrottleSimulator(frameRateNum: 30, frameRateDen: 1);
    });

    test('60 fps capture to 30 fps output (50% drop rate)', () {
      const captureInterval = 16667; // 60 fps

      for (int i = 0; i < 60; i++) {
        throttle.processFrame(i * captureInterval);
      }

      // Expected: roughly 50% acceptance rate (every other frame).
      final acceptanceRatio = throttle.acceptedFrames / throttle.totalFrames;
      expect(acceptanceRatio, greaterThan(0.48));
      expect(acceptanceRatio, lessThan(0.52));
    });

    test('24 fps capture to 30 fps output (all accepted + some waiting)', () {
      throttle = FpsThrottleSimulator(frameRateNum: 30, frameRateDen: 1);
      final minInterval = throttle.minIntervalUs;
      const captureInterval = 41667; // 24 fps

      for (int i = 0; i < 50; i++) {
        throttle.processFrame(i * captureInterval);
      }

      // 24 fps < 30 fps target, so throttle never drops (all accepted).
      expect(throttle.droppedFrames, equals(0));
      expect(throttle.acceptedFrames, equals(50));
    });

    test('bursty capture (e.g., window focus event) is throttled smoothly', () {
      final minInterval = throttle.minIntervalUs;

      // Simulate a burst of 5 frames arriving nearly simultaneously at t=0,
      // then normal spacing.
      final timestamps = [
        0,
        10,
        20,
        30,
        40,
        0 + minInterval * 5, // Resume normal spacing
        0 + minInterval * 6,
        0 + minInterval * 7,
        0 + minInterval * 8,
      ];

      List<bool> results = [];
      for (final ts in timestamps) {
        results.add(throttle.processFrame(ts));
      }

      // Burst: first frame accepted, rest dropped.
      expect(results[0], isTrue);
      expect(results[1], isFalse); // 10 < 33333
      expect(results[2], isFalse);
      expect(results[3], isFalse);
      expect(results[4], isFalse);

      // After resumption, should converge back.
      // Remaining frames should mostly be accepted.
      final remainingAccepted = results.skip(5).where((r) => r).length;
      expect(remainingAccepted, greaterThanOrEqualTo(3));
    });
  });
}
