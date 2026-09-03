/// The whole audio track, off the main thread.
///
/// A worker demuxes and decodes; an `AudioWorklet` plays what it writes,
/// straight out of shared memory, on the browser's realtime audio thread.
/// Between the two, this thread does nothing — which is the point. Audio no
/// longer depends on the main thread being free on a 20 ms cadence, so a long
/// Flutter frame stops being something you can hear.
///
/// It also becomes the player's CLOCK. The ring knows exactly how many frames
/// the audio device has consumed, which is the true playback position; the old
/// path could only know what had been WRITTEN, which is optimistic by however
/// much is sitting in the device buffer.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../workers/audio_playback_worker.dart' show audioPlaybackWorker;
import 'audio_ring_sink.dart';
import 'package:spawn/spawn.dart';

/// The worker's identity; its payload ships as a package asset.
const _entry = SpawnEntry.split(
  audioPlaybackWorker,
  asset: 'packages/miniav_tools_codecs/workers/audio_playback_worker',
);

/// An audio track played entirely off the main thread.
class WorkerAudioTrack {
  WorkerAudioTrack._(this._sink, this._worker, this._sampleRate);

  final AudioRingSink _sink;
  final Worker _worker;
  final int _sampleRate;

  /// Playback position is `[_baselinePtsUs] + frames consumed since
  /// [_baselineFrames]`. A seek moves both, because the ring's cursors are
  /// monotonic for the life of the ring and do not restart with the stream.
  int _baselinePtsUs = 0;
  int _baselineFrames = 0;
  bool _closed = false;

  /// Whether the caller has paused us, as distinct from the audio thread being
  /// suspended for some other reason. [seek] suspends and resumes internally,
  /// so it needs to know what state to put things back into — without this it
  /// would start a paused player playing.
  bool _paused = false;

  /// Starts a worker-hosted audio track over [bytes], or returns null.
  ///
  /// Null is the ordinary answer on any page that cannot host one — no shared
  /// memory (not cross-origin isolated), no `AudioWorklet`, no compiled
  /// payload, or a container this path cannot open. The player then runs its
  /// normal audio pump, exactly as it did before this existed.
  ///
  /// [workletUrl] exists so a test can serve the module from its own tree;
  /// production always uses the package asset.
  static Future<WorkerAudioTrack?> start({
    required Uint8List bytes,
    required int sampleRate,
    required int channels,
    required Duration depth,
    double volume = 1.0,
    String workletUrl = kWorkletAssetUrl,
  }) async {
    final sink = await AudioRingSink.open(
      sampleRate: sampleRate,
      channels: channels,
      depth: depth,
      workletUrl: workletUrl,
    );
    if (sink == null) return null;
    sink.volume = volume;

    final Worker worker;
    try {
      worker = await spawn(
        _entry,
        message: <String, Object?>{
          // SHARED, not transferred: both threads must address this same
          // memory, and shared memory in a transfer list is a DataCloneError.
          'ring': PlatformValue(sink.ring.shareable),
          'bytes': bytes,
        },
        timeout: const Duration(seconds: 10),
      );
    } on Object {
      await sink.close();
      return null;
    }

    final track = WorkerAudioTrack._(sink, worker, sampleRate);
    // A container the worker cannot open is not a transport failure and does
    // not look like one: the pump records it and keeps answering. Ask once
    // before committing, so the player falls back instead of playing silence.
    if (await track._failure() != null) {
      await track.close();
      return null;
    }
    return track;
  }

  Future<String?> _failure() async {
    try {
      final stats = await _worker.request<Object?>('stats');
      return (stats! as Map<String, Object?>)['error'] as String?;
    } on Object catch (e) {
      return '$e';
    }
  }

  /// True playback position, from what the audio device has actually consumed.
  ///
  /// Null until audio starts flowing, which is what the player wants: an
  /// unanchored clock means "nothing is due yet" rather than "we are at zero".
  int? get positionUs {
    if (_closed || _sampleRate <= 0) return null;
    final consumed = _sink.ring.framesConsumed - _baselineFrames;
    if (consumed <= 0 && _baselinePtsUs == 0) return null;
    return _baselinePtsUs + (consumed * 1000000) ~/ _sampleRate;
  }

  /// Frames the audio thread wanted and could not have. The number that says
  /// the producer fell behind — non-zero here is what a click sounds like.
  int get underruns => _sink.underruns;

  /// How much audio is buffered ahead: the margin against a stall.
  Duration get buffered => _sink.buffered;

  double get volume => _sink.volume;
  set volume(double value) => _sink.volume = value;

  /// Suspends the audio thread. The worker needs no telling: with nothing
  /// consuming, the ring fills and its pump blocks on backpressure.
  Future<void> pause() async {
    _paused = true;
    await _sink.suspend();
  }

  /// Resumes the audio thread; the worker's pump unblocks on its own.
  Future<void> resume() async {
    _paused = false;
    await _sink.resume();
  }

  /// Seeks to [targetUs].
  ///
  /// The audio thread is suspended across the whole operation. That is not
  /// politeness: the worker clears the ring as part of seeking, and clearing it
  /// under a live consumer would let one buffer of already-committed samples be
  /// overwritten mid-read — a click at exactly the moment a seek is supposed to
  /// be clean.
  Future<void> seek(int targetUs) async {
    if (_closed) return;
    final before = await _seekGeneration();
    await _sink.suspend();
    try {
      await _worker.request<Object?>(<Object?>['seek', targetUs]);
      // Wait for the pump to actually reach the seek: it may have been mid
      // decode, and resuming before it has cleared would play the old
      // position's tail.
      for (var i = 0; i < 100; i++) {
        if (await _seekGeneration() != before) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Position now advances from the seek target, against the ring's
      // monotonic cursor.
      _baselinePtsUs = targetUs;
      _baselineFrames = _sink.ring.framesConsumed;
    } on Object {
      // A failed seek leaves the stream where it was; the caller sees the
      // position not move rather than an exception out of a transport control.
    } finally {
      // Back to whatever the caller had, NOT unconditionally running: seeking
      // a paused player must leave it paused, or a scrub starts playback.
      if (!_paused) await _sink.resume();
    }
  }

  Future<int> _seekGeneration() async {
    try {
      final stats = await _worker.request<Object?>('stats');
      return ((stats! as Map<String, Object?>)['seekGeneration'] as int?) ?? 0;
    } on Object {
      return -1;
    }
  }

  /// True once the worker has decoded the last packet AND the device has played
  /// everything it wrote.
  Future<bool> isEnded() async {
    if (_closed) return true;
    if (_sink.ring.availableFrames > 0) return false;
    try {
      final stats = await _worker.request<Object?>('stats');
      return ((stats! as Map<String, Object?>)['eof'] as bool?) ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _worker.request<Object?>('stop');
    } on Object {
      // Already gone; the close below is what actually releases it.
    }
    await _worker.close(grace: const Duration(seconds: 1));
    await _sink.close();
  }
}
