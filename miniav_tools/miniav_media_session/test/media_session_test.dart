@TestOn('vm')
library;

import 'package:miniav_media_session/miniav_media_session.dart';
import 'package:test/test.dart';

/// End-to-end over the real chain: Dart → dart:ffi → the
/// `miniav_media_session_native` code asset built by hook/build.dart.
///
/// These tests pass whether or not a real OS backend is compiled in. That is
/// deliberate — they assert the CONTRACT (a session is always obtainable, and
/// always tells the truth about whether the shell accepted it), not that any
/// particular platform is wired up yet. When a real backend lands, the only
/// change here is that `isSupported` flips to true on that platform.
void main() {
  tearDown(() async {
    await MiniavMediaSession.current?.dispose();
  });

  test('create never throws on an unsupported platform', () async {
    // A missing shell integration must not be able to stop playback. Apps call
    // this unconditionally and check isSupported afterwards.
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(session.dispose);
    expect(session, isNotNull);
  });

  test('an unsupported backend says why, rather than pretending', () async {
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(session.dispose);

    if (session.isSupported) {
      expect(session.unsupportedReason, isNull);
    } else {
      // The placeholder backend names the file that would implement it. A
      // backend that reported success while publishing nothing would be
      // indistinguishable from a working one whose card the shell simply is
      // not showing — the failure mode that hid miniAV's per-process loopback
      // bug for months.
      expect(session.unsupportedReason, isNotEmpty);
      expect(session.unsupportedReason, contains('not implemented'));
    }
  });

  test('setters are safe to call when unsupported', () async {
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(session.dispose);

    await session.setMetadata(
      const MediaMetadata(
        title: 'Song',
        artist: 'Band',
        duration: Duration(minutes: 3),
      ),
    );
    await session.setPlaybackState(MediaPlaybackState.playing);
    await session.setPosition(
      const MediaPosition(
        position: Duration(seconds: 10),
        duration: Duration(minutes: 3),
      ),
    );
    await session.setActions({MediaAction.play, MediaAction.pause});
    expect(session.actions, containsAll([MediaAction.play]));
  });

  test('a second concurrent session is refused', () async {
    final first = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(first.dispose);

    // The OS has exactly one session per app. Two live instances could only
    // fight over the lock screen, so this is an error at the call site rather
    // than a mystery about which one won.
    await expectLater(
      MiniavMediaSession.create(appName: 'miniav test 2'),
      throwsA(isA<StateError>()),
    );
  });

  test('dispose releases the slot so a new session can be created', () async {
    final first = await MiniavMediaSession.create(appName: 'miniav test');
    await first.dispose();
    expect(MiniavMediaSession.current, isNull);

    final second = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(second.dispose);
    expect(MiniavMediaSession.current, same(second));
  });

  test('dispose is idempotent', () async {
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    await session.dispose();
    await session.dispose();
  });

  test('the commands stream is available even when unsupported', () async {
    final session = await MiniavMediaSession.create(appName: 'miniav test');
    addTearDown(session.dispose);
    // Apps subscribe before knowing whether the platform is wired up; the
    // stream must exist either way rather than being null-guarded everywhere.
    final sub = session.commands.listen((_) {});
    addTearDown(sub.cancel);
  });
}
