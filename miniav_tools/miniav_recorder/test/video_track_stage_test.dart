/// The stage swap, driven against the real [VideoTrackRuntime].
///
/// A GPU device reset removes every D3D11 device on the adapter at once, so
/// recovering one means replacing the encoder, the processor, the capture
/// context and every closure bound to them — in place, while a container that
/// already declared this track's dimensions keeps being written.
///
/// The order is the whole safety property, and none of it needs a GPU: the
/// runtime reaches its capture, its encoder and its buffers through callbacks,
/// so a fake supplies all three and the sequence is fully observable.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_recorder/src/capture_recovery.dart';
import 'package:miniav_recorder/src/recorder.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEncoder implements PlatformEncoder {
  _FakeEncoder(this.log, this.name, {this.extra});

  final List<String> log;
  final String name;
  final Uint8List? extra;
  bool closed = false;
  bool closeThrows = false;
  int keyframeRequests = 0;

  @override
  Future<EncodedPacket?> encode(FrameSource frame) async => null;

  @override
  Future<List<EncodedPacket>> flush() async => const [];

  @override
  Future<void> requestKeyframe() async => keyframeRequests++;

  @override
  CodecExtraData? get extraData => extra == null
      ? null
      : CodecExtraData.video(VideoCodec.h264, extra!);

  @override
  Future<void> close() async {
    log.add('close:$name');
    closed = true;
    if (closeThrows) throw StateError('device removed');
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Everything a track reaches the outside world through, recorded in order.
class _Stage {
  _Stage(this.log, this.name);

  final List<String> log;
  final String name;

  final _FakeEncoder platform = _FakeEncoder([], 'unset');
  late final Encoder encoder;

  bool stopThrows = false;
  bool destroyThrows = false;
  bool started = false;
  int lostSubscriptions = 0;
  int lostUnsubscribes = 0;
  bool unsubscribeThrows = false;
  MiniAVContextLostListener? listener;

  VideoTrackRuntime build({
    int width = 640,
    int height = 480,
    VideoCodec codec = VideoCodec.h264,
    int fpsNum = 30,
    Uint8List? extraData,
    bool withReacquire = true,
  }) {
    final fake = _FakeEncoder(log, name, extra: extraData);
    encoder = Encoder(fake, 'fake');
    _platform = fake;
    return VideoTrackRuntime(
      index: 0,
      label: 'screen[$name]',
      encoder: encoder,
      videoCodec: codec,
      width: width,
      height: height,
      frameRateNum: fpsNum,
      frameRateDen: 1,
      captureCtx: Object(),
      startFn: (cb) async {
        log.add('start:$name');
        started = true;
      },
      stopFn: () async {
        log.add('stop:$name');
        if (stopThrows) throw StateError('context already gone');
      },
      destroyFn: () async {
        log.add('destroy:$name');
        if (destroyThrows) throw StateError('context already gone');
      },
      reacquireFn: withReacquire
          ? () async {
              log.add('reacquire:$name');
              return true;
            }
          : null,
      addLostListenerFn: (l) {
        lostSubscriptions++;
        listener = l;
        log.add('subscribe:$name');
        return () {
          lostUnsubscribes++;
          log.add('unsubscribe:$name');
          if (unsubscribeThrows) throw StateError('context already gone');
        };
      },
    );
  }

  late final _FakeEncoder _platform;
  _FakeEncoder get fake => _platform;
}

/// A recovery with every hook inert — these tests are about the BINDING, and
/// nothing here ever declares a loss.
CaptureRecovery _inertRecovery() => CaptureRecovery(
      label: 'screen[test]',
      policy: VideoCaptureLossPolicy.reacquire,
      reacquireLimit: null,
      nowUs: () => 0,
      log: (m, {bool severe = false}) {},
      quiesce: () async {},
      restart: () async {},
    );

void main() {
  late List<String> log;

  setUp(() {
    log = [];
    // No real buffers reach these tests; if one ever does, say so loudly
    // rather than handing a synthetic buffer to native code.
    releaseCaptureBuffer = (b) => log.add('release');
  });

  tearDown(() {
    releaseCaptureBuffer = MiniAV.releaseBufferSync;
  });

  ({VideoTrackRuntime track, _Stage stage}) make(
    String name, {
    int width = 640,
    int height = 480,
    VideoCodec codec = VideoCodec.h264,
    int fpsNum = 30,
    Uint8List? extraData,
    bool withReacquire = true,
  }) {
    final s = _Stage(log, name);
    final t = s.build(
      width: width,
      height: height,
      codec: codec,
      fpsNum: fpsNum,
      extraData: extraData,
      withReacquire: withReacquire,
    );
    return (track: t, stage: s);
  }

  _watchdogWiringTests();
  _bufferAccountingTests();
  _liveStatusTests();

  group('adoptStage tears the old stage down before installing the new', () {
    test('the old capture, encoder and context all go, in that order',
        () async {
      final old = make('old');
      final fresh = make('new');

      await old.track.adoptStage(fresh.track);

      // stop before close before destroy: an encoder closed while the capture
      // is still delivering, or a context destroyed while its textures are
      // still imported, is a use-after-free in native code.
      final tail = log.where((e) => e.endsWith(':old')).toList();
      expect(tail, ['stop:old', 'close:old', 'destroy:old']);
      expect(old.stage.fake.closed, isTrue);
    });

    test('a teardown that throws does not lose the stage already built',
        () async {
      // After a device reset every object in the old stage is bound to a
      // removed device, so closing them is EXPECTED to fail. Throwing there
      // must not strand the working stage that was just constructed.
      final old = make('old');
      old.stage.stopThrows = true;
      old.stage.destroyThrows = true;
      old.stage.fake.closeThrows = true;
      final fresh = make('new');

      await old.track.adoptStage(fresh.track);

      expect(old.track.encoder, same(fresh.track.encoder),
          reason: 'the new encoder is installed despite every teardown '
              'failing');
      expect(log, containsAll(['stop:old', 'close:old', 'destroy:old']),
          reason: 'every teardown is still attempted');
    });

    test('every stage field moves across, not just the encoder', () async {
      final old = make('old');
      final fresh = make('new');

      await old.track.adoptStage(fresh.track);

      expect(old.track.encoder, same(fresh.track.encoder));
      expect(old.track.captureCtx, same(fresh.track.captureCtx));
      expect(old.track.processor, same(fresh.track.processor));
      expect(old.track.startFn, same(fresh.track.startFn));
      expect(old.track.stopFn, same(fresh.track.stopFn));
      expect(old.track.destroyFn, same(fresh.track.destroyFn));
      expect(old.track.reacquireFn, same(fresh.track.reacquireFn));
      expect(old.track.addLostListenerFn, same(fresh.track.addLostListenerFn));
    });

    test('capability flags travel WITH the stage', () async {
      // A rebuild can legitimately land on a different path — the GPU came
      // back but zero-copy did not. Keeping the old flags would route frames
      // somewhere the new encoder cannot follow, and that fails silently.
      final old = make('old');
      old.track.directD3d11Passthrough = true;
      old.track.pipelinedZeroCopy = true;
      final fresh = make('new');
      fresh.track.directD3d11Passthrough = false;
      fresh.track.pipelinedZeroCopy = false;
      fresh.track.processorCpuReadback = true;

      await old.track.adoptStage(fresh.track);

      expect(old.track.directD3d11Passthrough, isFalse);
      expect(old.track.pipelinedZeroCopy, isFalse);
      expect(old.track.processorCpuReadback, isTrue);
    });

    test('the first frame after a rebuild is asked to be a keyframe',
        () async {
      // Nothing downstream can predict where an outage ended, so a seek
      // landing just after one would otherwise run back to an IDR across the
      // discontinuity, through frames the new encoder never produced.
      final old = make('old');
      final fresh = make('new');
      await old.track.adoptStage(fresh.track);
      expect(fresh.stage.fake.keyframeRequests, 1);
    });
  });

  group('a rebuild is refused unless it matches what the file declares', () {
    test('the same shape is adoptable', () {
      final a = make('a');
      final b = make('b');
      expect(a.track.canAdopt(b.track), isTrue);
    });

    test('different dimensions are refused', () {
      final a = make('a');
      final b = make('b', width: 1280, height: 720);
      expect(a.track.canAdopt(b.track), isFalse,
          reason: 'the track header already declares 640x480');
    });

    test('a different codec is refused', () {
      final a = make('a');
      final b = make('b', codec: VideoCodec.hevc);
      expect(a.track.canAdopt(b.track), isFalse);
    });

    test('a different frame rate is refused', () {
      final a = make('a');
      final b = make('b', fpsNum: 60);
      expect(a.track.canAdopt(b.track), isFalse);
    });

    test('height alone moving is caught, with the width unchanged', () {
      // Both dimensions need their own comparison. Changing only the height
      // is what proves the height is actually read — a case where the width
      // also moves passes on the width check alone.
      final a = make('a');
      final b = make('b', width: 640, height: 481);
      expect(a.track.canAdopt(b.track), isFalse);
    });

    test('width alone moving is caught, with the height unchanged', () {
      final a = make('a');
      final b = make('b', width: 641, height: 480);
      expect(a.track.canAdopt(b.track), isFalse);
    });
  });

  group('the capture-lost subscription follows the stage', () {
    test('a rebuild re-subscribes, so a SECOND loss is still heard', () async {
      // The failure this prevents: recover once, then go quiet for the rest of
      // the session because the listener is still bound to a context that was
      // destroyed.
      final old = make('old');
      final fresh = make('new');
      old.track.bindLostListener(_inertRecovery());
      expect(old.stage.lostSubscriptions, 1);

      await old.track.adoptStage(fresh.track);

      expect(fresh.stage.lostSubscriptions, 1,
          reason: 'the new context must be listened to');
      expect(old.stage.lostUnsubscribes, 1,
          reason: 'and the old subscription released');
    });

    test('an unsubscribe that throws does not abort the rebind', () async {
      // The disposer belongs to a context that may already be destroyed.
      final old = make('old');
      final fresh = make('new');
      old.stage.unsubscribeThrows = true;
      old.track.bindLostListener(_inertRecovery());
      await old.track.adoptStage(fresh.track);
      expect(fresh.stage.lostSubscriptions, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// The watchdog tick, wired to a real recovery through the real runtime.
//
// Both halves have their own tests. This is about the WIRING between them,
// which is the part that has been wrong twice: a listener left bound to a
// destroyed context, and a re-acquire closure that was never null.
// ---------------------------------------------------------------------------
void _watchdogWiringTests() {
  const us = 1000000;

  group('a silent capture reaches the recovery', () {
    late List<String> log;

    setUp(() {
      log = [];
      releaseCaptureBuffer = (b) => log.add('release');
    });
    tearDown(() => releaseCaptureBuffer = MiniAV.releaseBufferSync);

    /// A recovery whose first backoff never elapses. It accepts a loss and
    /// starts its loop, then parks — so the loss is observable without the
    /// retry machinery running underneath the assertions.
    CaptureRecovery parked() => CaptureRecovery(
          label: 'screen[test]',
          policy: VideoCaptureLossPolicy.reacquire,
          reacquireLimit: null,
          nowUs: () => 0,
          log: (m, {bool severe = false}) {},
          quiesce: () async {},
          restart: () async {},
          reacquire: () async => true,
          delay: (d) => Completer<void>().future,
        );

    ({VideoTrackRuntime track, CaptureRecovery recovery}) armed({
      int fps = 30,
      bool arm = true,
      bool bind = true,
    }) {
      final s = _Stage(log, 'wd');
      final t = s.build(fpsNum: fps);
      final r = parked();
      if (bind) t.bindLostListener(r);
      if (arm) t.armWatchdog(0);
      return (track: t, recovery: r);
    }

    test('a producing capture is left alone', () {
      final h = armed();
      h.track.notePacket(1 * us);
      expect(h.track.checkWatchdog(2 * us), isFalse);
      expect(h.recovery.lossCount, 0);
    });

    test('silence past the window declares the loss to the RECOVERY', () {
      // Not just logged at: a watchdog that notices and tells nobody is the
      // bug it exists to fix, one layer up.
      final h = armed();
      h.track.notePacket(0);
      expect(h.track.checkWatchdog(10 * us), isTrue);
      expect(h.recovery.lossCount, 1);
      expect(h.track.captureLost, isTrue);
    });

    test('a second tick during recovery does not declare a second loss', () {
      // The recovery already owns the situation; re-declaring on every tick
      // would reset its backoff and never let an attempt finish.
      final h = armed();
      h.track.notePacket(0);
      expect(h.track.checkWatchdog(10 * us), isTrue);
      expect(h.track.checkWatchdog(20 * us), isFalse);
      expect(h.track.checkWatchdog(30 * us), isFalse);
      expect(h.recovery.lossCount, 1);
    });

    test('the silence clock restarts on the declaration', () {
      // Otherwise a recovery that has not fixed it re-declares on the very
      // next tick instead of waiting out the window again.
      final h = armed();
      h.track.notePacket(0);
      h.track.checkWatchdog(10 * us);
      expect(h.track.lastPacketUs, -1);
      expect(h.track.encodeErrorsSincePacket, 0);
    });

    test('a produced packet clears the error count that fed the decision', () {
      final h = armed();
      h.track.encodeErrorsSincePacket = 4;
      h.track.notePacket(5 * us);
      expect(h.track.encodeErrorsSincePacket, 0);
      expect(h.track.lastPacketUs, 5 * us);
    });

    test('an unarmed track never fires', () {
      final h = armed(arm: false);
      expect(h.track.checkWatchdog(600 * us), isFalse);
      expect(h.recovery.lossCount, 0);
    });

    test('a track with no recovery bound never fires', () {
      final h = armed(bind: false);
      expect(h.track.checkWatchdog(600 * us), isFalse);
    });

    test('the two detectors stay distinguishable in the log', () {
      // A platform reason code and "nothing reported this" must not collide,
      // or a log cannot say which detector fired.
      expect(VideoTrackRuntime.watchdogLossReason, isNegative);
    });
  });
}

// ---------------------------------------------------------------------------
// Capture buffers. Releasing one twice is a crash inside native code; never
// releasing it is a leak that only shows up an hour into a recording. Neither
// is observable from a real release, which is what the seam is for.
// ---------------------------------------------------------------------------
void _bufferAccountingTests() {
  MiniAVBuffer buf(int id) => MiniAVBuffer(
        type: MiniAVBufferType.video,
        contentType: MiniAVBufferContentType.gpuD3D11Handle,
        timestampUs: id,
        data: null,
        dataSizeBytes: 0,
      );

  group('a retired capture buffer is released exactly once', () {
    late List<int> released;

    setUp(() {
      released = [];
      releaseCaptureBuffer = (b) => released.add(b.timestampUs);
    });
    tearDown(() => releaseCaptureBuffer = MiniAV.releaseBufferSync);

    VideoTrackRuntime track(String name) => _Stage([], name).build();

    test('a stage swap releases the duplicator source, once', () async {
      final old = track('old');
      old.duplicatorSource = buf(1);
      await old.adoptStage(track('new'));

      expect(released, [1]);
      expect(old.duplicatorSource, isNull);
      expect(old.retiredBufferCount, 0);
    });

    test('two swaps in a row do not release the same buffer twice', () async {
      final old = track('old');
      old.duplicatorSource = buf(1);
      await old.adoptStage(track('a'));
      await old.adoptStage(track('b'));

      expect(released, [1], reason: 'the second swap has nothing left to free');
    });

    test('a swap with no retained source releases nothing', () async {
      final old = track('old');
      await old.adoptStage(track('new'));
      expect(released, isEmpty);
    });

    test('dispose releases a source the swap never reached', () async {
      // The recording ended during an outage: nothing re-acquired, so the
      // retired buffer is still held.
      final t = track('t');
      t.retireDuplicatorSource(buf(7));
      expect(released, isEmpty, reason: 'not before in-flight work drains');
      await t.dispose();
      expect(released, [7]);
    });

    test('dispose releases BOTH a retired buffer and a retained one',
        () async {
      // Two different holders. Freeing only the retained one leaks the other,
      // and an hour of recording is a lot of leaked capture surfaces.
      final t = track('t');
      t.retireDuplicatorSource(buf(1));
      t.duplicatorSource = buf(2);
      await t.dispose();
      expect(released..sort(), [1, 2]);
    });

    test('dispose after a swap does not double-release', () async {
      final t = track('t');
      t.duplicatorSource = buf(7);
      await t.adoptStage(track('new'));
      await t.dispose();
      expect(released, [7]);
    });

    test('several retirements BETWEEN drains all survive to be released',
        () async {
      // The case a single slot loses. A failed duplicate retires its source;
      // the next live frame arms a new one; the target then dies and retires
      // that too — all before anything drains. A slot keeps the first and
      // drops the rest.
      final t = track('t');
      t.retireDuplicatorSource(buf(1));
      t.retireDuplicatorSource(buf(2));
      t.duplicatorSource = buf(3);
      expect(t.retiredBufferCount, 2);

      await t.adoptStage(track('new'));
      expect(released..sort(), [1, 2, 3],
          reason: 'every retirement between drains must be freed');
      expect(t.retiredBufferCount, 0);
    });

    test('a source replaced across swaps is released each time', () async {
      final t = track('t');
      t.duplicatorSource = buf(1);
      await t.adoptStage(track('a'));
      t.duplicatorSource = buf(2);
      await t.adoptStage(track('b'));
      t.duplicatorSource = buf(3);
      await t.dispose();

      expect(released, [1, 2, 3]);
    });
  });
}

// ---------------------------------------------------------------------------
// Live status. captureIssues only exists after stop(); an operator watching a
// ninety-five-minute session needs to know at minute fifty-four, not at the
// end, so this is the signal that has to be right while recording.
// ---------------------------------------------------------------------------
void _liveStatusTests() {
  group('captureStatus reports health while the recording runs', () {
    late List<String> log;
    setUp(() {
      log = [];
      releaseCaptureBuffer = (b) => log.add('release');
    });
    tearDown(() => releaseCaptureBuffer = MiniAV.releaseBufferSync);

    CaptureRecovery parked({int nowUs = 0}) => CaptureRecovery(
          label: 'screen[test]',
          policy: VideoCaptureLossPolicy.reacquire,
          reacquireLimit: null,
          nowUs: () => nowUs,
          log: (m, {bool severe = false}) {},
          quiesce: () async {},
          restart: () async {},
          reacquire: () async => true,
          delay: (d) => Completer<void>().future,
        );

    test('a track with no recovery yet reports nothing', () {
      final t = _Stage(log, 'x').build();
      expect(t.captureStatus, isNull,
          reason: 'before startCapture there is nothing to report');
    });

    test('a healthy capture reads healthy', () {
      final t = _Stage(log, 'x').build();
      t.bindLostListener(parked());
      final s = t.captureStatus!;
      expect(s.healthy, isTrue);
      expect(s.lost, isFalse);
      expect(s.ended, isFalse);
      expect(s.lossCount, 0);
      expect(s.secondsMissing, 0);
      expect(s.toString(), contains('ok'));
    });

    test('an open outage is visible IMMEDIATELY, not after it resolves', () {
      // The whole point: an operator has to be able to see it while it is
      // happening. A status that only appears once the outage ends is a
      // status that never appears for the session that never recovers.
      var clock = 0;
      final t = _Stage(log, 'x').build();
      final r = CaptureRecovery(
        label: 'screen[x]',
        policy: VideoCaptureLossPolicy.reacquire,
        reacquireLimit: null,
        nowUs: () => clock,
        log: (m, {bool severe = false}) {},
        quiesce: () async {},
        restart: () async {},
        reacquire: () async => true,
        delay: (d) => Completer<void>().future,
      );
      t.bindLostListener(r);
      t.armWatchdog(0);
      t.notePacket(0);

      clock = 10000000;
      expect(t.checkWatchdog(clock), isTrue);

      clock = 25000000;
      final s = t.captureStatus!;
      expect(s.lost, isTrue);
      expect(s.healthy, isFalse);
      expect(s.lossCount, 1);
      expect(s.secondsMissing, greaterThan(0),
          reason: 'the outage still running must already count as missing');
      expect(s.toString(), contains('LOST'));
    });

    test('a track that gave up reads ended, and says so in one line', () {
      final t = _Stage(log, 'x').build(withReacquire: false);
      final r = CaptureRecovery(
        label: 'screen[x]',
        policy: VideoCaptureLossPolicy.reacquire,
        reacquireLimit: null,
        nowUs: () => 0,
        log: (m, {bool severe = false}) {},
        quiesce: () async {},
        restart: () async {},
        // No path at all — a closed window.
      );
      t.bindLostListener(r);
      r.noteLost(7);

      final s = t.captureStatus!;
      expect(s.ended, isTrue);
      expect(s.healthy, isFalse);
      expect(s.toString(), contains('ENDED'));
    });
  });
}
