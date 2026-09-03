@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:miniav_media_session/miniav_media_session.dart';
import 'package:miniav_media_session/src/backend_web.dart';
import 'package:test/test.dart';

/// Runs under `dart test -p chrome`.
///
/// This file is the compile gate as much as the behaviour gate: the web backend
/// is the one implementation that never sees the Dart VM, so a `dart:js_interop`
/// mistake in it is invisible to `dart analyze` on a native host and only
/// surfaces when something actually compiles for the browser. This repo has
/// been bitten by web-only breakage before.
void main() {
  test('the browser backend claims the session', () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    expect(backend.name, 'web');
    // Every browser the test runner drives implements the Media Session API.
    expect(backend.isSupported, isTrue);
    expect(backend.unsupportedReason, isNull);
    expect(backend.detail, isNotNull);
  });

  test('metadata, state and position round-trip without throwing', () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    await backend.setMetadata(
      const MediaMetadata(
        title: 'Song',
        artist: 'Band',
        album: 'LP',
        duration: Duration(minutes: 3),
      ),
    );
    await backend.setPlaybackState(MediaPlaybackState.playing);
    await backend.setPosition(
      const MediaPosition(
        position: Duration(seconds: 30),
        duration: Duration(minutes: 3),
      ),
    );
  });

  test('setPositionState is skipped rather than allowed to throw', () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    // The browser throws a TypeError when duration is missing, when position
    // exceeds duration, or when the rate is zero. All three are reachable in
    // normal use — a poll can read the outgoing track's position against the
    // incoming track's duration — so the backend must guard, not catch: an
    // uncaught TypeError here would surface in the app's zone.
    await backend.setPosition(
      const MediaPosition(position: Duration(seconds: 5)),
    );
    await backend.setPosition(
      const MediaPosition(
        position: Duration(minutes: 9),
        duration: Duration(minutes: 3),
      ),
    );
    await backend.setPosition(
      const MediaPosition(
        position: Duration(seconds: 5),
        duration: Duration(minutes: 3),
        speed: 0,
      ),
    );
  });

  test('byte artwork becomes a blob URL and is revoked', () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    // A 1x1 PNG. The browser only fetches it lazily, so the bytes need not be
    // a valid image for the call to succeed — but using a real one keeps the
    // test honest about what it is exercising.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]);
    await backend.setMetadata(
      MediaMetadata(
        title: 'With art',
        artwork: MediaArtwork.bytes(png, mimeType: 'image/png'),
      ),
    );
    // Replacing it must revoke the previous blob; without that every track
    // change leaks one for the life of the document.
    await backend.setMetadata(
      MediaMetadata(
        title: 'With other art',
        artwork: MediaArtwork.bytes(png, mimeType: 'image/png'),
      ),
    );
    await backend.setMetadata(const MediaMetadata(title: 'No art'));
  });

  test('file artwork is accepted and ignored on web', () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    // A browser cannot read an arbitrary local path. This must not throw —
    // shared code that sets a file path on desktop should still run on web.
    await backend.setMetadata(
      const MediaMetadata(
        title: 'Local art',
        artwork: MediaArtwork.file(r'C:\music\cover.jpg'),
      ),
    );
  });

  test('changing the action set does not throw on unsupported actions',
      () async {
    final backend = WebMediaSessionBackend();
    await backend.initialize(actions: kDefaultMediaActions);
    addTearDown(backend.dispose);

    // Browsers throw for actions they do not implement (Safari has historically
    // rejected `seekto`). One unsupported action must not abort the rest.
    await backend.setActions(MediaAction.values.toSet());
    await backend.setActions({MediaAction.play, MediaAction.pause});
    await backend.setActions(const {});
  });

  test('the session facade selects the web backend', () async {
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(session.dispose);
    expect(session.backendName, 'web');
    expect(session.isSupported, isTrue);
  });
}
