import 'dart:async';

import 'backend.dart';
import 'backend_factory.dart';
import 'media_metadata.dart';
import 'media_playback.dart';

/// The app's OS media session: what the system shell shows, and where hardware
/// media keys are delivered.
///
/// ```dart
/// final session = await MiniavMediaSession.create(appName: 'Tunes');
/// session.commands.listen((c) => switch (c.action) {
///   MediaAction.playPause => player.isPaused ? player.resume() : player.pause(),
///   MediaAction.seekTo => player.seek(c.position!),
///   _ => null,
/// });
/// await session.setMetadata(MediaMetadata(title: 'Song', artist: 'Band'));
/// await session.setPlaybackState(MediaPlaybackState.playing);
/// ```
///
/// Most apps should not drive this by hand — `miniav_media_session_player`
/// binds it to a `MiniavPlayer` in one line.
class MiniavMediaSession {
  final MediaSessionBackend _backend;

  MediaMetadata? _lastMetadata;
  MediaPlaybackState? _lastState;
  MediaPosition? _lastPosition;
  Set<MediaAction> _actions;
  bool _disposed = false;

  /// There is exactly ONE media session per app on every platform, so a second
  /// live instance could only fight the first. Tracked to turn that into an
  /// error at the call site instead of a mystery about which player owns the
  /// lock screen.
  static MiniavMediaSession? _current;

  /// Supplies a backend in place of the built-in one for this platform.
  ///
  /// Exists for Android, whose `MediaSession`, foreground service and
  /// notification live on the JVM and cannot be reached from a code asset. The
  /// companion package `miniav_media_session_flutter` sets this; the core
  /// cannot depend on it without inverting the dependency graph and dragging
  /// the Flutter SDK into a package that is deliberately plain Dart.
  ///
  /// Set it before calling [create]. Null restores the built-in selection.
  static MediaSessionBackend Function({
    required String appName,
    int? hostWindowHandle,
  })?
  backendOverride;

  MiniavMediaSession._(this._backend, this._actions);

  /// The live session, if one exists.
  static MiniavMediaSession? get current => _current;

  /// Claim the OS media session.
  ///
  /// [appName] identifies the app to the shell (the MPRIS bus name on Linux,
  /// the source label on Windows).
  ///
  /// [hostWindowHandle] is Windows-only and optional: an existing top-level
  /// `HWND` for SMTC to attach to. When omitted the native backend creates its
  /// own hidden window. Ignored on every other platform.
  ///
  /// Never throws for an unsupported platform — a missing shell integration is
  /// not a reason to fail playback. Check [isSupported] and
  /// [unsupportedReason] to find out whether the card will actually appear.
  ///
  /// Throws [StateError] if a session is already live; call [dispose] first.
  static Future<MiniavMediaSession> create({
    required String appName,
    Set<MediaAction> actions = kDefaultMediaActions,
    int? hostWindowHandle,
  }) async {
    if (_current != null && !_current!._disposed) {
      throw StateError(
        'A MiniavMediaSession is already live. The OS allows exactly one '
        'session per app, so a second one would compete with the first for '
        'the lock screen and media keys. Dispose the existing session '
        '(MiniavMediaSession.current) before creating another, or keep one '
        'session and re-point it at the item that should own the transport.',
      );
    }

    final build = backendOverride ?? createMediaSessionBackend;
    final backend = build(
      appName: appName,
      hostWindowHandle: hostWindowHandle,
    );
    await backend.initialize(actions: actions);
    final session = MiniavMediaSession._(backend, actions);
    _current = session;
    return session;
  }

  /// Whether the OS actually accepted a session. False is a normal outcome on
  /// an old Windows build, a Linux box without a session bus, or a browser
  /// without the Media Session API.
  bool get isSupported => _backend.isSupported;

  /// Why [isSupported] is false. Null when supported.
  String? get unsupportedReason => _backend.unsupportedReason;

  /// Which backend answered (`native`, `web`, `none`) — for logs and tests.
  String get backendName => _backend.name;

  /// What the backend actually did — which window it adopted, which fallback
  /// tier it landed on. Null when there is nothing to report.
  ///
  /// Worth logging when a session reports [isSupported] but no card appears:
  /// on Windows the shell draws from the app identity behind the host window,
  /// so a process without a visible top-level window gets working media keys
  /// and no card. Diagnostic only — do not parse it.
  String? get backendDetail => _backend.detail;

  /// Controls the user requested through the OS.
  Stream<MediaCommand> get commands => _backend.commands;

  /// Actions currently advertised to the OS.
  Set<MediaAction> get actions => Set.unmodifiable(_actions);

  /// Describe the current item. Redundant pushes are dropped.
  Future<void> setMetadata(MediaMetadata metadata) async {
    if (_disposed || metadata == _lastMetadata) return;
    _lastMetadata = metadata;
    await _backend.setMetadata(metadata);
  }

  /// Report play/pause/stop. Redundant pushes are dropped.
  Future<void> setPlaybackState(MediaPlaybackState state) async {
    if (_disposed || state == _lastState) return;
    _lastState = state;
    await _backend.setPlaybackState(state);
  }

  /// Report the playhead.
  ///
  /// Does NOT need calling at frame rate: platforms extrapolate from
  /// [MediaPosition.speed] between updates. A few times a second, plus once
  /// after every seek, is enough — and pushing more often makes some shells
  /// stutter the progress bar rather than smooth it.
  Future<void> setPosition(MediaPosition position) async {
    if (_disposed || position == _lastPosition) return;
    _lastPosition = position;
    await _backend.setPosition(position);
  }

  /// Change which controls the OS offers.
  Future<void> setActions(Set<MediaAction> actions) async {
    if (_disposed || _setEquals(actions, _actions)) return;
    _actions = actions;
    await _backend.setActions(actions);
  }

  /// Release the session. The shell card disappears and media keys stop
  /// routing here.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (identical(_current, this)) _current = null;
    await _backend.dispose();
  }

  static bool _setEquals(Set<MediaAction> a, Set<MediaAction> b) =>
      a.length == b.length && a.containsAll(b);
}
