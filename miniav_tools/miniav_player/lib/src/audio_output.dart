/// Decoded-PCM playback sink via miniav's first-party audio output module
/// (miniaudio — FFI on native, WASM on web). Replaces the external
/// `miniaudio_dart` dependency with `MiniAudioOutput`, so the player's sink is
/// the same code path on every platform.
///
/// Lazily initialises to the stream format reported by the FIRST decoded
/// chunk (the decoder, not the config, is the source of truth for sample
/// rate / channels). Drift control is queue-depth based: [MiniAudioOutputContext.writeFrames]
/// accepting fewer frames than offered means the ring is full — the tail is
/// dropped and counted, and the caller may re-anchor the clock.
///
/// A machine with no usable output device is a supported configuration, not an
/// error: the sink degrades once to a silent null sink that still honours
/// paced-write backpressure. See `usingNullSink`.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart' show visibleForTesting;
import 'package:miniav/miniav.dart';
import 'package:miniav_tools/miniav_tools.dart' show DecodedAudio;

class PlayerAudioOutput {
  PlayerAudioOutput({this.bufferMs = 120});

  /// Test seam for the device-open FAILURE path (a machine with no output
  /// device — headless CI, a container, a server). Static because the player
  /// builds its sink internally inside `MiniavPlayer.open`, so there is no
  /// instance to inject into.
  @visibleForTesting
  static Future<MiniAudioOutputContext> Function()? debugCreateContext;

  /// Target ring depth of the underlying sink, in milliseconds.
  final int bufferMs;

  MiniAudioOutputContext? _ctx;
  bool _disposed = false;

  /// Set once, permanently, when the output device cannot be opened. Writes
  /// are then accepted and discarded rather than throwing per chunk — see
  /// [usingNullSink].
  bool _nullSink = false;

  /// Null-sink mirror of the device's stopped state: with no device to stop,
  /// paced writes have to hold themselves.
  bool _nullPaused = false;

  int _sampleRate = 0;
  int _channels = 0;
  double _pendingVolume = 1.0;

  /// True when no output device could be opened and this sink is swallowing
  /// audio. Playback continues (and stays correctly paced in
  /// [PlayerLatencyMode.paced]); it is simply inaudible. The stats below then
  /// describe the null sink, not a device.
  bool get usingNullSink => _nullSink;

  // --- stats -----------------------------------------------------------------
  int writtenFrames = 0;
  int droppedFrames = 0;
  int formatMismatchChunks = 0;

  /// pts of the sample most recently accepted into the ring, µs (or null
  /// before the first write). `pts + accepted duration`.
  int? lastWrittenEndPtsUs;

  bool get isInitialized => _ctx != null;
  int get sampleRate => _sampleRate;
  int get channels => _channels;

  double get volume => _ctx?.volume ?? _pendingVolume;
  set volume(double v) {
    _pendingVolume = v;
    _ctx?.volume = v;
  }

  /// Lazily init/validate the device stream against [chunk]'s format.
  /// Returns false when the chunk cannot be played (format change).
  ///
  /// A device that cannot be opened degrades to the null sink ONCE and then
  /// keeps returning true: the alternative is an exception per chunk out of
  /// the player's audio pump, which is an unhandled async error nothing can
  /// catch and which takes playback down on any machine without an output
  /// device.
  Future<bool> _ensureFor(DecodedAudio chunk) async {
    if (_disposed) return false;
    if (_ctx == null && !_nullSink) {
      _sampleRate = chunk.sampleRate;
      _channels = chunk.channels;
      final bufferFrames = (bufferMs * _sampleRate / 1000).round();
      final MiniAudioOutputContext ctx;
      try {
        ctx = await (debugCreateContext ?? MiniAudioOutput.createContext)();
        await ctx.configure(
          '', // default output device
          MiniAVAudioInfo(
            format: MiniAVAudioFormat.f32,
            sampleRate: _sampleRate,
            channels: _channels,
            numFrames: 0,
          ),
          bufferFrames: bufferFrames,
        );
        ctx.volume = _pendingVolume;
        await ctx.start();
      } catch (e, s) {
        _nullSink = true;
        // Reported once, at the point of failure, and never again: this is a
        // property of the machine, not of the chunk in hand.
        developer.log(
          'no audio output device — playback continues without sound',
          name: 'miniav_player',
          error: e,
          stackTrace: s,
        );
        return true;
      }
      // A dispose() may have raced the awaits above.
      if (_disposed) {
        await ctx.destroy();
        return false;
      }
      _ctx = ctx;
      return true;
    }
    if (chunk.sampleRate != _sampleRate || chunk.channels != _channels) {
      // Mid-stream format changes are rare (codec reconfig); resampling is
      // out of scope here — count and skip so a/v keeps running.
      formatMismatchChunks++;
      return false;
    }
    return true;
  }

