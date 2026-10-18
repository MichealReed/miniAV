/// Recording the mouse cursor.
///
/// miniAV has had the toggle since before this package existed; the recorder
/// never called it, so every recording made through `addScreen` was
/// cursor-less with no way to say otherwise.
///
/// The part that fails silently is the ORDER. `MiniAV_Screen_SetCaptureCursor`
/// returns `MINIAV_ERROR_INVALID_OPERATION` once the context is configured,
/// because the backends read the flag when they build the capture session — so
/// a call in the wrong place draws no cursor and does not obviously fail
/// either. Nothing in the OUTPUT distinguishes that from a recording where the
/// pointer simply never moved, which is why this asserts on what the platform
/// says rather than on the file.
@TestOn('vm')
library;

import 'dart:io';

import 'package:miniav/miniav.dart';
import 'package:miniav_recorder/miniav_recorder.dart';
import 'package:miniav_recorder/src/recorder_source.dart';
import 'package:miniav_tools/miniav_tools.dart';
import 'package:test/test.dart';

void main() {
  test('the source defaults to no cursor, matching every backend', () {
    // Changing this default would put a pointer into every existing
    // consumer's recordings without them asking.
    const src = ScreenRecorderSource(
      codec: VideoCodec.h264,
      hwAccel: HwAccelPreference.preferred,
    );
    expect(src.captureCursor, isFalse);
  });

  group('against the real platform', () {
    late List<String> log;

    setUp(() {
      log = [];
      Recorder.setLogCallback((_, __, message) => log.add(message));
    });
    tearDown(() {
      Recorder.setLogCallback(null);
    });

    Future<void> record({required bool cursor}) async {
      final tmp = Directory.systemTemp.createTempSync('cursor');
      final rec = (RecorderBuilder()
            ..addScreen(fps: 30, captureCursor: cursor)
            ..addFileOutput('${tmp.path}/c.mp4'))
          .build();
      try {
        await rec.start();
        expect(rec.state, RecorderState.running,
            reason: 'asking for a cursor must not stop a recording starting');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } finally {
        try {
          await rec.stop();
        } catch (_) {}
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    }

    bool skip() {
      if (!Platform.isWindows) {
        markTestSkipped('Screen capture is Windows-only here.');
        return true;
      }
      return false;
    }

    test('captureCursor: true reaches the capture session', () async {
      if (skip()) return;
      if ((await MiniScreen.enumerateDisplays()).isEmpty) {
        markTestSkipped('No displays to capture.');
        return;
      }
      await record(cursor: true);

      // The recorder's OWN line, not the platform's. Deliberate: miniAV's
      // native log callback is process-global, so a concurrent suite's
      // recording writes into this list and this test's lines can go to
      // someone else's — reading it made this assertion depend on what else
      // happened to be running.
      //
      // And it proves the same thing. The platform REFUSES setCaptureCursor
      // once the context is configured, so this line only exists if the call
      // landed before the session was built.
      expect(log, contains('screen: cursor capture enabled.'),
          reason: 'either the request never reached the platform, or it '
              'landed after configureDisplay and was refused');
      // NOT covered here: that the call carries `true` rather than `false`.
      // This line witnesses that the call HAPPENED and that it happened in
      // time, not what it argued for — the platform's own answer would say,
      // and reading it is what made this test depend on which other suites
      // were recording at the same moment. The guard and the argument are one
      // expression in the recorder so they cannot disagree by accident.
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('the default asks for nothing at all', () async {
      if (skip()) return;
      if ((await MiniScreen.enumerateDisplays()).isEmpty) {
        markTestSkipped('No displays to capture.');
        return;
      }
      await record(cursor: false);

      // The recorder skips the call entirely for `false`, because that is
      // already every backend's default: one less way for a cosmetic setting
      // to fail a session. So the witness must be absent.
      expect(log, isNot(contains('screen: cursor capture enabled.')),
          reason: 'nothing asked for a cursor');
      expect(log.any((l) => l.contains('would not enable cursor capture')),
          isFalse,
          reason: 'and nothing tried and failed either');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
