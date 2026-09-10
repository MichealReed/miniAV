/// The re-acquire machine, driven against the real [CaptureRecovery] rather
/// than a simulation of it.
///
/// The occurrence these exist for (session f2bb70b3): a WGC capture item
/// closed 54 minutes into a 95-minute session. The machine was fine — an
/// independent capture of the same desktop ran for the remaining 41 minutes
/// and both audio tracks kept flowing — but the recorder had no way to hear
/// that its target had gone, so it produced a valid, playable, 41-minute-short
/// file and reported success.
///
/// Everything below is about the ORDER and the GIVING UP, because that is
/// where a recovery loop goes wrong: releasing a buffer an encode is still
/// reading, restarting onto a target that never came back, retrying a window
/// that cannot return, or quietly capturing something else instead.
library;

import 'dart:async';

import 'package:miniav_recorder/src/capture_recovery.dart';
import 'package:miniav_recorder/src/recorder_source.dart';
import 'package:test/test.dart';

/// A recorder-shaped harness: a clock the test advances by hand, an ordered
/// log of every callback, and a re-acquire that answers however the test says.
class _Harness {
  _Harness({
    this.policy = VideoCaptureLossPolicy.reacquire,
    this.reacquireLimit,
    bool hasReacquirePath = true,
    bool hasHardPath = false,
  }) {
    recovery = CaptureRecovery(
      label: 'screen[test]',
      policy: policy,
      reacquireLimit: reacquireLimit,
      nowUs: () => clockUs,
      log: (m, {bool severe = false}) => logs.add(m),
      quiesce: () async {
        calls.add('quiesce');
        await Future<void>.delayed(Duration.zero);
      },
      restart: () async {
        calls.add('restart');
        if (restartThrows) throw StateError('restart refused');
      },
      reacquire: hasReacquirePath
          ? () async {
              calls.add('reacquire');
              // Every attempt takes some wall time on the real clock.
              clockUs += 100000;
              if (reacquireThrows) throw StateError('display mid-transition');
              return targetBack;
            }
          : null,
      hardReacquire: hasHardPath
          ? () async {
              calls.add('hardReacquire');
              clockUs += 500000; // a rebuild is not free
              if (hardThrows) throw StateError('device still removed');
              return hardBack;
            }
          : null,
      // No real waiting: the delay is where a test would otherwise spend
      // seconds, and the backoff VALUES are asserted separately below.
      delay: (d) async {
        delays.add(d);
        clockUs += d.inMicroseconds;
        await Future<void>.delayed(Duration.zero);
      },
    );
  }

  final VideoCaptureLossPolicy policy;
  final Duration? reacquireLimit;
  late final CaptureRecovery recovery;

  int clockUs = 0;
  bool targetBack = true;
  bool reacquireThrows = false;
  bool restartThrows = false;
  bool hardBack = true;
  bool hardThrows = false;

  final List<String> calls = [];
  final List<String> logs = [];
  final List<Duration> delays = [];

