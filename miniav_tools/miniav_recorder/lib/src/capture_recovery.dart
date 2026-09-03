/// Re-acquiring a capture target that disappeared mid-recording.
///
/// **The occurrence this exists for** (miniav_recorder 0.5.9, session
/// f2bb70b3): a Windows Graphics Capture item closed 54 minutes into a
/// 95-minute session. Nothing was wrong with the machine — an independent
/// capture of the same desktop stayed connected for the remaining 41 minutes
/// and both audio tracks kept flowing — but the recorder never learned its
/// target had gone. It re-encoded the dead capture buffer at the frame rate
/// for the rest of the session and reported success at stop. One session in
/// six.
///
/// **Why re-acquire rather than report.** The output of a lost capture is a
/// file that is valid, playable, and short. For a paid usability session that
/// is not a partial result, it is a void one: the tester's time is spent, the
/// build has moved on, and the study window has closed. A few seconds of
/// frozen picture is a far cheaper outcome than losing the tail, so the
/// default absorbs the gap and carries on in the same file.
///
/// **What this is not.** Nothing here substitutes a different target for the
/// one that went away. A recorder that quietly starts capturing something
/// else has changed what the file is a recording of, and no caller can tell
/// from the output that it happened. If the original never returns, the video
/// track ends and [summary] says so.
library;

import 'dart:async';
import 'dart:math' as math;

import 'recorder_source.dart' show VideoCaptureLossPolicy;

/// Rebuild the capture target. `true` when it came back; `false` when it is
/// simply not there yet, which is a retry rather than a fault. Throwing is
/// also a retry — a display mid-transition refuses in several different ways
/// and none of them are worth distinguishing.
typedef ReacquireFn = Future<bool> Function();

/// Release everything tied to the capture that died, once in-flight work that
/// might still be reading it has drained.
typedef QuiesceFn = Future<void> Function();

/// Re-attach the frame callback to the freshly acquired target.
typedef RestartFn = Future<void> Function();

/// Rebuild everything a GPU device reset destroys — the graphics device, the
/// screen processor, the encoder and the capture context — leaving the track
/// ready to [RestartFn]. `false` when the rebuild could not be made to match
/// what the container already declares, which is terminal for this track.
typedef HardReacquireFn = Future<bool> Function();

typedef RecoveryLogFn = void Function(String message, {bool severe});

