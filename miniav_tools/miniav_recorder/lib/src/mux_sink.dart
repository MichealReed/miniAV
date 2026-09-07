/// The container writer behind a file sink, wherever it happens to run.
///
/// Two implementations: one that calls a [Muxer] on this isolate, and one that
/// talks to a worker. The recorder does not care which it has — except that
/// with the worker, `finish()` no longer blocks the isolate that called
/// [Recorder.stop].
library;

import 'dart:typed_data';

import 'package:miniav_tools/miniav_tools.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart'
    show Mp4ConfigChange, Mp4Muxer;
import 'package:miniav_tools_platform_interface/miniav_tools_platform_interface.dart';

/// What a container writer has to say for itself once the file is closed.
///
/// Deliberately strings and ints: this crosses an isolate boundary, and the
/// alternative was making every diagnostic type sendable so the recorder could
/// re-format it on the other side.
class MuxFinishReport {
  const MuxFinishReport({
    this.timingRepairs = const [],
    this.tracksMissingConfig = const [],
  });

  /// One line per track whose decode order had to be repaired. Empty is the
  /// normal case.
  final List<String> timingRepairs;

  /// Tracks whose encoder never published a configuration record. Their
  /// samples are in the file and their sample entry is not, so they will not
  /// decode — and the rest of the file is sound.
  final List<int> tracksMissingConfig;

  bool get isClean => timingRepairs.isEmpty && tracksMissingConfig.isEmpty;
}

/// Somewhere to write encoded packets that ends in a container.
abstract interface class MuxSink {
  /// For the log line that says which writer got the file.
  String get backendName;

  Future<void> writePacket(EncodedPacket packet);

  /// Hand the container a track's codec configuration record.
  ///
  /// Returns null for a writer with no such notion; otherwise what changed.
  /// See [Recorder.updateTrackConfig] for why this arrives when it does.
  Future<Mp4ConfigChange?> setTrackConfig(int trackIndex, Uint8List config);

  /// Write the index and close the file. The expensive one.
  Future<MuxFinishReport> finish();

  Future<void> close();
}

/// A [MuxSink] that runs the muxer right here.
///
/// What the recorder always did. Still the path for containers the worker does
/// not host — see `WorkerMuxSink` for which those are and why.
class InProcessMuxSink implements MuxSink {
  InProcessMuxSink(this._muxer);

  final Muxer _muxer;

  @override
  String get backendName => _muxer.backendName;

  @override
  Future<void> writePacket(EncodedPacket packet) => _muxer.writePacket(packet);

  @override
  Future<Mp4ConfigChange?> setTrackConfig(
    int trackIndex,
    Uint8List config,
  ) async {
    final p = _muxer.platform;
    if (p is! Mp4Muxer) return null;
    return p.setTrackConfig(trackIndex, config);
  }

  @override
  Future<MuxFinishReport> finish() async {
    await _muxer.finish();
    final p = _muxer.platform;
    if (p is! Mp4Muxer) return const MuxFinishReport();
    return MuxFinishReport(
      timingRepairs: [
        for (final r in p.timingReports)
          if (!r.isClean) '$r',
      ],
      tracksMissingConfig: p.tracksMissingConfig,
    );
  }

  @override
  Future<void> close() => _muxer.close();
}
