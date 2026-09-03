/// WebCodecs decoders hosted on a worker. **Off by default** — see
/// [workerDecodeRequested] for the measurements that turned it off.
///
/// It was built to get our bridge to the browser's decoder off the UI thread:
/// every packet builds a chunk and then waits for an output callback. Measured,
/// that bridge is not what makes playback lag — decoding 120 frames costs the
/// main thread ~11 ms either way, and under a 50%-busy main thread the two are
/// indistinguishable. The browser was already decoding off-thread; what remains
/// on the main thread is one event-loop turn per frame, and a worker adds a
/// round trip rather than removing one.
///
/// The machinery is sound and stays here because the shape it belongs to is a
/// worker that demuxes, decodes AND presents without returning to the main
/// thread per frame (OffscreenCanvas — Stage 4 in the media threading plan).
/// That is a different measurement, and this is the piece it is built from.
///
/// Decoded video crosses as a TRANSFERRED `VideoFrame`: a handle to a surface
/// the browser already owns, moved rather than copied, so a 4K frame costs the
/// same as a 240p one. Audio crosses as copied f32 PCM, because the sink on the
/// other side keeps it.
///
/// Both seams degrade the same way [WorkerDemuxer] does — a worker that cannot
/// be had returns null and the caller decodes in process. Missing a payload
/// should cost throughput, never playback.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';
import 'package:spawn/spawn.dart';
import 'package:web/web.dart' as web;

import '../../workers/codec_worker.dart';
import 'web_codecs_decoder.dart' show WebDecodedFrame;

/// Re-exported so a test can build an entry pointing at its own payload URL.
const WorkerHandler codecWorkerEntryPoint = codecWorker;

const String _kBackend = 'webcodecs-worker';

/// The worker's identity. Its compiled payload ships as a package asset, so an
/// app using this package builds nothing.
///
/// `.split`, not `.inline`: the body is WebCodecs, which does not exist off the
/// browser, and a split entry is never run on the main thread — so a missing
/// payload reports itself instead of silently decoding on the very thread this
/// exists to clear.
///
/// No `protocol` is named because there is nothing to register: unlike the
/// demuxer's `TrackInfo`/`EncodedPacket`, everything on this wire is already
/// portable — numbers, a `Uint8List`, a `Float32List`, and an opaque
/// [PlatformValue] holding the frame.
const codecWorkerEntry = SpawnEntry.split(
  codecWorker,
  asset: 'packages/miniav_tools_codecs/workers/codec_worker',
);

/// Whether [options] asks for worker decode. OFF unless asked for.
///
/// This shipped preferring the worker, on the reasoning that our bridge to the
/// browser's decoder — build a chunk, then yield the event loop waiting for the
/// output callback — had no business on the UI thread. Measurement
/// (test/worker_pipeline_bench_test.dart, Chrome, 120 VP8 frames at 640x480)
/// says it buys nothing:
///
/// | | in process | on a worker |
/// |---|---|---|
/// | idle page | 311 ms wall, 11.4 ms main-thread blocked | 330 ms, 8.4 ms |
/// | main thread 50% busy | **474 ms**, 233 ms blocked | **479 ms**, 232 ms |
///
/// The second row is the one that matters, because "lags under load" is the
/// complaint this was built for — and the two are indistinguishable. The
/// premise was that a contended main thread starves the decoder's yield loop,
/// but in steady state that loop never runs: `decode` submits and hands back a
/// frame buffered by the previous call, so there is nothing to starve. What
/// both paths still pay is one main-thread turn per frame, which a worker does
/// not remove.
///
/// Against that, the worker costs ~63 ms to spawn cold (straight onto
/// time-to-first-frame) and ~22 ms per seek, since the player reopens decoders
/// on every seek.
///
/// Kept, tested and one flag away: the balance flips the moment the main thread
/// stops being a per-frame participant — a worker that demuxes, decodes and
/// presents through an OffscreenCanvas without a round trip per frame is a
/// different measurement, and this is the piece it would be built from.
/// Turn on with `backendOptions['worker'] = 'true'`.
bool workerDecodeRequested(Map<String, String> options) =>
    options['worker'] == 'true';

/// Spawns a codec worker and configures its decoder, or returns null.
///
/// Null covers every reason a worker might not be available — no payload, no
/// worker support, a startup failure, or a browser that declines this codec in
/// a worker context. The caller has a working in-process path for all of them.
///
/// Cost, measured in Chrome on the dev box: ~63 ms the first time (fetching and
/// parsing the payload) and ~11 ms after, against ~0.1 ms to build an
/// in-process decoder. That matters because the player reopens its decoders on
/// every seek, so a seek pays roughly 22 ms for the pair — real, but small
/// beside the container seek and keyframe preroll it happens inside, and paid
/// only on a user-initiated action rather than per frame. If that ever stops
/// being true the fix is a reset op on the existing worker, not a pool.
Future<Worker?> _open(
  String role,
  Map<String, Object?> init,
  SpawnEntry entry,
  Duration timeout,
) async {
  final Worker worker;
  try {
    worker = await spawn(
      entry,
      message: <String, Object?>{'role': role, ...init},
      timeout: timeout,
    );
  } on Object {
    return null;
  }
  try {
    await worker.request<Object?>('open');
    return worker;
  } on Object {
    // Configure failed. The in-process decoder will fail the same way and the
    // backend registry can then fall through to a lower-priority backend, so
    // let the caller reach that conclusion on the path that reports it best.
    await worker.close(force: true);
    return null;
  }
}

/// A [PlatformDecoder] whose WebCodecs bridge runs somewhere else.
class WorkerVideoDecoder implements PlatformDecoder {
  WorkerVideoDecoder._(this._worker);