  /// Feed one decoded chunk (LIVE mode). Returns the number of frames
  /// actually accepted (== chunk.frameCount unless the ring overflowed —
  /// in live mode dropping beats adding latency).
  Future<int> write(DecodedAudio chunk) async {
    if (!await _ensureFor(chunk)) return 0;
    final ctx = _ctx;
    if (ctx == null) {
      // Null sink, live mode: consume instantly and discard. Counted as
      // accepted, not dropped — a sink with nowhere to put samples can never
      // be the thing that is behind.
      writtenFrames += chunk.frameCount;
      lastWrittenEndPtsUs =
          chunk.ptsUs + (chunk.frameCount * 1000000) ~/ chunk.sampleRate;
      return chunk.frameCount;
    }
    final accepted = ctx.writeFrames(chunk.samples, chunk.frameCount);
    writtenFrames += accepted;
    if (accepted < chunk.frameCount) {
      droppedFrames += chunk.frameCount - accepted;
    }
    lastWrittenEndPtsUs =
        chunk.ptsUs + (accepted * 1000000) ~/ chunk.sampleRate;
    return accepted;
  }

  /// Feed one decoded chunk (PACED/VOD mode): never drops — when the ring
  /// is full it WAITS for the device to consume, which is the natural
  /// decode-ahead throttle for source-driven playback. [shouldAbort] breaks
  /// the wait (pause/seek/close).
  Future<void> writePaced(
    DecodedAudio chunk, {
    required bool Function() shouldAbort,
  }) async {
    if (!await _ensureFor(chunk)) return;
    final ctx = _ctx;
    if (ctx == null) return _writePacedNull(chunk, shouldAbort);
    var offsetFrames = 0;
    while (offsetFrames < chunk.frameCount) {
      if (_disposed || shouldAbort()) return;
      final remaining = chunk.frameCount - offsetFrames;
      final view = offsetFrames == 0
          ? chunk.samples
          : Float32List.sublistView(chunk.samples, offsetFrames * _channels);
      final accepted = ctx.writeFrames(view, remaining);
      if (accepted > 0) {
        writtenFrames += accepted;
        offsetFrames += accepted;
        lastWrittenEndPtsUs =
            chunk.ptsUs + (offsetFrames * 1000000) ~/ chunk.sampleRate;
      } else {
        // Ring full: ~one device period of patience.
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }
  }

  /// Null-sink paced write: there is no ring to fill, so consume the chunk at
  /// the stream's REAL rate against a wall clock.
  ///
  /// Returning instantly instead would remove the only backpressure paced
  /// playback has — the decode-ahead gate would then run a whole file as fast
  /// as it decodes, and end-of-stream would arrive long before the media
  /// would have. Pacing off a single stopwatch rather than per-slice sleeps
  /// keeps timer overshoot from accumulating over a multi-second chunk.
  Future<void> _writePacedNull(
    DecodedAudio chunk,
    bool Function() shouldAbort,
  ) async {
    final rate = chunk.sampleRate > 0 ? chunk.sampleRate : _sampleRate;
    if (rate <= 0) return;
    var offsetFrames = 0;
    final elapsed = Stopwatch()..start();
    while (offsetFrames < chunk.frameCount) {
      if (_disposed || shouldAbort()) return;
      if (_nullPaused) {
        // A stopped device stops consuming; so does this.
        elapsed.stop();
        await Future<void>.delayed(const Duration(milliseconds: 8));
        continue;
      }
      if (!elapsed.isRunning) elapsed.start();
      final playedFrames = elapsed.elapsedMicroseconds * rate ~/ 1000000;
      if (playedFrames <= offsetFrames) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        continue;
      }
      final consumed = math.min(playedFrames, chunk.frameCount) - offsetFrames;
      offsetFrames += consumed;
      writtenFrames += consumed;
      lastWrittenEndPtsUs = chunk.ptsUs + (offsetFrames * 1000000) ~/ rate;
    }
  }

  /// Convenience for flush(): feed every trailing chunk.
  Future<void> writeAll(List<DecodedAudio> chunks) async {
    for (final c in chunks) {
      await write(c);
    }
  }

  /// Drop queued-but-unplayed samples (flush/seek).
  void clear() {
    final f = _ctx?.clear();
    if (f != null) unawaited(f);
  }

  /// Halt the device stream (queued samples stay buffered).
  void pause() {
    _nullPaused = true;
    final f = _ctx?.stop();
    if (f != null) unawaited(f);
  }

  /// Restart the device stream after [pause].
  void resume() {
    _nullPaused = false;
    final f = _ctx?.start();
    if (f != null) unawaited(f);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final ctx = _ctx;
    _ctx = null;
    if (ctx != null) unawaited(ctx.destroy());
  }
}
