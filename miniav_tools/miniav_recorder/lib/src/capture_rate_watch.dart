/// Notices a capture source running below its configured frame rate.
/// Pure timing policy — no I/O — so it is unit-testable.
library;

/// A change in whether a source keeps its configured rate.
enum CaptureRateChange {
  /// It has delivered below its rate for [CaptureRateWatch.sustainUs].
  dropped,

  /// It is back near its rate.
  recovered,
}

/// Watches the capture times of a source that delivers continuously, such as
/// a camera, for a sustained shortfall against its configured rate.
///
/// A webcam in a dim room lengthens its exposure past the frame interval: a
/// Logitech C922 set to 30 fps delivered 24, in alternating 32 and 48 ms
/// steps. The recorder fills the missing slots with duplicates, which plays
/// back as stutter, and nothing said why. The rate is measured over windows
/// of [windowUs]; a shortfall counts once it lasts [sustainUs], so a brief
/// dip does not report, and a window holding a step longer than [stallUs] is
/// a stall or a pause, which is not what this is about, and is skipped.
///
/// Not for screen capture, which delivers a frame only when the picture
/// changes.
class CaptureRateWatch {
  CaptureRateWatch({
    required this.nominalFps,
    this.windowUs = 2500000,
    this.sustainUs = 10000000,
    this.stallUs = 500000,
  });

  /// The rate the source was configured for.
  final double nominalFps;

  final int windowUs;
  final int sustainUs;
  final int stallUs;

  /// Below this share of [nominalFps] a window is short.
  static const dropShare = 0.9;

  /// At or above this share a window is back near the rate.
  static const recoverShare = 0.95;

  /// The rate of the last whole window, 0 before the first.
  double lastFps = 0;

  /// Whether the source is currently reported as below its rate.
  bool get low => _low;

  int _windowStartUs = -1;
  int _prevUs = -1;
  int _steps = 0;
  bool _stalled = false;
  int _shortSinceUs = -1;
  bool _low = false;

  /// Feeds the capture time of the next frame, in microseconds. Returns the
  /// change this frame completes, if any.
  CaptureRateChange? frame(int captureUs) {
    if (nominalFps <= 0) return null;
    if (_windowStartUs < 0 || captureUs <= _prevUs) {
      // The first frame, or a clock that went back: start over from here.
      _windowStartUs = captureUs;
      _prevUs = captureUs;
      _steps = 0;
      _stalled = false;
      return null;
    }
    if (captureUs - _prevUs > stallUs) _stalled = true;
    _prevUs = captureUs;
    _steps++;
    final elapsed = captureUs - _windowStartUs;
    if (elapsed < windowUs) return null;

    final fps = _steps * 1e6 / elapsed;
    final stalled = _stalled;
    _windowStartUs = captureUs;
    _steps = 0;
    _stalled = false;
    if (stalled) {
      _shortSinceUs = -1;
      return null;
    }
    lastFps = fps;
    if (fps < nominalFps * dropShare) {
      if (_shortSinceUs < 0) _shortSinceUs = captureUs - elapsed;
      if (!_low && captureUs - _shortSinceUs >= sustainUs) {
        _low = true;
        return CaptureRateChange.dropped;
      }
      return null;
    }
    _shortSinceUs = -1;
    if (_low && fps >= nominalFps * recoverShare) {
      _low = false;
      return CaptureRateChange.recovered;
    }
    return null;
  }
}
