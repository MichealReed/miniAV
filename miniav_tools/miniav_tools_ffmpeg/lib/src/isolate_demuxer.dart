/// Worker-hosted demuxer.
///
/// `av_read_frame` is synchronous FFI, and on live byte-pipe inputs it
/// BLOCKS until the transport delivers more bytes — so the demuxer must live
/// on a worker. Hosted with `package:spawn`, which supplies the handshake,
/// request/response correlation, and the bounded-then-forced shutdown this
/// file used to hand-roll. The data path for live streams never hops workers:
/// the feed side (main isolate) writes straight into the shim's native byte
/// pipe via FFI, and the worker's `av_read_frame` unblocks on the C condition
/// variable.
///
/// Shutdown protocol for a possibly-starved live worker: close the pipe
/// FIRST (main isolate, unblocks the reader with EOF), then close the worker,
/// then destroy the pipe. That order is not negotiable and `spawn` cannot do
/// it for us — killing an isolate does not preempt a blocking native call, so
/// only the code that owns the pipe can free the reader.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';

import 'ffmpeg_bindings.dart' show ensureFFmpegLoaded;
import 'ffmpeg_demuxer.dart';
import 'ffmpeg_shim.dart';

const String _kBackend = 'ffmpeg-demux-isolate';

/// Feeds a `Stream<List<int>>` into a shim byte pipe with backpressure:
/// when the ring fills, the subscription pauses and the remainder retries
/// on a short timer.
class _PipeFeeder {
  _PipeFeeder(this._shim, this._pipe, Stream<List<int>> stream) {
    _sub = stream.listen(
      _onData,
      onDone: _closePipe,
      onError: (Object e, StackTrace s) {
        error = e;
        _closePipe();
      },
      cancelOnError: true,
    );
  }

  final FfmpegShim _shim;
  final Pointer<Void> _pipe;
  late final StreamSubscription<List<int>> _sub;
  Timer? _retry;
  bool _stopped = false;

  /// First transport error, surfaced by IsolateDemuxer.readPacket at EOF.
  Object? error;

  void _onData(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    _write(bytes, 0);
  }

  void _write(Uint8List bytes, int offset) {
    if (_stopped) return;
    var off = offset;
    while (off < bytes.length) {
      final w = _shim.bytepipeWrite(_pipe, bytes, off, bytes.length - off);
      if (w < 0) {
        // Pipe closed under us (demuxer shutting down) — stop feeding.
        stop();
        return;
      }
      if (w == 0) {
        // Ring full: pause the transport, retry the remainder shortly.
        _sub.pause();
        _retry = Timer(const Duration(milliseconds: 5), () {
          if (_stopped) return;
          _sub.resume();
          _write(bytes, off);
        });
        return;
      }
      off += w;
    }
  }

  void _closePipe() {
    if (_stopped) return;
    _shim.bytepipeClose(_pipe);
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _retry?.cancel();
    _sub.cancel();
  }
}

/// The worker: it holds the FFmpeg demuxer and answers requests.
///
/// `open` is a request rather than part of the handshake because opening can
/// fail (and, on a stalled live stream, can block): as a request it gets a
/// timeout and an error path, where a handshake would only get a hang.
Future<void> demuxWorker(WorkerChannel channel) async {
  final init = channel.initialMessage! as Map<String, Object?>;
  FfmpegDemuxer? demuxer;

  channel.handleRequests((Object? request) async {
    switch (request) {
      case 'open':
        if (!await ensureFFmpegLoaded()) {
          throw StateError('FFmpeg failed to load in worker isolate');
        }
        final mode = init['mode'] as String;
        final arg = init['arg'];
        final opened = switch (mode) {
          'file' => FfmpegDemuxer.openUrl(arg! as String),
          'bytes' => FfmpegDemuxer.openBytes(arg! as Uint8List),
          _ => FfmpegDemuxer.openPipe(
            Pointer<Void>.fromAddress(arg! as int),
            ownsPipe: false, // main isolate owns + destroys
          ),
        };
        demuxer = opened;
        return TracksMessage(
          opened.tracks,
          opened.durationUs,
          opened.isSeekable,
        );

      case 'read':
        final packet = await demuxer!.readPacket();
        return packet == null ? null : PacketMessage(packet);

      case ['seek', final int timestampUs]:
        await demuxer!.seek(timestampUs);
        return null;

      default:
        throw StateError('unknown op: $request');
    }
  });

  // The host closes the pipe before closing us, so a starved `av_read_frame`
  // has already returned EOF by the time this resumes.
  await channel.onClose;
  try {
    await demuxer?.close();
  } on Object {
    // Teardown is best effort; the host is already gone.
  }
}