  final Worker _worker;
  bool _closed = false;

  /// Opens a worker-hosted video decoder for [config], or null if none can be
  /// had. [entry] exists so a test can point at a payload URL its own server
  /// serves; production always uses [codecWorkerEntry].
  static Future<WorkerVideoDecoder?> tryCreate(
    DecoderConfig config, {
    Duration timeout = const Duration(seconds: 10),
    SpawnEntry entry = codecWorkerEntry,
  }) async {
    if (!workerDecodeRequested(config.backendOptions)) return null;
    final worker = await _open(kRoleVideo, <String, Object?>{
      'codec': config.codec.name,
      'extra': _tight(config.extraData),
      'width': config.width,
      'height': config.height,
      'options': config.backendOptions,
    }, entry, timeout);
    return worker == null ? null : WorkerVideoDecoder._(worker);
  }

  @override
  Future<DecodedFrame?> decode(EncodedPacket packet) async {
    if (_closed) {
      throw const CodecRuntimeException(_kBackend, 'decoder closed');
    }
    try {
      return _frame(await _worker.request<Object?>(_decodeOp(packet)));
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
  }

  @override
  Future<List<DecodedFrame>> flush() async {
    if (_closed) return const <DecodedFrame>[];
    final Object? reply;
    try {
      reply = await _worker.request<Object?>('flush');
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
    return <DecodedFrame>[
      for (final frame in (reply as List<Object?>? ?? const <Object?>[]))
        if (_frame(frame) case final DecodedFrame decoded) decoded,
    ];
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Nothing native is blocked in here — a WebCodecs decoder is the browser's
    // own thread pool, not a synchronous FFI call — so the graceful path always
    // wins the race, and it is what closes any frames still buffered.
    await _worker.close(grace: const Duration(seconds: 2));
  }
}

/// A [PlatformAudioDecoder] whose WebCodecs bridge runs somewhere else.
class WorkerAudioDecoder implements PlatformAudioDecoder {
  WorkerAudioDecoder._(this._worker);

  final Worker _worker;
  bool _closed = false;

  /// Opens a worker-hosted audio decoder for [config], or null if none can be
  /// had. See [WorkerVideoDecoder.tryCreate].
  static Future<WorkerAudioDecoder?> tryCreate(
    AudioDecoderConfig config, {
    Duration timeout = const Duration(seconds: 10),
    SpawnEntry entry = codecWorkerEntry,
  }) async {
    if (!workerDecodeRequested(config.backendOptions)) return null;
    final worker = await _open(kRoleAudio, <String, Object?>{
      'codec': config.codec.name,
      'extra': _tight(config.extraData),
      'sampleRate': config.sampleRate,
      'channels': config.channels,
      'options': config.backendOptions,
    }, entry, timeout);
    return worker == null ? null : WorkerAudioDecoder._(worker);
  }

  @override
  Future<List<DecodedAudio>> decode(EncodedPacket packet) async {
    if (_closed) {
      throw const CodecRuntimeException(_kBackend, 'decoder closed');
    }
    return _chunks(() => _worker.request<Object?>(_decodeOp(packet)));
  }

  @override
  Future<List<DecodedAudio>> flush() async {
    if (_closed) return const <DecodedAudio>[];
    return _chunks(() => _worker.request<Object?>('flush'));
  }

  Future<List<DecodedAudio>> _chunks(Future<Object?> Function() call) async {
    final Object? reply;
    try {
      reply = await call();
    } on Object catch (e) {
      throw CodecRuntimeException(_kBackend, _describe(e));
    }
    return <DecodedAudio>[
      for (final chunk in (reply as List<Object?>? ?? const <Object?>[]))
        _audio(chunk! as Map<String, Object?>),
    ];
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _worker.close(grace: const Duration(seconds: 2));
  }
}

/// The decode request: only what a WebCodecs decoder reads.
///
/// The bytes are COPIED, not transferred. Transferring would detach the
/// caller's buffer, and `EncodedPacket.data` is routinely a view into a larger
/// one the demuxer or the MSE fallback still holds — a saved copy of a few
/// kilobytes is not worth a buffer that vanishes under someone else.
Object _decodeOp(EncodedPacket packet) => <Object?>[
  'decode',
  <String, Object?>{
    'data': packet.data,
    'pts': packet.ptsUs,
    'key': packet.isKeyframe,
  },
];

/// Wraps a transferred `VideoFrame` in the same [DecodedFrame] the in-process
/// path produces. Its size and timestamp are read off the frame itself, so
/// there is no metadata alongside it that could disagree with the pixels.
DecodedFrame? _frame(Object? reply) {
  if (reply == null) return null; // decoder buffering (priming / B-frames)
  if (reply is! PlatformValue) {
    throw CodecRuntimeException(_kBackend, 'expected a frame, got $reply');
  }
  return WebDecodedFrame(reply.value! as web.VideoFrame);
}

DecodedAudio _audio(Map<String, Object?> chunk) => DecodedAudio(
  samples: chunk['samples']! as Float32List,
  frameCount: chunk['frames']! as int,
  sampleRate: chunk['rate']! as int,
  channels: chunk['ch']! as int,
  ptsUs: chunk['pts']! as int,
);

/// A tight copy, because `extraData` is often a view into the container buffer
/// and only the view's own bytes are the avcC / AudioSpecificConfig.
Uint8List? _tight(Uint8List? bytes) =>
    bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);

String _describe(Object error) => switch (error) {
  RemoteWorkerError(:final message) => message,
  StateError(:final message) => message,
  _ => error.toString(),
};
