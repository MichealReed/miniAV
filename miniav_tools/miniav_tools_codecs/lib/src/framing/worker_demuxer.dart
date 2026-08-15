/// A container demuxer hosted on a worker.
///
/// The pure-Dart container parsers are CPU-bound and, on web, were running on
/// the UI thread — the browser decodes off-thread but nothing was parsing the
/// container off-thread, so a couple of thousand lines of MP4 box walking sat
/// between every packet and the next frame. This moves that parse to a Web
/// Worker (an isolate on native) behind the same [PlatformDemuxer] seam, so
/// nothing upstream of it changes.
///
/// The parse is the only thing that moves. Packets come back as bytes and are
/// still handed to WebCodecs on the main thread, because a `VideoDecoder`
/// belongs to whichever thread will present its frames.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';

import '../../workers/demux_worker.dart' show demuxWorker;

/// Re-exported so a test can build an entry pointing at its own payload URL.
const WorkerHandler demuxWorkerEntryPoint = demuxWorker;

const String _kBackend = 'container-worker';

/// The worker's identity. Its compiled payload ships as a package asset, so
/// an app using this package builds nothing.
const containerDemuxEntry = SpawnEntry.inline(
  demuxWorker,
  asset: 'packages/miniav_tools_codecs/workers/demux_worker',
  protocol: registerDemuxProtocol,
);

/// A [PlatformDemuxer] whose parsing happens somewhere else.
class WorkerDemuxer implements PlatformDemuxer {
  WorkerDemuxer._(
    this._worker,
    this._tracks,
    this._durationUs,
    this._isSeekable,
  );

  final Worker _worker;
  final List<TrackInfo> _tracks;
  final int? _durationUs;
  final bool _isSeekable;
  bool _closed = false;

  /// Opens [bytes] on a worker, or returns null if a worker cannot be had.
  ///
  /// Returning null rather than throwing is deliberate. A missing payload
  /// should cost throughput, not playback: the caller falls back to parsing in
  /// process, which is exactly what it did before this existed. The only way
  /// to be worse off than the old behaviour would be to refuse to play.
  ///
  /// [bytes] is COPIED to the worker, not transferred. Transferring would be
  /// cheaper, and wrong: these bytes belong to the caller, which may still
  /// need them — the player hands the same buffer to the MSE fallback, and a
  /// detached buffer would take playback down to save one copy at open.
  /// [entry] exists so a test can point at a payload URL its server actually
  /// serves; production always uses [containerDemuxEntry].
  static Future<WorkerDemuxer?> tryOpen(
    Uint8List bytes, {
    Container? container,
    Duration timeout = const Duration(seconds: 10),
    SpawnEntry entry = containerDemuxEntry,
  }) async {
    final Worker worker;
    try {
      worker = await spawn(
        entry,
        message: <String, Object?>{
          'bytes': bytes,
          'container': container?.name,
        },
        timeout: timeout,
      );
    } on Object {
      // No payload, no worker support, or a startup failure. The caller has a
      // working in-process path; do not take playback down over throughput.
      return null;
    }

    try {
      final info = await worker.request<TracksMessage>('open');
      return WorkerDemuxer._(
        worker,
        info.tracks,
        info.durationUs,
        info.isSeekable,
      );
    } on Object catch (e) {
      await worker.close(force: true);
      // The parser refused this container. That is a real answer, not a
      // transport problem — but the in-process path would refuse it the same
      // way, so let the caller reach that conclusion itself.
      if (e is RemoteWorkerError) return null;
      throw CodecInitException(_kBackend, '$e');
    }
  }

  @override
  List<TrackInfo> get tracks => _tracks;

  @override
  int? get durationUs => _durationUs;

  @override
  bool get isSeekable => _isSeekable;

  @override
  Future<EncodedPacket?> readPacket() async {
    if (_closed) {
      throw const CodecRuntimeException(_kBackend, 'demuxer closed');
    }
    try {
      final reply = await _worker.request<PacketMessage?>('read');
      return reply?.packet;
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
  }

  @override
  Future<void> seek(int timestampUs) async {
    if (_closed) {
      throw const CodecRuntimeException(_kBackend, 'demuxer closed');
    }
    if (!_isSeekable) {
      throw const CodecRuntimeException(
        _kBackend,
        'seek unsupported on this input',
      );
    }
    try {
      await _worker.request<Object?>(<Object?>['seek', timestampUs]);
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Nothing native is blocked in here — the parser is pure Dart over an
    // in-memory buffer — so the graceful path always wins the race.
    await _worker.close(grace: const Duration(seconds: 2));
  }
}

String _describe(Object error) => switch (error) {
  RemoteWorkerError(:final message) => message,
  StateError(:final message) => message,
  _ => error.toString(),
};
