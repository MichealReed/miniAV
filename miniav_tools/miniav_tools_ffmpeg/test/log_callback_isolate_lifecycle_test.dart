/// Regression test for the process-global native-log callback lifecycle.
///
/// `av_log_set_callback` is a PROCESS-GLOBAL registry. When Dart registered a
/// [NativeCallable] there, the pointer was owned by ONE isolate — and the VM
/// deletes the trampoline when that isolate exits, while FFmpeg keeps the
/// pointer. The next `av_log` from a codec thread (typically from inside
/// `avcodec_open2`) then aborted the whole VM process:
///
///     runtime_entry.cc: error: Callback invoked after it has been deleted
///     runtime_entry.cc: error: Cannot invoke native callback from a leaf call
///
/// A whole-suite `dart test` run reproduces it every time, because each test
/// FILE is a separate isolate inside ONE VM process. This test pins the
/// mechanism without needing the whole suite: it registers a log sink here,
/// registers one in a short-lived isolate, kills that isolate, then forces
/// native log output. Under the old function-pointer path the process dies
/// during step 3 and this file reports a crash; under the native-port path
/// the dead port is simply inert.
///
/// It also pins the documented semantics: delivery is PROCESS-GLOBAL and
/// LAST WRITER WINS, so after another isolate registers, this isolate stops
/// receiving until it registers again.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:test/test.dart';

const int _avLogDebug = 48;

/// Entry point for the short-lived isolate. Registers a log sink on the
/// process-global av_log hook, reports readiness, then idles until killed.
void _childRegistersLogSink(SendPort ready) async {
  await ensureFFmpegLoaded();
  final shim = FfmpegShim.tryLoad();
  shim?.setFfmpegLogCallback((level, message) {
    // Deliberately empty: the point is that this isolate OWNS the
    // registration when it dies.
  }, level: _avLogDebug);
  ready.send(shim != null);
  // Do not return — the parent kills us, which is what makes the
  // registration go stale mid-process.
}

/// Opens and closes an AAC encoder. `avcodec_open2` is the call that emitted
/// the fatal log line in the original crash.
Future<void> _forceNativeLogOutput() async {
  final backend = FfmpegBackend();
  if (!backend.supportsAudioEncode(AudioCodec.aac)) return;
  final enc = await backend.createAudioEncoder(
    const AudioEncoderConfig(
      codec: AudioCodec.aac,
      sampleRate: 48000,
      channels: 2,
      bitrateBps: 128000,
    ),
  );
  await enc?.close();
}

void main() {
  late FfmpegShim shim;

  setUpAll(() async {
    await ensureFFmpegLoaded();
    final loaded = FfmpegShim.tryLoad();
    if (loaded == null) {
      markTestSkipped('shim not loadable on this host');
      return;
    }
    shim = loaded;
  });

  tearDownAll(() {
    // Leave FFmpeg on its own logger so later suites in this process are not
    // fed by a port we are about to drop.
    FfmpegShim.tryLoad()?.setFfmpegLogCallback(null);
  });

  test(
    'native av_log survives an isolate that registered and exited',
    () async {
      final lines = <String>[];
      shim.setFfmpegLogCallback(
        (level, message) => lines.add(message),
        level: _avLogDebug,
      );
      addTearDown(() => shim.setFfmpegLogCallback(null));

      // 1. Positive control for the harness itself: this isolate really does
      //    receive native log lines. Without this the rest could pass
      //    vacuously.
      await _forceNativeLogOutput();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        lines,
        isNotEmpty,
        reason: 'no native av_log lines reached Dart — the test cannot '
            'demonstrate anything about their lifecycle',
      );

      // 2. A second isolate takes over the process-global registration and
      //    then dies, leaving the native side holding its handle.
      final ready = ReceivePort();
      final child = await Isolate.spawn(_childRegistersLogSink, ready.sendPort);
      final childHasShim = await ready.first as bool;
      ready.close();
      expect(childHasShim, isTrue, reason: 'child isolate could not load shim');

      final exited = ReceivePort();
      child.addOnExitListener(exited.sendPort);
      child.kill(priority: Isolate.immediate);
      await exited.first;
      exited.close();

      // 3. THE CRASH POINT. With a NativeCallable the VM aborts the entire
      //    process here. Reaching the next statement is the whole proof.
      lines.clear();
      await _forceNativeLogOutput();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4. Documented semantics: PROCESS-GLOBAL, LAST WRITER WINS. The dead
      //    child owned the registration, so nothing arrived here — and
      //    posting to its closed port was silent, not fatal.
      expect(
        lines,
        isEmpty,
        reason: 'the last registration (the dead child) should still own the '
            'process-global hook',
      );

      // 5. Re-registering restores delivery to this isolate.
      shim.setFfmpegLogCallback(
        (level, message) => lines.add(message),
        level: _avLogDebug,
      );
      await _forceNativeLogOutput();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(lines, isNotEmpty);
    },
  );

}
