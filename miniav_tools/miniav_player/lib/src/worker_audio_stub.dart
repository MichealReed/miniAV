/// Native stub for the worker-hosted audio track.
///
/// Selected off-web by the conditional import in `player.dart`. There is
/// nothing to stand in for: native already decodes audio on a worker isolate
/// and feeds a real device from a thread that is not the UI thread, so the
/// problem this solves does not exist there. [WorkerAudioTrack.start] returns
/// null and the player runs its ordinary audio pump.
///
/// Every other member throws. That is not laziness — the player only ever holds
/// one of these when [start] handed it one, so a throw here means the guard
/// that keeps this path web-only has been broken, and it should say so loudly
/// rather than return a plausible zero.
library;

import 'dart:typed_data';

/// A worker-hosted audio track. Never available off-web.
class WorkerAudioTrack {
  WorkerAudioTrack._();

  /// Always null off-web.
  static Future<WorkerAudioTrack?> start({
    required Uint8List bytes,
    required int sampleRate,
    required int channels,
    required Duration depth,
    double volume = 1.0,
  }) async => null;

  static Never _webOnly() =>
      throw UnsupportedError('worker-hosted audio is web only');

  /// True playback position from the audio device. See the web implementation.
  int? get positionUs => _webOnly();

  /// Frames the audio thread wanted and could not have.
  int get underruns => _webOnly();

  /// How much audio is buffered ahead.
  Duration get buffered => _webOnly();

  /// Output gain, 0..1.
  double get volume => _webOnly();
  set volume(double value) => _webOnly();

  /// Suspends the audio thread.
  Future<void> pause() => _webOnly();

  /// Resumes the audio thread.
  Future<void> resume() => _webOnly();

  /// Seeks the worker's demuxer and clears the ring.
  Future<void> seek(int targetUs) => _webOnly();

  /// Whether the stream has been fully decoded and fully played.
  Future<bool> isEnded() => _webOnly();

  /// Stops the worker and releases the audio context.
  Future<void> close() => _webOnly();
}