  /// Let the recovery loop run to a resting point.
  Future<void> settle([int turns = 40]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  group('a lost target is re-acquired into the same recording', () {
    test('quiesce runs before re-acquire, and re-acquire before restart',
        () async {
      // The order is the whole safety property: releasing the dead capture's
      // buffer before in-flight encodes have finished frees memory something
      // is still reading, and restarting before the target is back attaches
      // the frame callback to nothing.
      final h = _Harness();
      h.recovery.noteLost(7);
      await h.settle();

      expect(h.calls, ['quiesce', 'reacquire', 'restart']);
      expect(h.recovery.lost, isFalse);
      expect(h.recovery.ended, isFalse);
      expect(h.recovery.recoveryCount, 1);
    });

    test('keeps retrying while the target is still away', () async {
      final h = _Harness()..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(30);

      expect(h.recovery.lost, isTrue, reason: 'still out');
      expect(h.recovery.ended, isFalse, reason: 'no limit — never gives up');
      expect(h.calls.where((c) => c == 'reacquire').length, greaterThan(3));
      expect(h.calls, isNot(contains('restart')),
          reason: 'nothing may restart onto a target that is not back');

      // It comes back.
      h.targetBack = true;
      await h.settle(20);
      expect(h.recovery.lost, isFalse);
      expect(h.calls.last, 'restart');
    });

    test('a throwing re-acquire is a retry, not a fault', () async {
      // A display mid-transition refuses in several different ways; none of
      // them mean the display is gone for good.
      final h = _Harness()..reacquireThrows = true;
      h.recovery.noteLost(7);
      await h.settle(30);

      expect(h.recovery.ended, isFalse);
      expect(h.calls.where((c) => c == 'reacquire').length, greaterThan(3));

      h.reacquireThrows = false;
      await h.settle(20);
      expect(h.recovery.lost, isFalse);
      expect(h.recovery.recoveryCount, 1);
    });

    test('the outage is measured and reported, not swallowed', () async {
      final h = _Harness()..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(20);

      // Still out: the summary must already account for the open outage, or a
      // recording that never recovers reports 0 s missing.
      expect(h.recovery.totalLostUs, greaterThan(0));
      expect(h.recovery.summary, contains('lost 1 time(s)'));

      h.targetBack = true;
      await h.settle(20);
      final s = h.recovery.summary!;
      expect(s, contains('re-acquired 1'));
      // Not 'of video': this summary is now written for a microphone as
      // often as for a display.
      expect(s, contains('missing from this track'));
    });

    test('a second loss is counted, and both outages add up', () async {
      final h = _Harness();
      h.recovery.noteLost(7);
      await h.settle();
      final afterFirst = h.recovery.totalLostUs;

      h.recovery.noteLost(7);
      await h.settle();

      expect(h.recovery.lossCount, 2);
      expect(h.recovery.recoveryCount, 2);
      expect(h.recovery.totalLostUs, greaterThan(afterFirst));
    });
  });

  group('giving up is explicit, and never silent', () {
    test('no re-acquire path ends the track immediately', () async {
      // A window whose HWND was destroyed. Retrying asks a question that can
      // only ever be answered no.
      final h = _Harness(hasReacquirePath: false);
      h.recovery.noteLost(7);
      await h.settle();

      expect(h.recovery.ended, isTrue);
      expect(h.calls, isEmpty, reason: 'nothing is attempted');
      expect(h.logs.join(' '), contains('ENDED early'));
      expect(h.recovery.summary, contains('did not return'));
    });

    test('endTrack policy does not attempt a re-acquire it could have made',
        () async {
      final h = _Harness(policy: VideoCaptureLossPolicy.endTrack);
      expect(h.recovery.canReacquire, isFalse);
      h.recovery.noteLost(7);
      await h.settle();

      expect(h.recovery.ended, isTrue);
      expect(h.calls, isEmpty);
    });

    test('reacquireLimit ends the track once it expires', () async {
      final h = _Harness(reacquireLimit: const Duration(seconds: 3))
        ..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(60);

      expect(h.recovery.ended, isTrue);
      expect(h.logs.join(' '), contains('reacquireLimit expired'));
      // It gave up rather than looping forever, but it did try first.
      expect(h.calls.where((c) => c == 'reacquire').length, greaterThan(0));
    });

    test('a limit that has not expired keeps trying', () async {
      final h = _Harness(reacquireLimit: const Duration(hours: 1))
        ..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(30);
      expect(h.recovery.ended, isFalse);
    });

    test('cancel stops the loop, and a stopped recording reports nothing new',
        () async {
      final h = _Harness()..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(10);
      final attemptsAtCancel = h.calls.where((c) => c == 'reacquire').length;

      h.recovery.cancel();
      await h.settle(30);

      expect(h.calls.where((c) => c == 'reacquire').length, attemptsAtCancel,
          reason: 'a cancelled recovery makes no further attempts');
    });
  });

  group('a loss the cheap repair cannot fix escalates to a rebuild', () {
    // A closed capture item and a reset GPU device look identical from here —
    // the target stops producing — and nothing at this level tells them apart.
    // So the loop does not guess: it tries the cheap repair, and escalates
    // when that keeps failing.

    test('the cheap repair is tried first, and alone, while it might work',
        () async {
      final h = _Harness(hasHardPath: true);
      h.recovery.noteLost(7);
      await h.settle();

      expect(h.calls, ['quiesce', 'reacquire', 'restart']);
      expect(h.calls, isNot(contains('hardReacquire')),
          reason: 'rebuilding the whole GPU stage for a display that came '
              'straight back would be a needless outage');
      expect(h.recovery.hardRecoveryCount, 0);
    });

    test('after enough soft failures it rebuilds, and recovers', () async {
      // A device reset: re-configuring lands on a device that no longer
      // exists, so the soft path can never succeed.
      final h = _Harness(hasHardPath: true)..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(40);

      expect(h.calls, contains('hardReacquire'));
      expect(h.recovery.lost, isFalse, reason: 'the rebuild recovered it');
      expect(h.recovery.hardRecoveryCount, 1);
      expect(h.recovery.recoveryCount, 1);
      // The rebuild installs a new startFn, so the restart that follows it
      // must be the next thing to happen — not another soft attempt against
      // the stage that was just replaced.
      final hardAt = h.calls.indexOf('hardReacquire');
      expect(h.calls.sublist(hardAt), ['hardReacquire', 'restart'],
          reason: 'restart uses the NEW startFn the rebuild installed, and '
              'nothing may run between them');
    });

    test('escalation waits for the configured number of soft failures', () {
      final h = _Harness(hasHardPath: true);
      expect(h.recovery.escalated, isFalse);
      expect(CaptureRecovery.softAttemptsBeforeHard, greaterThan(0));
    });

    test('a soft path that throws still counts toward escalating', () async {
      // A re-configure onto a removed device throws rather than returning
      // false; if only the false answers counted, a device reset would retry
      // the cheap repair forever.
      final h = _Harness(hasHardPath: true)..reacquireThrows = true;
      h.recovery.noteLost(7);
      await h.settle(40);

      expect(h.calls, contains('hardReacquire'));
      expect(h.recovery.hardRecoveryCount, 1);
    });

    test('a rebuild that cannot match the container is not retried forever '
        'as a success', () async {
      // rebuildVideoStage returns false when the new stage would not match
      // what the file already declares. That is a retry, never a splice.
      final h = _Harness(hasHardPath: true)
        ..targetBack = false
        ..hardBack = false;
      h.recovery.noteLost(7);
      await h.settle(40);

      expect(h.calls.where((c) => c == 'hardReacquire').length, greaterThan(1));
      expect(h.calls, isNot(contains('restart')));
      expect(h.recovery.lost, isTrue);
      expect(h.recovery.recoveryCount, 0);
    });

    test('a throwing rebuild keeps trying rather than ending the track',
        () async {
      final h = _Harness(hasHardPath: true)
        ..targetBack = false
        ..hardThrows = true;
      h.recovery.noteLost(7);
      await h.settle(40);

      expect(h.recovery.ended, isFalse, reason: 'Dawn may still be recovering');
      expect(h.calls.where((c) => c == 'hardReacquire').length, greaterThan(1));

      h.hardThrows = false;
      await h.settle(20);
      expect(h.recovery.lost, isFalse);
      expect(h.recovery.hardRecoveryCount, 1);
    });

    test('with no hard path available the loop never claims to have one',
        () async {
      final h = _Harness()..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(40);
      expect(h.recovery.escalated, isFalse);
      expect(h.calls, isNot(contains('hardReacquire')));
      expect(h.recovery.hardRecoveryCount, 0);
    });

    test('the summary distinguishes a device reset from a lost target',
        () async {
      final h = _Harness(hasHardPath: true)..targetBack = false;
      h.recovery.noteLost(7);
      await h.settle(40);
      expect(h.recovery.summary, contains('GPU stage rebuilt'));

      final soft = _Harness();
      soft.recovery.noteLost(7);
      await soft.settle();
      expect(soft.recovery.summary, isNot(contains('GPU stage rebuilt')));
    });
  });

  group('the backoff is quick first, then cheap', () {
    test('early attempts are sub-second, later ones settle to a slow poll',
        () {
      // A display coming back from Win+P or a lock is usually there within a
      // second; after that the point is to cost almost nothing. The unfixed
      // code did ~30 failed ENCODES a second for 41 minutes.
      expect(CaptureRecovery.backoffFor(0), const Duration(milliseconds: 250));
      expect(CaptureRecovery.backoffFor(1), const Duration(milliseconds: 500));
      expect(CaptureRecovery.backoffFor(4), const Duration(seconds: 4));
      expect(CaptureRecovery.backoffFor(5), const Duration(seconds: 5));
      expect(CaptureRecovery.backoffFor(500), const Duration(seconds: 5),
          reason: 'never faster than the resting interval, however long it '
              'has been out');
    });

    test('the loop actually waits before its first attempt', () async {
      // Attempting synchronously on the loss would race the platform's own
      // teardown, which is still unwinding when the callback fires.
      final h = _Harness();
      h.recovery.noteLost(7);
      await h.settle();
      expect(h.delays.first, const Duration(milliseconds: 250));
      expect(h.calls.first, 'quiesce');
    });
  });

  _watchdogTests();
  _lateBindingTests();

  test('a capture that never fails reports nothing at all', () async {
    final h = _Harness();
    expect(h.recovery.summary, isNull);
    expect(h.recovery.lost, isFalse);
    expect(h.recovery.ended, isFalse);
    expect(h.recovery.totalLostUs, 0);
  });
}

// ---------------------------------------------------------------------------
// The watchdog: catching a capture that died without anyone saying so.
// ---------------------------------------------------------------------------

const _us = 1000000;

void _watchdogTests() {
  CaptureWatchdog wd({int fps = 30, bool idleFill = true}) => CaptureWatchdog(
        frameIntervalUs: fps > 0 ? _us ~/ fps : 0,
        idleFillActive: idleFill,
      );

  group('the watchdog does not fire on a healthy capture', () {
    test('the OUTPUT test never fires while duplicates keep arriving', () {
      // Screen capture delivers no frames at all while nothing moves, so
      // watching arrivals alone would call every idle desktop a dead capture.
      // Watching packets does not — the duplicator keeps emitting them.
      //
      // Read this narrowly. It says the duplicator is alive. It says NOTHING
      // about the capture, which is why sourceWentSilent exists: a frozen
      // capture produces this exact pattern for as long as you let it.
      final w = wd();
      for (final minutes in [1, 10, 60]) {
        expect(
          w.shouldDeclareLost(
            nowUs: minutes * 60 * _us,
            lastPacketUs: minutes * 60 * _us - 100000, // a duplicate 100ms ago
            errorsSincePacket: 0,
            startedAtUs: 0,
          ),
          isFalse,
          reason: 'the duplicator is alive at minute $minutes',
        );
      }
    });

    test('a brief encode hiccup is not a loss', () {
      final w = wd();
      expect(
        w.shouldDeclareLost(
          nowUs: 2 * _us,
          lastPacketUs: 0,
          errorsSincePacket: 3,
          startedAtUs: 0,
        ),
        isFalse,
        reason: '2s of trouble is under the silence window',
      );
    });

    test('a track that has not produced its first packet yet is given time',
        () {
      // startedAtUs is deliberately NOT zero: a capture can begin well into a
      // session (a re-acquire restarts this clock), and measuring its grace
      // period from the master clock's origin instead of from ITS start would
      // condemn every such track on its first tick. A zero start hides that.
      final w = wd();
      const startedAt = 600 * _us;
      expect(
        w.shouldDeclareLost(
          nowUs: startedAt + 1 * _us,
          lastPacketUs: -1,
          errorsSincePacket: 0,
          startedAtUs: startedAt,
        ),
        isFalse,
        reason: 'an encoder still opening has produced nothing and is fine',
      );
      expect(
        w.shouldDeclareLost(
          nowUs: startedAt + 10 * _us,
          lastPacketUs: -1,
          errorsSincePacket: 0,
          startedAtUs: startedAt,
        ),
        isTrue,
        reason: 'the grace period is not unlimited',
      );
    });
  });

  group('the watchdog fires when output stops', () {
    test('silence past the window with idle fill active is a loss', () {
      final w = wd();
      expect(
        w.shouldDeclareLost(
          nowUs: 5 * _us,
          lastPacketUs: 0,
          errorsSincePacket: 0,
          startedAtUs: 0,
        ),
        isTrue,
        reason: 'the duplicator should have emitted ~150 packets by now',
      );
    });

    test('a capture that never produced a first packet is eventually a loss',
        () {
      final w = wd();
      expect(
        w.shouldDeclareLost(
          nowUs: 610 * _us,
          lastPacketUs: -1,
          errorsSincePacket: 0,
          startedAtUs: 600 * _us,
        ),
        isTrue,
        reason: 'measured from capture start when there is no packet yet',
      );
    });

    test('without idle fill it waits for a FAILURE, never for silence alone',
        () {
      // idleFramePolicy.none makes silence indistinguishable from a static
      // screen: the source is allowed to deliver nothing for minutes. Firing
      // on that would put a periodic hitch into every static recording.
      final w = wd(idleFill: false);
      expect(
        w.shouldDeclareLost(
          nowUs: 600 * _us,
          lastPacketUs: 0,
          errorsSincePacket: 0,
          startedAtUs: 0,
        ),
        isFalse,
        reason: 'ten minutes of a legitimately static screen',
      );
      expect(
        w.shouldDeclareLost(
          nowUs: 600 * _us,
          lastPacketUs: 0,
          errorsSincePacket: 1,
          startedAtUs: 0,
        ),
        isTrue,
        reason: 'work attempted and failed is the unambiguous signal',
      );
    });
  });

  group('the silence window scales with the frame rate', () {
    test('a slow capture gets a proportionally longer window', () {
      // At 1 fps, six intervals is six seconds; a 3-second floor would call a
      // perfectly healthy 1 fps capture dead.
      final slow = wd(fps: 1);
      expect(slow.silenceThresholdUs, 6 * _us);
      expect(
        slow.shouldDeclareLost(
          nowUs: 4 * _us,
          lastPacketUs: 0,
          errorsSincePacket: 0,
          startedAtUs: 0,
        ),
        isFalse,
      );
    });

    test('a fast capture is floored, not scaled down to nothing', () {
      // At 120 fps six intervals is 50ms — far too tight to survive an
      // ordinary GC pause or a busy encoder.
      final fast = wd(fps: 120);
      expect(fast.silenceThresholdUs, CaptureWatchdog.minSilenceUs);
    });

    test('a source-controlled rate still gets the floor', () {
      expect(wd(fps: 0).silenceThresholdUs, CaptureWatchdog.minSilenceUs);
    });
  });

  group('the source-silence window', () {
    // The blind spot the output test cannot cover. With idle fill on — the
    // screen default — a capture that dies goes on producing packets at the
    // full frame rate, because the duplicator re-encodes its last frame
    // forever. Output looks perfect; the picture is frozen.
    test('a recent frame is healthy', () {
      expect(
        wd().sourceWentSilent(
            nowUs: 9 * _us, lastSourceFrameUs: 5 * _us, startedAtUs: 0),
        isFalse,
      );
    });

    test('silence past the window is not', () {
      expect(
        wd().sourceWentSilent(
            nowUs: 16 * _us, lastSourceFrameUs: 5 * _us, startedAtUs: 0),
        isTrue,
      );
    });

    test('a capture that never delivered anything is judged from the start',
        () {
      // Otherwise a source that produces nothing from the very first frame is
      // the one case that never gets caught.
      final w = wd();
      expect(
        w.sourceWentSilent(
            nowUs: 5 * _us, lastSourceFrameUs: -1, startedAtUs: 0),
        isFalse,
        reason: 'still inside the window',
      );
      expect(
        w.sourceWentSilent(
            nowUs: 30 * _us, lastSourceFrameUs: -1, startedAtUs: 0),
        isTrue,
      );
    });

    test('nothing is judged before the capture has started', () {
      expect(
        wd().sourceWentSilent(
            nowUs: 999 * _us, lastSourceFrameUs: -1, startedAtUs: -1),
        isFalse,
      );
    });

    test('the window is far longer than the output window', () {
      // They answer different questions. Output silence is unambiguous;
      // source silence is what a still desktop looks like.
      final w = wd();
      expect(w.sourceSilenceThresholdUs,
          greaterThan(w.silenceThresholdUs * 3));
    });

    test('each unproductive declaration doubles the wait, up to a cap', () {
      // What keeps the false positive cheap: a genuinely static screen trips
      // the window, gets re-acquired, still delivers nothing — and each
      // pointless attempt buys twice as long before the next.
      final w = wd();
      expect(w.sourceSilenceThresholdUs, CaptureWatchdog.minSourceSilenceUs);
      w.widenSourceSilence();
      expect(w.sourceSilenceThresholdUs,
          CaptureWatchdog.minSourceSilenceUs * 2);
      for (var i = 0; i < 20; i++) {
        w.widenSourceSilence();
      }
      expect(w.sourceSilenceThresholdUs, CaptureWatchdog.maxSourceSilenceUs,
          reason: 'capped, not unbounded');
    });

    test('a frame arriving earns the short window back', () {
      // A real death after a recovery has to be caught in ten seconds again,
      // not sixty.
      final w = wd();
      for (var i = 0; i < 5; i++) {
        w.widenSourceSilence();
      }
      expect(w.sourceSilenceThresholdUs,
          greaterThan(CaptureWatchdog.minSourceSilenceUs));
      w.noteSourceAlive();
      expect(w.sourceSilenceThresholdUs, CaptureWatchdog.minSourceSilenceUs);
    });
  });
}

// ---------------------------------------------------------------------------
// The seam between a track and its recovery. Both halves of this were wrong at
// some point during the build, and neither showed up in any other test.
// ---------------------------------------------------------------------------
void _lateBindingTests() {
  group('lateBound keeps presence and freshness separate', () {
    test('no path at all stays null, so the track can still end', () {
      // An always-non-null wrapper makes canReacquire true for a window
      // target, and "end the track and say so" becomes a silent forever-loop.
      expect(CaptureRecovery.lateBound(() => null), isNull);
    });

    test('a path that exists is read on every call, not captured once',
        () async {
      // A rebuild REPLACES the re-acquire function along with the capture
      // context. A closure holding the original would keep re-configuring a
      // context that has been destroyed.
      var current = 'first';
      final bound = CaptureRecovery.lateBound(() => () async {
            current = '$current-called';
            return true;
          });
      expect(bound, isNotNull);

      var swapped = false;
      final rebound = CaptureRecovery.lateBound(() =>
          swapped ? () async => true : () async => false);
      expect(await rebound!(), isFalse);
      swapped = true;
      expect(await rebound(), isTrue,
          reason: 'the replacement must be the one that runs');

      await bound!();
      expect(current, 'first-called');
    });

    test('a path that disappears after construction answers false, not throw',
        () {
      ReacquireFn? fn = () async => true;
      final bound = CaptureRecovery.lateBound(() => fn);
      fn = null;
      expect(bound!(), completion(isFalse));
    });
  });
}
