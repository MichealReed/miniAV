// Manual probe: claims a real OS media session, publishes a fake track, and
// holds it so the shell card can be eyeballed and hardware media keys tried.
//
//   dart run tool/media_session_probe.dart
//
// Plays NO audio — it only publishes metadata, so it is safe to run at any
// time and will not interrupt whatever is actually playing. (It will, however,
// take over the media keys for as long as it runs, because that is the whole
// point of owning the session.)
//
// Prints every command the OS sends, so pressing a media key on the keyboard
// should produce a line here.

import 'dart:async';
import 'dart:io';

import 'package:miniav_media_session/miniav_media_session.dart';

Future<void> main(List<String> args) async {
  final holdSeconds = args.isEmpty ? 30 : int.tryParse(args.first) ?? 30;

  final session = await MiniavMediaSession.create(
    appName: 'miniav media session probe',
    actions: {
      MediaAction.play,
      MediaAction.pause,
      MediaAction.stop,
      MediaAction.next,
      MediaAction.previous,
      MediaAction.seekTo,
    },
  );

  stdout.writeln('backend        : ${session.backendName}');
  stdout.writeln('isSupported    : ${session.isSupported}');
  stdout.writeln('reason         : ${session.unsupportedReason ?? "-"}');
  stdout.writeln('detail         : ${session.backendDetail ?? "-"}');

  if (!session.isSupported) {
    stdout.writeln(
      '\nNo OS session on this machine/build — nothing further to show.',
    );
    await session.dispose();
    exit(1);
  }

  session.commands.listen((c) => stdout.writeln('COMMAND -> $c'));

  const total = Duration(minutes: 4, seconds: 33);
  await session.setMetadata(
    const MediaMetadata(
      title: 'miniav probe track',
      artist: 'miniav_media_session',
      album: 'Diagnostics',
      duration: total,
      trackNumber: 1,
    ),
  );
  await session.setPlaybackState(MediaPlaybackState.playing);

  stdout.writeln(
    '\nSession is live for ${holdSeconds}s.\n'
    'Check the volume flyout (press a volume key) for a card titled\n'
    '"miniav probe track", and try the media keys — each press should print\n'
    'a COMMAND line below.\n',
  );

  // Advance a simulated playhead so the shell progress bar is visibly moving,
  // which is the quickest way to tell UpdateTimelineProperties is landing.
  var elapsed = Duration.zero;
  final ticker = Timer.periodic(const Duration(milliseconds: 500), (_) async {
    elapsed += const Duration(milliseconds: 500);
    if (elapsed > total) elapsed = Duration.zero;
    await session.setPosition(
      MediaPosition(position: elapsed, duration: total),
    );
  });

  await Future<void>.delayed(Duration(seconds: holdSeconds));
  ticker.cancel();
  await session.dispose();
  stdout.writeln('Session released.');
}
