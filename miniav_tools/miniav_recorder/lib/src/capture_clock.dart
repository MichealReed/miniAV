/// Puts a capture source's own frame timestamps on the recorder's clock.
/// Pure timing policy — no I/O — so it is unit-testable.
library;

/// Maps the timestamp a capture source stamps on each frame onto the
/// recorder's master clock, and refuses frames that arrive out of capture
/// order.
///
/// Why not simply use the time a frame ARRIVES: delivery latency varies frame
/// to frame. Windows Graphics Capture fills its frame pool at the display rate
/// and hands frames over as the pool drains, so a 30 fps recording of a 60 Hz
/// desktop receives frames that were captured 33 ms apart, then 50, then 17,
/// at arrival times that are nearly even. Stamping arrival time puts an even
/// clock under uneven content — the picture steps forward unevenly and, at
/// the short steps, looks like it jumps back. The capture time is what the
/// picture actually shows.
///
/// The source's timestamps are in its own timebase. Every platform this runs
/// on derives them from the monotonic counter the recorder's clock reads
/// (QueryPerformanceCounter on Windows, mach_absolute_time on Apple,
/// CLOCK_MONOTONIC on Linux), so the two differ by a constant offset plus the
/// delivery latency. The offset is taken from the frame that arrived fastest:
/// the smallest arrival-minus-capture seen so far. That is the one estimate a
/// late frame can never make worse, and mapped times stay strictly increasing
/// whenever the source's own times are.
///
/// Missing timestamps (zero — DXGI reports none for a pointer-only update)
/// fall back to the arrival time. A source whose clock turns out not to run at
/// real-time rate is distrusted for good after a few corrections, and from
/// then on every frame takes its arrival time.
class CaptureClock {
  CaptureClock({
    this.windowUs = 2000000,
    this.maxLagUs = 500000,
    this.resetJumpUs = 1000000,
    this.maxReanchors = 3,
  });

  /// Length of the window over which the smallest lag is judged.
  final int windowUs;

  /// A whole window in which no frame came closer than this to the offset
  /// means the offset is stale (the source's clock jumped or drifted), and it
  /// is moved up to the window's smallest lag.
  final int maxLagUs;

  /// A source timestamp further than this BEHIND the previous one is a clock
  /// that restarted, not a frame out of order: the mapping starts over.
  final int resetJumpUs;

  /// Corrections tolerated before the source's clock is distrusted.
  final int maxReanchors;

  int? _offsetUs;
  int _lastNativeUs = -1;
  int _windowStartUs = -1;
  int _windowMinLagUs = 0;

  /// Frames refused because their capture time was not newer than the
  /// previous frame's.
  int outOfOrder = 0;

  /// Frames that carried no timestamp and took their arrival time.
  int missing = 0;

  /// Times the offset was corrected or the mapping restarted.
  int reanchors = 0;

  /// Whether the source's clock has been given up on.
  bool get distrusted => reanchors >= maxReanchors;

  /// Source-clock step from the previous stamped frame to the last one, or -1
  /// when either had no timestamp.
  int lastStepUs = -1;

  /// Arrival time minus mapped capture time of the last frame: how much later
  /// than the fastest delivery it arrived. 0 when it took its arrival time.
  int lastLagUs = 0;

  /// The capture time of a frame stamped [nativeUs] by its source and
  /// delivered at [arrivalUs] (master clock), or null when the frame is out of
  /// order and must be dropped.
  int? stamp(int nativeUs, int arrivalUs) {
    lastStepUs = -1;
    lastLagUs = 0;
    if (nativeUs <= 0) {
      missing++;
      return arrivalUs;
    }
    if (_lastNativeUs > 0) {
      if (nativeUs <= _lastNativeUs) {
        if (_lastNativeUs - nativeUs <= resetJumpUs) {
          outOfOrder++;
          return null;
        }
        // The source's clock restarted. Nothing before it can be compared
        // with anything after it.
        reanchors++;
        _offsetUs = null;
      } else {
        lastStepUs = nativeUs - _lastNativeUs;
      }
    }
    _lastNativeUs = nativeUs;
    if (distrusted) return arrivalUs;

    final d = arrivalUs - nativeUs;
    final offset = _offsetUs;
    if (offset == null || d < offset) {
      _offsetUs = d;
      _windowStartUs = arrivalUs;
      _windowMinLagUs = 0;
      return arrivalUs;
    }
    final lag = d - offset;
    if (lag < _windowMinLagUs) _windowMinLagUs = lag;
    if (arrivalUs - _windowStartUs >= windowUs) {
      if (_windowMinLagUs > maxLagUs) {
        reanchors++;
        _offsetUs = offset + _windowMinLagUs;
        if (distrusted) return arrivalUs;
      }
      _windowStartUs = arrivalUs;
      _windowMinLagUs = d - _offsetUs!;
    }
    lastLagUs = d - _offsetUs!;
    return nativeUs + _offsetUs!;
  }
}
