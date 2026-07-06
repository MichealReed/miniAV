/// Tests for the [FfmpegShim.ensureMta] / `miniav_shim_ensure_mta` export
/// added in ABI v12 to unblock QSV and MediaFoundation encoder init on Windows.
///
/// Validates:
///   1. [FfmpegShim.kExpectedAbiVersion] is 13.
///   2. On Windows with a loaded shim: [ensureMta] returns 0 (S_OK) or -1
///      (RPC_E_CHANGED_MODE — STA thread); never throws.
///   3. Calling [ensureMta] twice on the same thread is safe (idempotent in
///      the MTA case, still -1 in the STA case).
///   4. On non-Windows platforms [ensureMta] is a no-op returning 0.
@TestOn('vm')
library;

import 'dart:io';

import 'package:miniav_tools_ffmpeg/miniav_tools_ffmpeg.dart';
import 'package:miniav_tools_ffmpeg/src/ffmpeg_shim.dart';
import 'package:test/test.dart';

void main() {
  group('FfmpegShim.ensureMta', () {
    test('kExpectedAbiVersion is 13', () {
      expect(FfmpegShim.kExpectedAbiVersion, equals(13));
    });

    test('returns 0 on non-Windows (no-op)', () {
      if (Platform.isWindows) {
        markTestSkipped('Non-Windows test');
        return;
      }
      final shim = FfmpegShim.tryLoad();
      // On non-Windows the shim may not exist, but the Dart guard still fires.
      // If the shim IS present, ensureMta must return 0.
      if (shim == null) {
        markTestSkipped('Shim not available on this platform');
        return;
      }
      expect(shim.ensureMta(), equals(0));
    });

    test('returns 0 or -1 on Windows and never throws', () {
      if (!Platform.isWindows) {
        markTestSkipped('Windows-only test');
        return;
      }
      final shim = FfmpegShim.tryLoad();
      if (shim == null) {
        markTestSkipped('Shim asset not available (run flutter build first)');
        return;
      }

      // The Dart unit-test runner thread may be STA (Flutter UI) or MTA.
      // Either result is valid; what matters is no exception and a defined
      // return value.
      final result = shim.ensureMta();
      expect(
        result,
        anyOf(equals(0), equals(-1)),
        reason:
            'ensureMta must return 0 (MTA ok) or -1 (STA blocked), got $result',
      );
    });

    test('calling ensureMta twice is safe', () {
      if (!Platform.isWindows) {
        markTestSkipped('Windows-only test');
        return;
      }
      final shim = FfmpegShim.tryLoad();
      if (shim == null) {
        markTestSkipped('Shim asset not available');
        return;
      }

      final first = shim.ensureMta();
      final second = shim.ensureMta();

      // Both calls must agree (same thread, same COM state).
      expect(
        second,
        equals(first),
        reason: 'Two calls on same thread should return same value',
      );
    });

    test('shim ABI version matches kExpectedAbiVersion', () {
      if (!Platform.isWindows) {
        markTestSkipped('Shim only ships on Windows');
        return;
      }
      final shim = FfmpegShim.tryLoad();
      if (shim == null) {
        markTestSkipped('Shim asset not available');
        return;
      }
      expect(shim.abiVersion(), equals(FfmpegShim.kExpectedAbiVersion));
    });
  });
}
