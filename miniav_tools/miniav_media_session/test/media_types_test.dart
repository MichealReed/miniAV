import 'dart:typed_data';

import 'package:miniav_media_session/miniav_media_session.dart';
import 'package:test/test.dart';

void main() {
  group('MediaMetadata equality', () {
    test('identical content compares equal so redundant pushes are dropped', () {
      const a = MediaMetadata(title: 'Song', artist: 'Band', album: 'LP');
      const b = MediaMetadata(title: 'Song', artist: 'Band', album: 'LP');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('any differing field compares unequal', () {
      const base = MediaMetadata(title: 'Song');
      expect(base, isNot(equals(base.copyWith(title: 'Other'))));
      expect(base, isNot(equals(base.copyWith(artist: 'Band'))));
      expect(
        base,
        isNot(equals(base.copyWith(duration: const Duration(minutes: 3)))),
      );
      expect(base, isNot(equals(base.copyWith(trackNumber: 2))));
    });

    test('byte artwork compares by buffer identity, not content', () {
      // Deep-comparing a multi-megabyte cover on every poll tick would cost
      // more than the platform push the comparison exists to avoid.
      final bytes = Uint8List.fromList([1, 2, 3]);
      final sameBuffer = MediaArtwork.bytes(bytes, mimeType: 'image/png');
      final otherBuffer = MediaArtwork.bytes(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );

      expect(
        MediaArtwork.bytes(bytes, mimeType: 'image/png'),
        equals(sameBuffer),
      );
      expect(sameBuffer, isNot(equals(otherBuffer)));
    });

    test('file and uri artwork compare by value', () {
      expect(
        const MediaArtwork.file(r'C:\music\cover.jpg'),
        equals(const MediaArtwork.file(r'C:\music\cover.jpg')),
      );
      expect(
        MediaArtwork.uri(Uri.parse('https://x/y.png')),
        equals(MediaArtwork.uri(Uri.parse('https://x/y.png'))),
      );
      expect(
        const MediaArtwork.file('a'),
        isNot(equals(const MediaArtwork.file('b'))),
      );
    });
  });

  group('MediaPosition', () {
    test('compares by value', () {
      const a = MediaPosition(
        position: Duration(seconds: 5),
        duration: Duration(minutes: 3),
      );
      const b = MediaPosition(
        position: Duration(seconds: 5),
        duration: Duration(minutes: 3),
      );
      expect(a, equals(b));
      expect(a.speed, 1.0);
    });

    test('a differing playhead is not equal, so the push is not dropped', () {
      const a = MediaPosition(position: Duration(seconds: 5));
      const b = MediaPosition(position: Duration(seconds: 6));
      expect(a, isNot(equals(b)));
    });
  });

  group('MediaCommand', () {
    test('carries a seek target', () {
      const c = MediaCommand(
        MediaAction.seekTo,
        position: Duration(seconds: 30),
      );
      expect(c.action, MediaAction.seekTo);
      expect(c.position, const Duration(seconds: 30));
      expect(c.offset, isNull);
    });

    test('compares by value', () {
      expect(
        const MediaCommand(MediaAction.play),
        equals(const MediaCommand(MediaAction.play)),
      );
      expect(
        const MediaCommand(MediaAction.play),
        isNot(equals(const MediaCommand(MediaAction.pause))),
      );
    });
  });

  test('default action set advertises no playlist controls', () {
    // Declaring next/previous lights up skip buttons in the shell. With no
    // queue behind them they would be dead controls, which is worse than
    // absent ones.
    expect(kDefaultMediaActions, isNot(contains(MediaAction.next)));
    expect(kDefaultMediaActions, isNot(contains(MediaAction.previous)));
    expect(kDefaultMediaActions, contains(MediaAction.playPause));
    expect(kDefaultMediaActions, contains(MediaAction.seekTo));
  });
}
