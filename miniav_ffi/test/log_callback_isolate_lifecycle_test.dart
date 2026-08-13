/// Regression test for the process-global native-log callback lifecycle.
///
/// `MiniAV_SetLogCallback` is a PROCESS-GLOBAL registry. When Dart registered
/// a [NativeCallable] there, the pointer was owned by ONE isolate — and the
/// VM deletes the trampoline when that isolate exits, while miniav_c keeps
/// the pointer. The next `miniav_log()` from a capture/worker thread, or from
/// inside a leaf FFI call such as `MiniAV_ReleaseBuffer`, then aborted the
/// whole VM process:
///
///     runtime_entry.cc: error: Callback invoked after it has been deleted
///     runtime_entry.cc: error: Cannot invoke native callback from a leaf call
///
/// A whole-suite `dart test` run reproduces it every time, because each test
/// FILE is a separate isolate inside ONE VM process. This test pins the
/// mechanism on its own: register a log sink here, register one in a
/// short-lived isolate, kill that isolate, then force native log output.
/// Under the old function-pointer path the process dies at that point; under
/// the native-port path the dead port is simply inert.
///
/// It also pins the documented semantics: delivery is PROCESS-GLOBAL and
/// LAST WRITER WINS, so once another isolate registers, this isolate stops
/// receiving until it registers again.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:miniav_ffi/miniav_ffi.dart';
import 'package:test/test.dart';

/// Platform-interface log level indices: none=0, trace=1, debug=2, info=3.
const int _trace = 1;

/// Entry point for the short-lived isolate. Takes over the process-global
/// registration, reports readiness, then idles until the parent kills it.
void _childRegistersLogSink(SendPort ready) {
  final platform = MiniAVFFIPlatform();
  platform.setLogLevel(_trace);
  platform.setLogCallback((level, message) {
    // Deliberately empty: what matters is that this isolate OWNS the
    // registration when it dies.
  });
  ready.send(true);
  // Do not return — the parent kills us, which is what makes the
  // registration go stale mid-process.
}

/// Enumerating cameras emits several `miniav_log` lines at DEBUG/INFO from
/// the native backend regardless of how many devices exist.
Future<void> _forceNativeLogOutput(MiniAVFFIPlatform platform) async {
  await platform.camera.enumerateDevices();
}

void main() {
  late MiniAVFFIPlatform platform;

  setUpAll(() {
    platform = MiniAVFFIPlatform();
    platform.setLogLevel(_trace);
  });

  tearDownAll(() {
    // Leave the native library on its own sink so later suites in this
    // process are not fed by a port we are about to drop.
    MiniAVFFIPlatform().setLogCallback(null);
  });

  test('native log survives an isolate that registered and exited', () async {
    final lines = <String>[];
    platform.setLogCallback((level, message) => lines.add(message));
    addTearDown(() => platform.setLogCallback(null));

    // 1. Positive control for the harness itself: this isolate really does
    //    receive native log lines. Without this the rest could pass
    //    vacuously.
    await _forceNativeLogOutput(platform);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      lines,
      isNotEmpty,
      reason: 'no native log lines reached Dart — the test cannot '
          'demonstrate anything about their lifecycle',
    );

    // 2. A second isolate takes over the process-global registration and then
    //    dies, leaving the native side holding its handle.
    final ready = ReceivePort();
    final child = await Isolate.spawn(_childRegistersLogSink, ready.sendPort);
    expect(await ready.first, isTrue);
    ready.close();

    final exited = ReceivePort();
    child.addOnExitListener(exited.sendPort);
    child.kill(priority: Isolate.immediate);
    await exited.first;
    exited.close();

    // 3. THE CRASH POINT. With a NativeCallable the VM aborts the entire
    //    process here. Reaching the next statement is the whole proof.
    lines.clear();
    await _forceNativeLogOutput(platform);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 4. Documented semantics: PROCESS-GLOBAL, LAST WRITER WINS. The dead
    //    child owned the registration, so nothing arrived here — and posting
    //    to its closed port was silent, not fatal.
    expect(
      lines,
      isEmpty,
      reason: 'the last registration (the dead child) should still own the '
          'process-global hook',
    );

    // 5. Re-registering restores delivery to this isolate.
    platform.setLogCallback((level, message) => lines.add(message));
    await _forceNativeLogOutput(platform);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines, isNotEmpty);
  });
}
