import 'dart:async';

import 'media_metadata.dart';
import 'media_playback.dart';

/// One platform's implementation of the OS media session.
///
/// Backends are push-only for state and stream-only for commands: the session
/// tells the OS what is happening, the OS asks the session to change it. There
/// is deliberately no "read current state from the OS" call — the app is the
/// source of truth, and a backend that could disagree with it would create a
/// second one.
abstract class MediaSessionBackend {
  /// Short identifier for logs and tests (`smtc`, `mpris`, `web`, …).
  String get name;

  /// Whether this backend can actually publish a session on this machine.
  ///
  /// False is a normal, expected outcome — an old Windows build, a Linux box
  /// with no D-Bus session, a browser without the Media Session API. Callers
  /// must treat it as "the flyout will not appear", never as an error.
  bool get isSupported;

  /// Human-readable reason [isSupported] is false, for logs and diagnostics.
  /// Null when supported.
  String? get unsupportedReason;

  /// What the backend actually did, when it succeeded — which window it
  /// adopted, which fallback tier it landed on.
  ///
  /// Exists because a session can register successfully and still show no card:
  /// on Windows the shell draws from the app identity behind the host window,
  /// so a process with no visible window gets working media keys and no card at
  /// all. That is invisible from [isSupported] alone. Diagnostic only — the
  /// text is not stable and must not be parsed.
  String? get detail;

  /// Claim the OS session and declare which controls it offers.
  Future<void> initialize({required Set<MediaAction> actions});

  Future<void> setMetadata(MediaMetadata metadata);

  Future<void> setPlaybackState(MediaPlaybackState state);

  Future<void> setPosition(MediaPosition position);

  Future<void> setActions(Set<MediaAction> actions);

  /// Controls requested by the user through the OS.
  Stream<MediaCommand> get commands;

  /// Release the OS session. The card disappears and media keys stop routing
  /// here.
  Future<void> dispose();
}

/// The backend used where no OS integration exists.
///
/// Accepts every call and does nothing, so an app can drive a session
/// unconditionally without platform checks — but reports [isSupported] as
/// false and says why, so "the OS card never appeared" is a question with an
/// answer rather than a mystery.
class UnsupportedMediaSessionBackend implements MediaSessionBackend {
  @override
  final String name;

  @override
  final String? unsupportedReason;

  final _commands = StreamController<MediaCommand>.broadcast();

  UnsupportedMediaSessionBackend(this.unsupportedReason, {this.name = 'none'});

  @override
  bool get isSupported => false;

  @override
  String? get detail => null;

  @override
  Future<void> initialize({required Set<MediaAction> actions}) async {}

  @override
  Future<void> setMetadata(MediaMetadata metadata) async {}

  @override
  Future<void> setPlaybackState(MediaPlaybackState state) async {}

  @override
  Future<void> setPosition(MediaPosition position) async {}

  @override
  Future<void> setActions(Set<MediaAction> actions) async {}

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<void> dispose() async {
    await _commands.close();
  }
}
