/// A container writer hosted on a worker.
///
/// `finish()` builds the sample index in one synchronous pass — for a
/// two-hour recording, over half a million entries across `stts`, `stsz`,
/// `stco` and `ctts`. Run on the isolate that called [Recorder.stop], which in
/// a desktop app is the one drawing the UI, that is a frozen window at exactly
/// the moment somebody is waiting to be told their session was saved.
///
/// Only the writing moves. Packets are already encoded when they get here, and
/// they cross as bytes.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show Mp4ConfigChange;
import 'package:spawn/spawn.dart';

import '../workers/mux_worker.dart' show encodeTrackInfo, muxWorker;
import 'mux_sink.dart';

/// Re-exported so a test can drive the handler directly.
const WorkerHandler muxWorkerEntryPoint = muxWorker;

/// The worker's identity.
///
/// No compiled payload: writing a container to a FILE is native-only —
/// `muxerFileSinkAvailable` is false on web — so this never needs to become a
/// Web Worker, and the asset id is here only because [SpawnEntry.inline]
/// requires one.
const muxWorkerEntry = SpawnEntry.inline(
  muxWorker,
  asset: 'packages/miniav_recorder/workers/mux_worker',
);

/// Which phase the worker is in, as it reports them.
typedef MuxPhaseListener = void Function(String phase);

/// The worker ended before the recording did. Reported once.
typedef MuxFatalListener = void Function(Object? error);

/// How a worker gets started. `spawn` in production; `spawnLocal` in a test.
typedef WorkerSpawner = Future<Worker> Function(
  SpawnEntry entry, {
  Object? message,
  Duration timeout,
});

class WorkerMuxSink implements MuxSink {
  WorkerMuxSink._(
    this._worker,
    this.backendName,
    this._onPhase,
    this._onFatal,
  ) {
    _events = _worker.events.listen((event) {
      if (event is String) _onPhase(event);
    });
    // A worker that ends on its own takes the container writer with it. Every
    // write after that fails, one log line per packet, and `finish()` fails
    // too — so the recording ends with no index and thousands of identical
    // errors describing it. Say it once, when it happens, while the rest of
    // the session is still being recorded.
    unawaited(_worker.done.then((_) {
      if (_closed) return;
      _onFatal(_worker.error);
    }));
  }

  final Worker _worker;
  final MuxPhaseListener _onPhase;
  final MuxFatalListener _onFatal;
  late final StreamSubscription<Object?> _events;
  bool _closed = false;

  @override
  final String backendName;

  /// Opens [path] on a worker, or returns null if a worker cannot be had.
  ///
  /// Null rather than throwing, and the distinction matters: a worker that
  /// will not start should cost the UI a freeze at stop, not the recording.
  /// The caller falls back to writing in process, which is what it did before
  /// this existed.
  ///
  /// A muxer that DECLINES the tracks is a different answer and does throw —
  /// that is the routing decision the caller makes, and swallowing it here
  /// would send a container to FFmpeg for a reason nobody could see.
  static Future<WorkerMuxSink?> tryOpen({
    required Container container,
    required String path,
    required List<TrackInfo> tracks,
    required MuxPhaseListener onPhase,
    required MuxFatalListener onFatal,
    SpawnEntry entry = muxWorkerEntry,
    Duration timeout = const Duration(seconds: 10),
    // Injected so a test can run the handler in process behind the REAL
    // Worker protocol (`spawnLocal`) rather than mocking the seam it is
    // supposed to be testing.
    WorkerSpawner spawner = spawn,
  }) async {
    final Worker worker;
    try {
      worker = await spawner(
        entry,
        message: <String, Object?>{
          'container': container.name,
          'path': path,
          'tracks': [for (final t in tracks) encodeTrackInfo(t)],
        },
        timeout: timeout,
      );
    } catch (_) {
      return null;
    }
    final String backend;
    try {
      backend = await worker.request<String>('open', timeout: timeout);
    } catch (e) {
      // The worker started and the muxer refused. Take the worker down and let
      // the caller see why — this is the routing signal, not a transport fault.
      await worker.close(force: true);
      rethrow;
    }
    return WorkerMuxSink._(worker, backend, onPhase, onFatal);
  }

  @override
  Future<void> writePacket(EncodedPacket packet) {
    // COPIED, not transferred, and deliberately. Transferring would detach the
    // buffer on this side, and [Recorder.dispatchPacket] hands the same packet
    // to every sink in turn — a stream sink after a file sink would get a dead
    // view. The copy is one memcpy of an already-encoded frame, tens of
    // kilobytes at 30fps, against a recording that is being written to disk
    // anyway.
    return _worker.request<Object?>([
      'packet',
      packet.data,
      packet.ptsUs,
      packet.dtsUs,
      packet.durationUs,
      packet.isKeyframe,
      packet.trackIndex,
    ]);
  }

  @override
  Future<Mp4ConfigChange?> setTrackConfig(
    int trackIndex,
    Uint8List config,
  ) async {
    final name = await _worker.request<String?>(['config', trackIndex, config]);
    if (name == null) return null;
    return Mp4ConfigChange.values.byName(name);
  }

  @override
  Future<MuxFinishReport> finish() async {
    final raw = await _worker.request<Map<Object?, Object?>>(
      'finish',
      // No timeout: this is the call the whole class exists for, its length is
      // proportional to the recording, and abandoning it would leave a file
      // with no index — the exact outcome all of this is here to prevent.
      timeout: null,
    );
    return MuxFinishReport(
      timingRepairs: (raw['timingRepairs']! as List<Object?>).cast<String>(),
      tracksMissingConfig:
          (raw['tracksMissingConfig']! as List<Object?>).cast<int>(),
    );
  }

  /// Kill the worker without going through [close], so a test can exercise
  /// the path where it ends on its own. Not part of the recorder's flow.
  Future<void> killForTest() => _worker.close(force: true);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _events.cancel();
    await _worker.close();
  }
}
