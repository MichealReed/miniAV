/// Capture-loss machinery on the track base, where every source now shares it.
///
/// It used to live on the video runtime, because video was the only path with
/// a loss signal wired to it. Nothing in it is about pictures — a
/// subscription, a state machine, two counters — and a recorder that hears a
/// display go away but not the microphone beside it is exactly as silent about
/// the session as one that hears nothing.
///
/// The properties worth pinning are the ones a mixed-audio track depends on:
/// several sources per track, failing independently, each reported under its
/// own name. Driven through a bare [TrackRuntime] so none of it needs a device
/// to unplug.
@TestOn('vm')
library;

import 'dart:async';

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_recorder/src/capture_recovery.dart';
import 'package:miniav_recorder/src/recorder.dart';
import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:test/test.dart';

/// A track that owns nothing but the loss machinery under test.
class _BareTrack extends TrackRuntime {
  _BareTrack() : super(index: 0, label: 'bare');

  bool stopping = false;

  @override
  bool get captureStopping => stopping;

  @override
  Future<void> startCapture(Recorder rec) async {}
  @override
  Future<void> stopCapture() async {}
  @override
  Future<void> flushAndDispatch(Recorder rec) async {}
  @override
  Future<void> dispose() async {}
  @override
  TrackInfo toTrackInfo() =>
      AudioTrackInfo(codec: AudioCodec.aac, sampleRate: 48000, channels: 2);
  @override
  FfmpegEncoderBridge? get encoderBridge => null;
  @override
  TrackChunk toChunk(EncodedPacket pkt) =>
      throw UnimplementedError('not part of this test');
}

/// A platform that can report its own death, and counts who is listening.
class _Source {
  int subscribes = 0;
  int unsubscribes = 0;
  bool unsubscribeThrows = false;
  MiniAVContextLostListener? listener;

  void Function() subscribe(MiniAVContextLostListener l) {
    subscribes++;
    listener = l;
    return () {
      unsubscribes++;
      if (unsubscribeThrows) throw StateError('context already destroyed');
    };
  }

  void die([int reason = -14]) => listener?.call(reason);
}

/// A recovery whose retries are instant but still YIELD.
///
/// `(_) async {}` would not: it completes as a microtask, and a re-acquire
/// that keeps answering false then spins the loop without ever letting a timer
/// run. The test hangs, and it looks like the code under test deadlocked.
/// A zero-duration Future.delayed is a real timer, so the loop is fast and the
/// event loop still turns.
CaptureRecovery _recovery(
  String label, {
  required List<String> log,
  ReacquireFn? reacquire,
  int Function()? nowUs,
}) {
  final r = CaptureRecovery(
    label: label,
    policy: CaptureLossPolicy.reacquire,
    reacquireLimit: null,
    nowUs: nowUs ?? () => 0,
    log: (m, {bool severe = false}) => log.add(m),
    quiesce: () async {},
    restart: () async => log.add('restart:$label'),
    reacquire: reacquire,
    delay: (_) => Future<void>.delayed(Duration.zero),
  );
  // A target that never returns is retried for as long as the recording runs,
  // which here means for as long as the test process does.
  addTearDown(r.cancel);
  return r;
}

