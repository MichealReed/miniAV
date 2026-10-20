/// What [Recorder.stop] is doing, while it does it.
///
/// Stopping a recording is not instant and never was. The container index is
/// built from every sample in the file, encoders are flushed, capture contexts
/// are destroyed — and all of it is synchronous work that used to run on
/// whatever isolate called stop, which in a desktop app is the one drawing the
/// UI. The muxing moved to a worker; this is how the app finds out how far
/// along it is, so it can show something other than a frozen window.
///
/// Phases, not a fraction. The expensive step is a single call into a
/// container writer that reports nothing while it runs, and inventing a
/// percentage over it would be a progress bar that lies.
library;

/// The step [Recorder.stop] is on.
///
/// In order. A recording that stops cleanly passes through each exactly once,
/// ending at [done].
enum RecorderFinalizePhase {
  /// Capture is being stopped. Fast, unless a platform capture thread is wedged.
  stoppingCapture,

  /// Waiting for encodes that were already in flight when stop was called.
  draining,

  /// Flushing the encoders and pushing their trailing packets to the sinks.
  flushing,

  /// Writing the container index — `moov` for MP4. Proportional to the number
  /// of SAMPLES, not to the file size: roughly a quarter of a million entries
  /// for an hour of 30fps video plus AAC. The longest phase for a long
  /// recording, and the reason any of this is reported.
  writingIndex,

  /// Closing encoders, capture contexts and files.
  closing,

  /// Everything is on disk and released.
  done,
}

/// One step of a recording being finalized.
class RecorderFinalizeProgress {
  const RecorderFinalizeProgress({
    required this.phase,
    required this.elapsed,
    this.path,
  });

  final RecorderFinalizePhase phase;

  /// Since [Recorder.stop] was called.
  final Duration elapsed;

  /// The output this phase concerns, where it concerns exactly one — the file
  /// whose index is being written. Null for the phases that span the whole
  /// recorder.
  final String? path;

  @override
  String toString() => 'RecorderFinalizeProgress(${phase.name}'
      '${path == null ? '' : ' $path'}, ${elapsed.inMilliseconds}ms)';
}