/// The worker's identity. `protocol:` registers the wire types on both ends.
const demuxEntry = SpawnEntry.inline(
  demuxWorker,
  asset: 'packages/miniav_tools_ffmpeg/workers/demux_worker',
  protocol: registerDemuxProtocol,
);

class IsolateDemuxer implements PlatformDemuxer {
  IsolateDemuxer._(
    this._worker,
    this._tracks,
    this._durationUs,
    this._isSeekable,
    this._shim,
    this._pipe,
    this._feeder,
  );

  final Worker _worker;
  final List<TrackInfo> _tracks;
  final int? _durationUs;
  final bool _isSeekable;

  /// Main-isolate-owned pipe for bytes/byteStream inputs (null for files).
  final FfmpegShim? _shim;
  final Pointer<Void>? _pipe;
  final _PipeFeeder? _feeder;

  bool _closed = false;

  static Future<IsolateDemuxer> open(DemuxerConfig config) async {
    // File inputs need no pipe; bytes/byteStream create one on the MAIN
    // isolate (requires FFmpeg + shim loaded here too — cheap, idempotent).
    Pointer<Void>? pipe;
    FfmpegShim? shim;
    _PipeFeeder? feeder;
    final input = config.input;

    Object? workerArg;
    List<Object>? transfer;
    var mode = 'file';
    if (input is FileDemuxerInput) {
      workerArg = input.path;
    } else {
      if (!await ensureFFmpegLoaded()) {
        throw const CodecInitException(_kBackend, 'FFmpeg failed to load');
      }
      shim = FfmpegShim.tryLoad();
      if (shim == null) {
        throw const CodecInitException(
          _kBackend,
          'shim not loadable — byte inputs need the byte pipe',
        );
      }
      switch (input) {
        case BytesDemuxerInput(:final bytes):
          // Seekable in-worker open from a transferred copy (moov-at-end
          // MP4s need seeks — a forward-only pipe cannot probe them).
          mode = 'bytes';
          workerArg = bytes;
          transfer = <Object>[bytes.buffer];
        case StreamDemuxerInput(:final stream, :final bufferBytes):
          pipe = shim.bytepipeCreate(bufferBytes);
          if (pipe == nullptr) {
            throw const CodecInitException(_kBackend, 'bytepipe OOM');
          }
          feeder = _PipeFeeder(shim, pipe, stream);
          mode = 'pipe';
          workerArg = pipe.address;
        case FileDemuxerInput():
          throw StateError('unreachable');
      }
    }

    void cleanupPipe() {
      feeder?.stop();
      if (pipe != null) {
        shim!.bytepipeClose(pipe);
        shim.bytepipeDestroy(pipe);
      }
    }

    final Worker worker;
    try {
      worker = await spawn(
        demuxEntry,
        message: <String, Object?>{'mode': mode, 'arg': workerArg},
        transfer: transfer,
      );
    } on Object catch (e) {
      cleanupPipe();
      throw CodecInitException(_kBackend, 'worker spawn failed: $e');
    }

    // Open timeout: a live byte stream that stalls mid-probe
    // (avformat_find_stream_info reads ahead and BLOCKS on the pipe) would
    // otherwise hang open() forever — a dead/stalled connection must surface
    // an error instead. Only applies to pipe (stream) inputs; file/bytes
    // open from local/in-memory data that cannot stall. Default 15s; override
    // via backendOptions {'open_timeout_ms': '...'} ('0' disables).
    final int? openTimeoutMs = () {
      final raw = config.backendOptions['open_timeout_ms'];
      if (raw != null) {
        final v = int.tryParse(raw);
        return (v == null || v <= 0) ? null : v;
      }
      return mode == 'pipe' ? 15000 : null;
    }();

    // Deliberately NOT `request(timeout:)`: on a timeout we still need this
    // future, to learn when the worker has released the pipe.
    final opening = worker.request<TracksMessage>('open');
    // A late failure must not surface as an unhandled async error after we
    // have already given up on it.
    unawaited(opening.then((_) {}, onError: (Object _, StackTrace __) {}));

    final TracksMessage info;
    try {
      info = openTimeoutMs != null
          ? await opening.timeout(Duration(milliseconds: openTimeoutMs))
          : await opening;
    } on TimeoutException {
      // Unblock the worker's blocked probe (read cb → EOF → open fails), then
      // wait briefly for it to unwind and release the pipe before destroying.
      if (pipe != null) shim!.bytepipeClose(pipe);
      var workerReleased = false;
      try {
        await opening.timeout(const Duration(seconds: 2));
        workerReleased = true; // answered normally
      } on TimeoutException {
        // Still blocked inside the native probe — leak the pipe rather than
        // risk a use-after-free by destroying it under a live reader.
      } on Object {
        // Answered by throwing: the open failed, which means it unwound out
        // of the native call and is no longer touching the pipe.
        workerReleased = true;
      }
      feeder?.stop();
      await worker.close(force: true);
      if (workerReleased && pipe != null) shim!.bytepipeDestroy(pipe);
      throw CodecInitException(
        _kBackend,
        'open timed out after ${openTimeoutMs}ms — the stream did not deliver '
        'enough data to probe (dead or stalled connection?)',
      );
    } on Object catch (e) {
      // The worker refused to open: a RemoteWorkerError carrying whatever
      // FfmpegDemuxer threw.
      await worker.close(force: true);
      cleanupPipe();
      throw CodecInitException(_kBackend, _describe(e));
    }

    return IsolateDemuxer._(
      worker,
      info.tracks,
      info.durationUs,
      info.isSeekable,
      shim,
      pipe,
      feeder,
    );
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
    final PacketMessage? reply;
    try {
      reply = await _worker.request<PacketMessage?>('read');
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
    if (reply == null) {
      // EOF — surface a transport error (if the feed died) exactly once.
      final err = _feeder?.error;
      if (err != null) {
        _feeder?.error = null;
        throw CodecRuntimeException(_kBackend, 'source stream error: $err');
      }
      return null;
    }
    return reply.packet;
  }

  @override
  Future<void> seek(int timestampUs) async {
    if (!_isSeekable) {
      throw const CodecRuntimeException(
        _kBackend,
        'seek unsupported on a non-seekable (live byte stream) input',
      );
    }
    if (_closed) {
      throw const CodecRuntimeException(_kBackend, 'demuxer closed');
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
    _feeder?.stop();
    final pipe = _pipe;
    // Unblock a starved av_read_frame BEFORE asking the worker to close.
    // Killing the worker cannot do this: an isolate inside a blocking FFI
    // call does not observe a kill until it returns.
    if (pipe != null) _shim!.bytepipeClose(pipe);
    _closed = true;
    // Bounded, then forced — and in-flight requests are failed for us. If the
    // worker already died (a native FFmpeg crash on corrupt input), the grace
    // period expires and the kill still happens.
    await _worker.close(grace: const Duration(seconds: 2));
    if (pipe != null) _shim!.bytepipeDestroy(pipe);
  }
}

/// The message from whatever the worker threw, without the wrapper noise.
String _describe(Object error) => switch (error) {
  RemoteWorkerError(:final message) => message,
  StateError(:final message) => message,
  _ => error.toString(),
};
