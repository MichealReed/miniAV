/// `registerFirstPartyBackends()` must actually populate the registry, and
/// mf_encode must then be what a hardware H.264 encode selects.
///
/// The first half is not a formality. The obvious way to write this — a
/// top-level `final x = register();` in the library — does NOT work: Dart
/// top-level finals are lazy, they run on first *read*, and nothing reads them.
/// That failure is silent in the worst way, because the app keeps encoding
/// happily via FFmpeg and reports success at every step. The only honest check
/// is against the registry itself.
@TestOn('vm')
library;

import 'dart:io';

import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:test/test.dart';

void main() {
  test('registerFirstPartyBackends populates the registry', () {
    expect(registerFirstPartyBackends(), isTrue,
        reason: 'first call registered nothing');
    final names =
        MiniAVToolsPlatform.instance.backends.map((b) => b.name).toSet();
    expect(names, contains(MinigpuBackend.backendName));
    expect(names, contains(ContainerFramingBackend.backendName));
    if (Platform.isWindows) {
      expect(names, contains(MfEncodeBackend.backendName));
      expect(names, contains(MfDecodeBackend.backendName));
    }
    expect(registerFirstPartyBackends(), isFalse,
        reason: 'not idempotent — a second call re-registered something, so '
            'the recorder calling it per start() would grow the registry');
  });

  test('mf_encode is what a hardware H.264 encode negotiates to', () async {
    if (!Platform.isWindows) return;
    registerFirstPartyBackends();
    if (!MfEncodeBackend.hasHardwareMft(VideoCodec.h264)) {
      markTestSkipped('no hardware H.264 MFT on this machine');
      return;
    }
    // The real question is not "is it registered" but "does it win". Only
    // backends present in this process compete, and this test deliberately does
    // NOT import miniav_tools_ffmpeg — see the note below.
    final b = MiniAVToolsPlatform.instance.backends
        .where((x) => x.supportsEncode(VideoCodec.h264, hwAccel: true))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
    expect(b, isNotEmpty);
    expect(b.first.name, MfEncodeBackend.backendName);
  });
}
