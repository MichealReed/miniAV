import 'package:meta/meta.dart';

/// Coarse transport state, as the OS understands it.
///
/// Deliberately the *intersection* of what the six platforms model, not the
/// union. Windows SMTC alone has `Closed`/`Changing`; Android has a dozen
/// states including `buffering` and `error`; the browser Media Session API has
/// exactly three (`none`/`playing`/`paused`). Modelling the union would mean
/// inventing a mapping for states that most backends must then collapse
/// anyway — and a state that silently collapses is a state the caller was
/// wrong to rely on. These four survive everywhere.
enum MediaPlaybackState {
  /// Nothing loaded. The OS card disappears.
  none,
  playing,
  paused,

  /// Loaded but reset to the start. Distinct from [paused] on Windows,
  /// Android and Linux; collapses to `paused` on web and Apple platforms.
  stopped,
}

/// A control the OS may offer for this session.
///
/// Declaring an action is a promise: the OS renders a button (or routes a
/// hardware key) and expects a corresponding [MediaCommand] to be handled. Do
/// not declare [next]/[previous] unless a playlist actually exists — a dead
/// button is worse than an absent one.
enum MediaAction {
  play,
  pause,

  /// Toggle. Hardware play/pause keys usually arrive as this rather than as
  /// [play] or [pause], because the keyboard has no idea which state you are
  /// in. Backends that receive a discrete play/pause synthesise this only when
  /// [playPause] was declared and the discrete action was not.
  playPause,
  stop,
  next,
  previous,

  /// Absolute scrub. Required for the draggable progress bar on macOS/iOS and
  /// in browser notifications.
  seekTo,

  /// Relative jump (the ±10s/±30s buttons). Carries an offset.
  seekForward,
  seekBackward,
}

/// The default action set: transport plus scrubbing, no playlist.
///
/// Excludes [MediaAction.next]/[MediaAction.previous] because the core session
/// has no concept of a queue — declaring them by default would light up
/// skip buttons that do nothing.
const Set<MediaAction> kDefaultMediaActions = {
  MediaAction.play,
  MediaAction.pause,
  MediaAction.playPause,
  MediaAction.stop,
  MediaAction.seekTo,
};

/// Where playback currently is, for the OS progress bar.
@immutable
class MediaPosition {
  final Duration position;

  /// Total length. Null for live/unbounded sources, which suppresses the
  /// progress bar rather than drawing a meaningless one.
  final Duration? duration;

  /// Playback rate. 1.0 is normal; 0.0 means stalled.
  ///
  /// Platforms use this to *extrapolate* the playhead between updates rather
  /// than redrawing on every tick — which is exactly why the session does not
  /// need to push position at frame rate. Reporting a wrong rate makes the
  /// bar visibly drift.
  final double speed;

  const MediaPosition({
    required this.position,
    this.duration,
    this.speed = 1.0,
  });

  static const MediaPosition zero = MediaPosition(position: Duration.zero);

  Map<String, Object?> toMap() => {
    'positionUs': position.inMicroseconds,
    'durationUs': duration?.inMicroseconds,
    'speed': speed,
  };

  @override
  bool operator ==(Object other) =>
      other is MediaPosition &&
      other.position == position &&
      other.duration == duration &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(position, duration, speed);

  @override
  String toString() => 'MediaPosition($position/${duration ?? '∞'} @${speed}x)';
}

/// A control request travelling *from* the OS *to* the app.
///
/// Arrives when the user presses a keyboard media key, clicks the Windows
/// flyout, uses the macOS Control Center tile, taps a lock-screen button, or
/// operates Bluetooth/headset controls.
@immutable
class MediaCommand {
  final MediaAction action;

  /// Target playhead for [MediaAction.seekTo]. Null otherwise.
  final Duration? position;

  /// Jump distance for [MediaAction.seekForward]/[MediaAction.seekBackward],
  /// always positive. Null otherwise.
  ///
  /// Platforms that do not supply one (most do not) leave this null and the
  /// handler should apply its own default — this is why it is nullable rather
  /// than defaulted to 10s here: a silent default in the wrong layer hides
  /// which platform actually asked for what.
  final Duration? offset;

  const MediaCommand(this.action, {this.position, this.offset});

  @override
  bool operator ==(Object other) =>
      other is MediaCommand &&
      other.action == action &&
      other.position == position &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(action, position, offset);

  @override
  String toString() =>
      'MediaCommand(${action.name}'
      '${position == null ? '' : ', position: $position'}'
      '${offset == null ? '' : ', offset: $offset'})';
}
