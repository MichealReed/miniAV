/// Video presentation scheduling: live (latest-wins) and paced (pts-clocked).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart' show visibleForTesting;
import 'package:miniav_tools/miniav_tools.dart'
    show DecodedPixelLayout, YuvColorMatrix;

import 'player_clock.dart';

/// A decoded frame queued for presentation.
///
/// Carries exactly one payload:
///  - [yuv420p] — native software path: tightly packed Y | U | V bytes (the
///    decode worker's relay layout), converted to RGBA on the GPU.
///  - [d3d11SharedHandle] — native hardware path: an NT handle to a shared NV12
///    D3D11 texture (from the MF decoder). The presenter imports it into Dawn
///    and converts NV12→RGBA on the GPU, with no CPU readback of the frame.
///  - [webFrame] — web path: an opaque browser `VideoFrame` (already a
///    displayable surface), presented directly with no conversion.
///
/// [onDone] releases any resource the payload holds ([webFrame]'s `close()`,
/// the MF worker's texture for [d3d11SharedHandle]); the scheduler calls it
/// whenever the frame is presented OR dropped, so nothing leaks. It is null
/// (no-op) for the GC-managed [yuv420p] payload.
class ScheduledVideoFrame {
  const ScheduledVideoFrame({
    required this.ptsUs,
    required this.width,
    required this.height,
    this.yuv420p,
    this.yuvLayout = DecodedPixelLayout.i420,
    this.yuvFullRange = false,
    this.yuvMatrix = YuvColorMatrix.bt601,
    this.d3d11SharedHandle,
    this.webFrame,
    this.onDone,
  });

  final int ptsUs;
  final int width;
  final int height;
  final Uint8List? yuv420p;

  /// Planar layout of [yuv420p] (i420 / i422 / i444 / 10-bit / nv12) so the
  /// presenter picks the right converter; [yuvFullRange] selects the coefficient
  /// set. Ignored for the d3d11/web payloads.
  final DecodedPixelLayout yuvLayout;
  final bool yuvFullRange;

  /// YCbCr matrix of [yuv420p] (bt601 default; bt709 when the bitstream
  /// declared it).
  final YuvColorMatrix yuvMatrix;
  final int? d3d11SharedHandle;
  final Object? webFrame;
  final void Function()? onDone;
}

/// How the player trades latency against smoothness.
enum PlayerLatencyMode {
  /// Latest-wins, NO clock pacing: present each frame as soon as it is
  /// decoded, and when the presenter is busy keep only the NEWEST decoded
  /// frame. Minimal latency, drops beat lag.
  ///
  /// Correct ONLY for a true realtime source whose frames arrive at ~display
  /// cadence and where you always want the freshest frame — a remote-desktop
  /// / video-call feed where the app controls packet timing. **Do NOT use for
  /// a demuxed container stream:** a demuxer delivers a whole fragment (many
  /// frames) at once, and with no clock each burst collapses to ~1–2 presented
  /// frames — visibly choppy at a fraction of the real framerate. Use [paced].
  live,

  /// Pts-clocked: present each frame at its presentation timestamp against
  /// the [PlayerClock] (frames hopelessly late are dropped when a newer one
  /// is queued). Smooth playback at the source's true framerate.
  ///
  /// The right mode for ANY container source — files, VOD, AND live/broadcast
  /// streams (which are inherently bursty because they arrive fragment by
  /// fragment). This is the default for [MiniavPlayer.openSource].
  paced,
}

class VideoScheduler {
  VideoScheduler({
    required this.mode,
    required PlayerClock clock,
    required Future<void> Function(ScheduledVideoFrame frame) present,
    this.lateDropThresholdUs = 50000,
    this.maxQueuedFrames = 8,
    void Function(Object error, StackTrace stack)? onPresentError,
  }) : _clock = clock,
       _present = present,
       _onPresentError = onPresentError;

  final PlayerLatencyMode mode;
  final PlayerClock _clock;
  final Future<void> Function(ScheduledVideoFrame frame) _present;
  final void Function(Object, StackTrace)? _onPresentError;

  /// Paced mode: a frame older than `mediaTime - lateDropThresholdUs` is
  /// dropped when a newer frame is queued behind it.
  final int lateDropThresholdUs;

  /// Paced mode: bound on decoded-but-unpresented frames; overflow drops
  /// the oldest.
  final int maxQueuedFrames;

  final List<ScheduledVideoFrame> _queue = [];
  ScheduledVideoFrame? _livePending;
  bool _presenting = false;
  bool _disposed = false;
  Timer? _timer;

  // --- stats -----------------------------------------------------------------
  int presentedCount = 0;

  /// Live mode: frames replaced by a newer one before they could present.
  int droppedSupersededCount = 0;

  /// Paced mode: frames dropped for being hopelessly late / queue overflow.
  int droppedLateCount = 0;

  /// Number of frames waiting (excluding the one currently presenting).
  int get queueDepth => mode == PlayerLatencyMode.live
      ? (_livePending != null ? 1 : 0)
      : _queue.length;

  /// Frames accepted but not yet accounted for, INCLUDING the one whose
  /// present is in flight. [queueDepth] deliberately excludes that one (it is
  /// the decode-ahead backpressure signal); end-of-stream needs it, or the
  /// tail reads as shown while it is still on its way to the screen.
  int get pendingCount => queueDepth + (_presenting ? 1 : 0);

