/// Binds a [MiniavPlayer] to the OS media session.
///
/// ```dart
/// final binding = await PlayerMediaSession.attach(
///   player,
///   appName: 'Tunes',
///   metadata: const MediaMetadata(title: 'Song', artist: 'Band'),
/// );
/// // ... hardware media keys now control `player`.
/// await binding.detach();
/// ```
library;

import 'dart:async';

import 'package:miniav_media_session/miniav_media_session.dart';
import 'package:miniav_media_session_flutter/miniav_media_session_flutter.dart';
import 'package:miniav_player/miniav_player.dart';

export 'package:miniav_media_session/miniav_media_session.dart';

/// Keeps an OS media session in step with a [MiniavPlayer], in both directions.
///
/// **Why this polls.** [MiniavPlayer] exposes a complete transport — `isPaused`,
/// `position`, `duration`, `pause()`, `resume()`, `seek()` — but no change
/// notification: no `ValueListenable`, no state stream. So the only way to
/// notice that the app paused playback through its own UI is to look. The
/// session needs a periodic position push anyway (that is how every shell
/// drives its progress bar), so the poll is not pure overhead — but the state
/// half of it is, and it costs up to [pollInterval] of lag before the shell
/// catches up with an in-app pause.
///
/// Commands arriving *from* the OS do not wait for the next tick: they push
/// immediately, because that path knows exactly what changed. Adding a
/// listenable to `MiniavPlayer` would remove the remaining lag and let the
/// interval drop to the position cadence alone.
class PlayerMediaSession {
  final MiniavPlayer player;
  final MiniavMediaSession session;

  /// How often the player is sampled. See the class doc for why this exists.
  final Duration pollInterval;

  /// Jump distance used for [MediaAction.seekForward]/[MediaAction.seekBackward]
  /// when the platform supplies no offset of its own (most do not).
  final Duration defaultSeekStep;

  final FutureOr<void> Function()? _onNext;
  final FutureOr<void> Function()? _onPrevious;

  Timer? _timer;
  StreamSubscription<MediaCommand>? _commandSub;
  bool _detached = false;

  PlayerMediaSession._(
    this.player,
    this.session, {
    required this.pollInterval,
    required this.defaultSeekStep,
    required FutureOr<void> Function()? onNext,
    required FutureOr<void> Function()? onPrevious,
  }) : _onNext = onNext,
       _onPrevious = onPrevious;

  /// Claim the OS session and wire it to [player].
  ///
  /// [actions] defaults to [kDefaultMediaActions], plus [MediaAction.next] and
  /// [MediaAction.previous] when [onNext]/[onPrevious] are supplied — the
  /// player has no queue of its own, so skip controls are only advertised when
  /// the app can actually service them.
  ///
  /// Does not throw when the platform has no session to give; check
  /// [isSupported] afterwards.
  static Future<PlayerMediaSession> attach(
    MiniavPlayer player, {
    required String appName,
    MediaMetadata? metadata,
    Set<MediaAction>? actions,
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration defaultSeekStep = const Duration(seconds: 10),
    FutureOr<void> Function()? onNext,
    FutureOr<void> Function()? onPrevious,
    int? hostWindowHandle,
  }) async {
    // Android's session lives on the JVM and cannot be reached from the core
    // package's code asset, so it is supplied by a companion plugin that has
    // to be pointed at before the first create. No-op elsewhere.
    registerMiniavMediaSessionAndroid();

    final resolved =
        actions ??
        {
          ...kDefaultMediaActions,
          if (onNext != null) MediaAction.next,
          if (onPrevious != null) MediaAction.previous,
        };

    final session = await MiniavMediaSession.create(
      appName: appName,
      actions: resolved,
      hostWindowHandle: hostWindowHandle,
    );

    final binding = PlayerMediaSession._(
      player,
      session,
      pollInterval: pollInterval,
      defaultSeekStep: defaultSeekStep,
      onNext: onNext,
      onPrevious: onPrevious,
    );

    if (metadata != null) await session.setMetadata(metadata);
    binding._commandSub = session.commands.listen(binding._handleCommand);
    binding._timer = Timer.periodic(pollInterval, (_) => binding._sync());
    await binding._sync();
    return binding;
  }

  /// Whether the shell actually accepted the session.
  bool get isSupported => session.isSupported;

  /// Why [isSupported] is false. Null when supported.
  String? get unsupportedReason => session.unsupportedReason;

  /// Describe the track now playing. Call on every track change.
  Future<void> setMetadata(MediaMetadata metadata) =>
      session.setMetadata(metadata);

  Future<void> _sync() async {
    if (_detached) return;
    if (player.isClosed) {
      // A closed player has nothing to show. Tear the card down rather than
      // leaving a frozen one advertising a transport that no longer exists.
      await session.setPlaybackState(MediaPlaybackState.none);
      return;
    }

    await session.setPlaybackState(
      player.isPaused ? MediaPlaybackState.paused : MediaPlaybackState.playing,
    );

    final position = player.position;
    if (position != null) {
      await session.setPosition(
        MediaPosition(
          position: position,
          duration: player.duration,
          // Reporting rate 0 while paused stops the shell extrapolating a
          // playhead that is not moving — otherwise the bar keeps creeping
          // forward between pushes and snaps back on the next one.
          speed: player.isPaused ? 0.0 : 1.0,
        ),
      );
    }
  }

  Future<void> _handleCommand(MediaCommand command) async {
    if (_detached || player.isClosed) return;

    switch (command.action) {
      case MediaAction.play:
        player.resume();
      case MediaAction.pause:
        player.pause();
      case MediaAction.playPause:
        player.isPaused ? player.resume() : player.pause();
      case MediaAction.stop:
        // MiniavPlayer has no stop(): closing it would end the session
        // entirely, and pausing alone leaves the playhead mid-track. Pause and
        // rewind is the closest honest equivalent.
        player.pause();
        if (player.isSeekable) await player.seek(Duration.zero);
      case MediaAction.seekTo:
        final target = command.position;
        if (target != null && player.isSeekable) await player.seek(target);
      case MediaAction.seekForward:
        await _seekBy(command.offset ?? defaultSeekStep);
      case MediaAction.seekBackward:
        await _seekBy(-(command.offset ?? defaultSeekStep));
      case MediaAction.next:
        await _onNext?.call();
      case MediaAction.previous:
        await _onPrevious?.call();
    }

    // Push straight away instead of waiting for the next tick — this path knows
    // what changed, so the shell should not lag behind a button the user just
    // pressed on it.
    await _sync();
  }

  Future<void> _seekBy(Duration delta) async {
    if (!player.isSeekable) return;
    final current = player.position;
    if (current == null) return;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    final duration = player.duration;
    if (duration != null && target > duration) target = duration;
    await player.seek(target);
  }

  /// Stop syncing and release the OS session.
  ///
  /// Does NOT close [player] — the binding never owned it.
  Future<void> detach() async {
    if (_detached) return;
    _detached = true;
    _timer?.cancel();
    _timer = null;
    await _commandSub?.cancel();
    _commandSub = null;
    await session.dispose();
  }
}