/// Drives one video track's response to losing its capture target.
///
/// Deliberately owns no capture, encoder or platform type: everything it
/// touches arrives as a callback. That is what lets the sequence below — the
/// part where the bugs live — be tested without a display to unplug.
class CaptureRecovery {
  CaptureRecovery({
    required this.label,
    required this.policy,
    required this.reacquireLimit,
    required this.nowUs,
    required this.log,
    required this.quiesce,
    required this.restart,
    this.reacquire,
    this.hardReacquire,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final String label;
  final VideoCaptureLossPolicy policy;

  /// How long to keep trying before ending the track; null = for as long as
  /// the recording runs.
  final Duration? reacquireLimit;

  /// Master-clock microseconds.
  final int Function() nowUs;

  final RecoveryLogFn log;
  final QuiesceFn quiesce;
  final RestartFn restart;

  /// Null when this source has no re-acquire path at all — a camera, or a
  /// window, whose HWND is destroyed rather than temporarily unavailable.
  final ReacquireFn? reacquire;

  /// The escalation, for a loss that re-configuring cannot fix.
  ///
  /// A capture item closing and a GPU device resetting look identical from
  /// here — the target stops producing — but they need different repairs, and
  /// nothing available at this level tells them apart. So this does not guess:
  /// it tries the cheap repair, and when that keeps failing it tries the
  /// expensive one. A re-configure onto a removed device fails immediately, so
  /// the wasted attempts cost about a second and a half, once.
  final HardReacquireFn? hardReacquire;

  /// Soft failures tolerated before escalating. Small on purpose: the whole
  /// point of the soft path is that it is nearly free when it works.
  static const int softAttemptsBeforeHard = 3;

  /// A [ReacquireFn] that reads its target through [read] on every call, for a
  /// caller whose re-acquire function is REPLACED as part of a rebuild.
  ///
  /// Two properties, both of which are easy to get wrong in opposite
  /// directions and neither of which shows up until something breaks in the
  /// field:
  ///
  ///  * a caller with no path at all must get `null` back, not a closure that
  ///    always exists. [canReacquire] reads presence, so an always-non-null
  ///    wrapper turns "end the track and say so" into a silent forever-loop
  ///    against a target that cannot return.
  ///  * a caller that HAS a path must have it read late. Capturing it once
  ///    means a rebuild installs a new capture context while the recovery
  ///    keeps re-configuring the destroyed one.
  static ReacquireFn? lateBound(ReacquireFn? Function() read) {
    if (read() == null) return null;
    return () {
      final fn = read();
      return fn == null ? Future.value(false) : fn();
    };
  }

  final Future<void> Function(Duration) _delay;

  /// A display coming back from Win+P, a lock, a dock or an RDP transition is
  /// usually there within a second, so the first attempts are quick. After
  /// that this settles to a slow poll — roughly 0.2 attempts per second,
  /// against the ~30 failed ENCODES per second the unfixed loop was doing.
  static const List<int> backoffMs = [250, 500, 1000, 2000, 4000];
  static const int intervalMs = 5000;

  static Duration backoffFor(int attempt) => Duration(
        milliseconds:
            attempt < backoffMs.length ? backoffMs[attempt] : intervalMs,
      );

  bool _lost = false;
  bool _ended = false;
  bool _cancelled = false;
  bool _running = false;
  int _attempts = 0;
  int _lostAtUs = -1;
  int _lossCount = 0;
  int _recoveryCount = 0;
  int _hardRecoveries = 0;
  int _softFailures = 0;
  int _totalLostUs = 0;

  /// True while the target is gone and this has not given up. The frame
  /// callback drops anything that arrives while it holds.
  bool get lost => _lost && !_ended;

  /// True once this has stopped trying. Terminal for the video track; every
  /// other track keeps recording.
  bool get ended => _ended;

  int get lossCount => _lossCount;
  int get recoveryCount => _recoveryCount;

  /// Recoveries that needed the whole GPU stage rebuilt, not just the capture
  /// re-configured. Worth separating: it says a device reset happened, which
  /// is a different fault with a different cause from a display being
  /// re-routed.
  int get hardRecoveryCount => _hardRecoveries;

  /// Whether the next attempt will rebuild rather than re-configure.
  bool get escalated =>
      hardReacquire != null && _softFailures >= softAttemptsBeforeHard;

  /// Total microseconds of capture missed, including an outage still open.
  int get totalLostUs =>
      _totalLostUs + (_lost && !_ended && _lostAtUs >= 0 ? nowUs() - _lostAtUs : 0);

  /// Whether a re-acquire will even be attempted.
  bool get canReacquire =>
      reacquire != null && policy == VideoCaptureLossPolicy.reacquire;

  /// The platform says the target is gone. Safe to call from a capture
  /// thread's marshalled callback: it starts the attempt loop and returns.
  void noteLost(int reason) {
    if (_cancelled || _ended || _lost) return;
    _lost = true;
    _lossCount++;
    _lostAtUs = nowUs();
    _attempts = 0;

    if (!canReacquire) {
      log(
        '$label capture target lost (reason $reason) — ending this video '
        'track; other tracks continue.',
        severe: true,
      );
      _end(reacquire == null
          ? 'this target cannot be re-acquired'
          : 'lossPolicy is endTrack');
      return;
    }
    log(
      '$label capture target lost (reason $reason) — re-acquiring; the '
      'encoder and the output file stay open.',
      severe: false,
    );
    unawaited(_loop());
  }

  /// Stop trying. Called when the recording stops.
  void cancel() {
    _cancelled = true;
  }

  Future<void> _loop() async {
    if (_running) return;
    _running = true;
    try {
      while (!_cancelled && !_ended && _lost) {
        await _delay(backoffFor(_attempts));
        if (_cancelled || _ended || !_lost) return;
        if (_limitExpired()) {
          _end('reacquireLimit expired');
          return;
        }
        _attempts++;
        final hard = escalated;
        try {
          if (hard) {
            // The rebuild does its own draining and teardown — it has to, it
            // is replacing the encoder those in-flight encodes are using.
            final rebuilt = await hardReacquire!();
            if (!rebuilt) continue;
            if (_cancelled || _ended) return;
            await restart();
            _hardRecoveries++;
            _recovered();
            return;
          }

          // In-flight encodes may still hold the dead capture's buffers.
          // Nothing is released or re-configured until they have finished.
          await quiesce();
          if (_cancelled || _ended) return;

          final back = await reacquire!();
          if (!back) {
            _softFailures++;
            continue;
          }
          if (_cancelled || _ended) return;

          await restart();
          _recovered();
          return;
        } catch (e) {
          if (!hard) _softFailures++;
          // A throwing re-acquire is still a retry: a display mid-transition
          // refuses in several different ways, none worth telling apart.
          if (_attempts == 1 || _attempts % 12 == 0) {
            log('$label re-acquire attempt $_attempts failed: $e',
                severe: false);
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  bool _limitExpired() {
    final limit = reacquireLimit;
    if (limit == null || _lostAtUs < 0) return false;
    return nowUs() - _lostAtUs >= limit.inMicroseconds;
  }

  void _recovered() {
    final outageUs = _lostAtUs >= 0 ? nowUs() - _lostAtUs : 0;
    _totalLostUs += outageUs;
    _recoveryCount++;
    _lost = false;
    _lostAtUs = -1;
    final attempts = _attempts;
    final wasHard = escalated;
    _attempts = 0;
    _softFailures = 0;
    log(
      '$label capture re-acquired after '
      '${(outageUs / 1000000).toStringAsFixed(1)}s (attempt $attempts'
      '${wasHard ? ', after rebuilding the GPU stage' : ''}) — '
      'recording continues in the same file.',
      severe: false,
    );
  }

  void _end(String why) {
    if (_ended) return;
    if (_lostAtUs >= 0) {
      _totalLostUs += nowUs() - _lostAtUs;
      _lostAtUs = -1;
    }
    _ended = true;
    log(
      '$label video capture ENDED early ($why). The file stays valid and '
      'every other track keeps recording; the video track simply stops here. '
      'A different capture target is not substituted — that would change what '
      'the recording is of, without saying so.',
      severe: true,
    );
  }

  /// One line describing what happened to this capture, or null when nothing
  /// did. Collected by the recorder at stop.
  String? get summary {
    if (_lossCount == 0) return null;
    final lost = (totalLostUs / 1000000).toStringAsFixed(1);
    if (_ended) {
      return '$label: capture target lost $_lossCount time(s) and did not '
          'return — video ends ${lost}s before the recording does';
    }
    final how = _hardRecoveries > 0
        ? ' ($_hardRecoveries needed the GPU stage rebuilt — a device reset, '
            'not just a lost target)'
        : '';
    return '$label: capture target lost $_lossCount time(s), re-acquired '
        '$_recoveryCount$how — ${lost}s of video missing';
  }
}

/// Decides when a capture that is still nominally running has actually gone
/// silent.
///
/// **Why a watchdog at all.** The platform's capture-lost callback is the only
/// signal the recorder has, and it does not fire for every way a capture can
/// die. A removed D3D device is detected inside `TryGetNextFrame`, so it
/// depends on the frame pool raising an event at least once more; if the pool
/// simply stops, nothing is ever notified. This is the catch-all for that, and
/// for whatever the next unknown cause turns out to be — of six field sessions
/// we understand one mechanism, which is not a good ratio to build only
/// specific fixes against.
///
/// **Why it watches OUTPUT, not input.** Screen capture legitimately delivers
/// no frames at all while the screen is static — that is the entire reason the
/// idle duplicator exists — so "no frames arrived" is normal, not a fault.
/// What is NOT normal, with idle fill active, is producing no encoded packet:
/// a static screen still emits duplicates, and a capture whose surfaces have
/// died cannot. So the health signal is the packet, not the frame.
///
/// **The cost asymmetry, deliberately.** Declaring a loss that was not one
/// costs a re-configure: a few hundred milliseconds of frozen picture and a
/// line in the log, with the encoder and the file untouched. Missing a real
/// one costs the rest of the session. That is why this fires on suspicion.
class CaptureWatchdog {
  CaptureWatchdog({
    required this.frameIntervalUs,
    required this.idleFillActive,
  });

  /// Target frame interval; 0 when the source controls the rate.
  final int frameIntervalUs;

  /// Whether [VideoIdleFramePolicy] keeps producing packets on a static
  /// screen. False for `none`, which changes what silence means.
  final bool idleFillActive;

  /// Floor on the silence window with idle fill active. Well above any
  /// plausible encode hiccup, well below the length of a lost session.
  static const int minSilenceUs = 3000000;

  /// Number of frame intervals of silence tolerated before suspicion.
  static const int silentIntervals = 6;

  int get silenceThresholdUs => math.max(
        minSilenceUs,
        frameIntervalUs > 0 ? frameIntervalUs * silentIntervals : 0,
      );

  /// True when the capture should be treated as lost.
  ///
  /// [lastPacketUs] is when this track last produced an encoded packet, or -1
  /// if it never has. [errorsSincePacket] counts encode or GPU-stage failures
  /// since then — the signal that separates a dead capture from a quiet one.
  bool shouldDeclareLost({
    required int nowUs,
    required int lastPacketUs,
    required int errorsSincePacket,
    required int startedAtUs,
  }) {
    // Never before the first packet has had a fair chance: a track that is
    // still opening its encoder has produced nothing yet and is perfectly
    // healthy.
    final since = lastPacketUs >= 0 ? lastPacketUs : startedAtUs;
    if (since < 0) return false;
    if (nowUs - since < silenceThresholdUs) return false;

    // Without idle fill, silence is indistinguishable from a static screen —
    // the source is simply allowed to deliver nothing for minutes. Guessing
    // there would put a periodic hitch into every static recording, so this
    // waits for the one unambiguous signal: work that was attempted and
    // failed.
    if (!idleFillActive) return errorsSincePacket > 0;

    // With idle fill, silence alone is already pathological: a healthy static
    // screen emits a duplicate every frame interval. An error since the last
    // packet only confirms it.
    return true;
  }
}