  /// Every frame this scheduler has finished with — presented or dropped.
  /// Its increments are the definition of progress for [waitUntilPresented].
  int get _settledCount =>
      presentedCount + droppedSupersededCount + droppedLateCount;

  /// Paced mode only: the head frame's presentation time has not arrived yet,
  /// so no progress is EXPECTED — waiting is what pacing means. An unanchored
  /// clock reads as not-waiting (nothing will ever be presented then, which is
  /// a real stall), and so does a PAUSED one: a frozen media time never reaches
  /// the head pts, so waiting on it is a stall, not pacing.
  bool get _waitingOnClock {
    if (mode != PlayerLatencyMode.paced ||
        _presenting ||
        _queue.isEmpty ||
        _clock.isPaused) {
      return false;
    }
    final now = _clock.mediaTimeUs();
    return now != null && _queue.first.ptsUs > now;
  }

  /// Wait until every submitted frame has been presented (or dropped), so a
  /// caller can say the queue really reached the screen.
  ///
  /// Bounded three ways, because the failure shapes need different bounds:
  /// [stallTimeout] catches a wedged presenter quickly but does not run while
  /// paced frames are legitimately waiting on the media clock (a low-framerate
  /// tail would otherwise be cut short) — a paused clock is NOT such a wait, so
  /// pausing mid-wait gives up on the stall bound rather than pacing out the
  /// absolute one. [shouldAbort] drops the wait when the caller's own state
  /// moved on (pause / seek / close), so a caller that can make the queue
  /// drainable again is not held here meanwhile. [maxWait] is the absolute
  /// backstop. Returns false when it gave up with frames still pending.
  Future<bool> waitUntilPresented({
    Duration stallTimeout = const Duration(seconds: 2),
    Duration maxWait = const Duration(seconds: 30),
    bool Function()? shouldAbort,
  }) async {
    var lastSettled = _settledCount;
    final stall = Stopwatch()..start();
    final total = Stopwatch()..start();
    while (!_disposed && pendingCount > 0) {
      if (shouldAbort != null && shouldAbort()) return false;
      await Future<void>.delayed(const Duration(milliseconds: 4));
      if (_settledCount != lastSettled) {
        lastSettled = _settledCount;
        stall.reset();
      } else if (_waitingOnClock) {
        stall.reset();
      } else if (stall.elapsed > stallTimeout) {
        return false;
      }
      if (total.elapsed > maxWait) return false;
    }
    return pendingCount == 0;
  }

  /// Submit a decoded frame. Never blocks; drop policy per [mode].
  void submit(ScheduledVideoFrame frame) {
    if (_disposed) return;
    // Video-only streams anchor the clock here; when audio exists it
    // anchors first (the player feeds audio before video decode finishes
    // its first frame in practice, and re-anchoring is harmless).
    if (!_clock.isAnchored) _clock.anchor(frame.ptsUs);

    if (mode == PlayerLatencyMode.live) {
      if (_presenting) {
        final superseded = _livePending;
        if (superseded != null) {
          droppedSupersededCount++;
          superseded.onDone?.call();
        }
        _livePending = frame;
      } else {
        _presentNow(frame);
      }
      return;
    }

    // Paced: keep the queue pts-ordered (packets normally arrive in order,
    // so this is an append).
    var i = _queue.length;
    while (i > 0 && _queue[i - 1].ptsUs > frame.ptsUs) {
      i--;
    }
    _queue.insert(i, frame);
    while (_queue.length > maxQueuedFrames) {
      _queue.removeAt(0).onDone?.call();
      droppedLateCount++;
    }
    pump();
  }

  /// Drop everything not yet presented (flush/seek), releasing each payload.
  void clear() {
    _timer?.cancel();
    _timer = null;
    for (final f in _queue) {
      f.onDone?.call();
    }
    _queue.clear();
    _livePending?.onDone?.call();
    _livePending = null;
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  /// Paced-mode pump: present the head frame when its time has come, or
  /// arm a timer for it. Public for tests (fake clocks can't drive real
  /// timers).
  @visibleForTesting
  void pump() {
    if (_disposed || _presenting || _queue.isEmpty) return;
    final now = _clock.mediaTimeUs();
    if (now == null) return;
    // Late frames: skip ahead when something newer is already queued —
    // presenting a stale frame just adds latency.
    while (_queue.length > 1 && _queue.first.ptsUs < now - lateDropThresholdUs) {
      _queue.removeAt(0).onDone?.call();
      droppedLateCount++;
    }
    final head = _queue.first;
    final waitUs = head.ptsUs - now;
    if (waitUs <= 0) {
      _queue.removeAt(0);
      _presentNow(head);
      return;
    }
    _timer?.cancel();
    _timer = Timer(Duration(microseconds: waitUs), pump);
  }

  void _presentNow(ScheduledVideoFrame frame) {
    _presenting = true;
    _present(frame).then((_) {
      presentedCount++;
    }).catchError((Object e, StackTrace s) {
      _onPresentError?.call(e, s);
    }).whenComplete(() {
      // Release the payload (e.g. close a browser VideoFrame) once presented.
      frame.onDone?.call();
      _presenting = false;
      if (_disposed) return;
      if (mode == PlayerLatencyMode.live) {
        final pending = _livePending;
        _livePending = null;
        if (pending != null) _presentNow(pending);
      } else {
        pump();
      }
    });
  }
}
