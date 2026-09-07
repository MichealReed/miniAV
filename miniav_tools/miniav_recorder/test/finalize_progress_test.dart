/// Stopping a real recording, reported while it happens.
///
/// The worker protocol is covered by `worker_mux_sink_test.dart`; this is the
/// wiring — that a recorder actually routes its MP4 through the worker, and
/// that the phases reach an app in order. Both halves have been wrong before
/// in ways every unit test agreed with.
@TestOn('vm')
library;

import 'dart:io';

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

void main() {
  test('stopping an MP4 recording reports its phases in order', () async {
    if (!Platform.isWindows) {
      markTestSkipped('Screen capture is Windows-only here.');
      return;
    }
    final displays = await MiniScreen.enumerateDisplays();
    if (displays.isEmpty) {
      markTestSkipped('No displays to capture.');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('finalize');
    final path = '${tmp.path}/session.mp4';
    final log = <String>[];
    Recorder.setLogCallback((_, __, message) => log.add(message));

    final phases = <RecorderFinalizePhase>[];
    final rec = (RecorderBuilder()
          ..addScreen(fps: 30)
          ..addFileOutput(path))
        .build();
    rec.finalizeProgress.listen((p) => phases.add(p.phase));

    try {
      await rec.start();
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      try {
        await rec.stop();
      } catch (_) {}
      Recorder.setLogCallback(null);
    }
    // Broadcast delivery is asynchronous by contract, so the last event is
    // still in flight when stop() returns. Asserting without this is a race
    // that passes on a fast machine.
    await Future<void>.delayed(Duration.zero);

    // Ordering, not exact membership: writingIndex may be announced by the
    // worker (for the file) or by the fallback, and a recorder with no file
    // sink would skip it entirely. What must hold is that nothing arrives out
    // of order and that it ends.
    expect(phases, isNotEmpty);
    expect(phases.first, RecorderFinalizePhase.stoppingCapture);
    expect(phases.last, RecorderFinalizePhase.done);
    final order = RecorderFinalizePhase.values;
    for (var i = 1; i < phases.length; i++) {
      expect(
        order.indexOf(phases[i]),
        greaterThanOrEqualTo(order.indexOf(phases[i - 1])),
        reason: 'phase ${phases[i].name} came after ${phases[i - 1].name}',
      );
    }

    // And the container it was writing: the point of the move is that this
    // file is assembled somewhere other than the isolate that called stop.
    final muxLine = log.firstWhere(
      (l) => l.startsWith('muxer = ') && l.contains('.mp4'),
      orElse: () => '',
    );
    expect(muxLine, contains('on a worker'),
        reason: 'an MP4 recording should route through the worker; '
            'in-process means the fallback fired — the log says why');

    final bytes = File(path).readAsBytesSync();
    expect(bytes, isNotEmpty);
    final d = Mp4Demuxer.open(bytes);
    expect(d.tracks, isNotEmpty, reason: 'the index was written');
    await d.close();

    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, timeout: const Timeout(Duration(seconds: 90)));
}
