@TestOn('vm')
library;

import 'package:miniav_media_session/src/backend_mpris.dart';
import 'package:miniav_media_session/src/media_playback.dart';
import 'package:test/test.dart';

/// The MPRIS backend is only *selected* on Linux, but it is pure Dart, so its
/// failure path can be exercised anywhere. On a host with no D-Bus session bus
/// — this Windows/macOS CI leg, a container, a root shell — `initialize` must
/// report the situation rather than throw, because an app must not fail to play
/// audio just because the desktop has no bus.
///
/// On a Linux desktop leg this same test takes the other branch and asserts the
/// name was actually claimed.
void main() {
  test('initialize never throws, whether or not a session bus exists', () async {
    final backend = MprisMediaSessionBackend(appName: 'miniav test');
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    if (backend.isSupported) {
      expect(backend.unsupportedReason, isNull);
      expect(backend.detail, contains('org.mpris.MediaPlayer2'));
    } else {
      expect(backend.unsupportedReason, isNotEmpty);
    }
  });

  test('setters are safe with no bus and do not throw', () async {
    final backend = MprisMediaSessionBackend(appName: 'miniav test');
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    await backend.setPlaybackState(MediaPlaybackState.playing);
    await backend.setPosition(
      const MediaPosition(
        position: Duration(seconds: 3),
        duration: Duration(minutes: 4),
      ),
    );
    await backend.setActions({MediaAction.play});
  });

  test('the bus name is a legal D-Bus name element', () async {
    // D-Bus name elements are [A-Za-z_][A-Za-z0-9_]*. An app called
    // "My App 2.0" would otherwise produce "org.mpris.MediaPlayer2.My App 2.0",
    // which the bus rejects outright — the session would silently never exist.
    final backend = MprisMediaSessionBackend(appName: 'My App 2.0!');
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    final detail = backend.detail;
    if (detail != null) {
      final name = detail.split(' ').last;
      expect(
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
            .hasMatch(name),
        isTrue,
        reason: 'bus name "$name" is not a legal D-Bus name',
      );
    }
  });

  test('dispose is idempotent with no bus', () async {
    final backend = MprisMediaSessionBackend(appName: 'miniav test');
    await backend.initialize(actions: kDefaultMediaActions);
    await backend.dispose();
    await backend.dispose();
  });
}