void main() {
  group('one track, one source', () {
    test('a platform loss reaches the recovery', () async {
      final t = _BareTrack();
      final src = _Source();
      final log = <String>[];
      final r = _recovery('mic', log: log, reacquire: () async => true);
      t.bindLostSubscription(r, src.subscribe);

      expect(src.subscribes, 1);
      expect(t.recoveries, [r]);
      expect(t.soleRecovery, same(r));
      expect(t.captureLost, isFalse);

      src.die();
      await Future<void>.delayed(Duration.zero);
      expect(t.captureLost, isTrue, reason: 'the loss was heard');

      await Future<void>.delayed(Duration.zero);
      expect(log, contains('restart:mic'));
      expect(t.captureLost, isFalse, reason: 'and recovered');
    });

    test('an onLost hook runs BEFORE the recovery is told', () async {
      // Order is the safety property: whatever the dead capture still owns has
      // to be dropped before the recovery knows anything, so nothing
      // downstream can pick it up again in between.
      //
      // Measured against noteLost and not against the re-acquire, which is a
      // landmark far enough downstream (noteLost only schedules the loop, and
      // the loop's first act is a backoff) that reversing the two would still
      // pass.
      final t = _BareTrack();
      final src = _Source();
      final log = <String>[];
      final r = _recovery('src', log: log, reacquire: () async => true);
      bool? lostWhenReleased;
      t.bindLostSubscription(r, src.subscribe,
          onLost: () => lostWhenReleased = r.lost);

      src.die();
      await Future<void>.delayed(Duration.zero);
      expect(lostWhenReleased, isFalse,
          reason: 'released before the recovery was told, not after');
      await Future<void>.delayed(Duration.zero);
      expect(log, contains('restart:src'), reason: 'and it still recovers');
    });

    test('a loss during teardown is ignored', () async {
      // stopCapture sets this. A recovery started here would outlive the
      // recording and re-acquire a target nothing is going to read.
      final t = _BareTrack();
      final src = _Source();
      final log = <String>[];
      t.bindLostSubscription(
        _recovery('mic', log: log, reacquire: () async => true),
        src.subscribe,
      );

      t.stopping = true;
      src.die();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(t.captureLost, isFalse);
      expect(log, isEmpty);
    });

    test('re-binding drops the previous subscription', () async {
      // The subscription belongs to the capture context, and a rebuild
      // destroys the one it was made against.
      final t = _BareTrack();
      final first = _Source();
      final second = _Source();
      final r = _recovery('screen', log: [], reacquire: () async => true);

      t.bindLostSubscription(r, first.subscribe);
      t.bindLostSubscription(r, second.subscribe);

      expect(first.unsubscribes, 1);
      expect(second.subscribes, 1);
      expect(t.recoveries, hasLength(1), reason: 'still one source');
    });

    test('an unsubscribe that throws does not abort the rebind', () async {
      final t = _BareTrack();
      final first = _Source()..unsubscribeThrows = true;
      final second = _Source();
      final r = _recovery('screen', log: [], reacquire: () async => true);

      t.bindLostSubscription(r, first.subscribe);
      t.bindLostSubscription(r, second.subscribe);

      expect(second.subscribes, 1, reason: 'the new one is still bound');
    });

    test('a source with no platform signal still registers', () {
      // A watchdog, or an explicit call, may declare the loss instead — and
      // captureStatuses has to report the source either way.
      final t = _BareTrack();
      final r = _recovery('camera', log: [], reacquire: () async => true);
      t.bindLostSubscription(r, null);
      expect(t.recoveries, [r]);
      expect(t.captureStatuses, hasLength(1));
    });
  });

  group('one track, two sources that fail independently', () {
    // The mixed-audio case: an HDMI render endpoint dies with the monitor it
    // belongs to while the USB microphone beside it keeps working.
    late _BareTrack t;
    late _Source micSrc;
    late _Source loopSrc;
    late List<String> log;
    late CaptureRecovery mic;
    late CaptureRecovery loop;

    setUp(() {
      t = _BareTrack();
      micSrc = _Source();
      loopSrc = _Source();
      log = [];
      mic = _recovery('mixed mic', log: log, reacquire: () async => true);
      // This one never comes back.
      loop = _recovery('mixed loopback', log: log, reacquire: () async => false);
      t.bindLostSubscription(mic, micSrc.subscribe);
      t.bindLostSubscription(loop, loopSrc.subscribe);
    });

    test('both are registered under their own names', () {
      expect(t.recoveries, hasLength(2));
      expect(
        t.captureStatuses.map((s) => s.label),
        ['mixed mic', 'mixed loopback'],
      );
      expect(t.soleRecovery, isNull,
          reason: '"the" recovery is not a question with an answer here');
    });

    test('one dying leaves the other capturing', () async {
      loopSrc.die();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final byLabel = {for (final s in t.captureStatuses) s.label: s};
      expect(byLabel['mixed loopback']!.lost, isTrue);
      expect(byLabel['mixed mic']!.lost, isFalse);
      expect(byLabel['mixed mic']!.lossCount, 0);
      expect(t.captureLost, isTrue, reason: 'the track has a problem');
    });

    test('each reports its own outage at stop', () async {
      loopSrc.die();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final summaries = t.captureLossSummaries.toList();
      expect(summaries, hasLength(1),
          reason: 'only the source that lost anything has something to say');
      expect(summaries.single, contains('mixed loopback'));
    });

    test('cancelling stops both and unsubscribes both', () {
      t.cancelRecoveries();
      expect(micSrc.unsubscribes, 1);
      expect(loopSrc.unsubscribes, 1);

      micSrc.die();
      loopSrc.die();
      expect(t.captureLost, isFalse);
    });

    test('cancelling twice is safe', () {
      t.cancelRecoveries();
      t.cancelRecoveries();
      expect(micSrc.unsubscribes, 1, reason: 'not unsubscribed again');
    });
  });

  group('captureStatuses', () {
    test('an outage still open counts toward the time missing', () async {
      var clock = 0;
      final t = _BareTrack();
      final src = _Source();
      final r = _recovery('mic',
          log: [], reacquire: () async => false, nowUs: () => clock);
      t.bindLostSubscription(r, src.subscribe);

      src.die();
      await Future<void>.delayed(Duration.zero);
      clock = 4000000;
      await Future<void>.delayed(Duration.zero);

      final s = t.captureStatuses.single;
      expect(s.lost, isTrue);
      expect(s.secondsMissing, closeTo(4.0, 0.001));
      expect(s.healthy, isFalse);
    });

    test('a track with no sources reports nothing rather than null', () {
      // Recorder.captureStatus spreads these, so "no capture to lose" has to
      // be an empty list and not an entry claiming health.
      expect(_BareTrack().captureStatuses, isEmpty);
      expect(_BareTrack().captureLossSummaries, isEmpty);
      expect(_BareTrack().captureLost, isFalse);
    });
  });
}
