/// Android companion for `miniav_media_session`.
///
/// Call [registerMiniavMediaSessionAndroid] once before creating a session:
///
/// ```dart
/// registerMiniavMediaSessionAndroid();
/// final session = await MiniavMediaSession.create(appName: 'Tunes');
/// ```
///
/// `miniav_media_session_player` does this for you.
///
/// Registration is explicit rather than automatic because the core package is
/// plain Dart and cannot depend on this one — that would invert the dependency
/// graph and pull the Flutter SDK into a package that is deliberately usable
/// from `dart test` and from non-Flutter apps.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:miniav_media_session/miniav_media_session.dart';

const _channel = MethodChannel('com.practicalxr.miniav_media_session');

/// Routes Android through this package's `MediaSession`-backed implementation.
///
/// A no-op on every other platform: the built-in backends there are already
/// the right ones, and overriding them would replace a working SMTC or MPRIS
/// session with a channel that has no native half.
///
/// [showNotification] controls the foreground service that carries the media
/// panel in the notification shade. On by default. Turning it off keeps media
/// buttons and lock-screen controls but drops the shade panel — worth doing if
/// you would rather not ship the `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
/// declaration this package's manifest contributes.
///
/// [notificationChannelName] is what the user sees in Android's per-app
/// notification settings. It is not a title; the notification's title is the
/// track.
///
/// Safe to call more than once.
void registerMiniavMediaSessionAndroid({
  bool showNotification = true,
  String notificationChannelName = 'Playback',
}) {
  if (!Platform.isAndroid) return;
  MiniavMediaSession.backendOverride =
      ({required String appName, int? hostWindowHandle}) =>
          AndroidMediaSessionBackend(
            showNotification: showNotification,
            notificationChannelName: notificationChannelName,
          );
}

/// Backend over the platform channel to `android.media.session.MediaSession`.
class AndroidMediaSessionBackend implements MediaSessionBackend {
  /// Run the foreground service that carries the notification-shade panel.
  final bool showNotification;

  /// Channel name shown in Android's per-app notification settings.
  final String notificationChannelName;

  AndroidMediaSessionBackend({
    this.showNotification = true,
    this.notificationChannelName = 'Playback',
  });

  bool _supported = false;
  String? _unsupportedReason;
  String? _detail;

  final _commands = StreamController<MediaCommand>.broadcast();

  @override
  String get name => 'androidsession';

  @override
  bool get isSupported => _supported;

  @override
  String? get unsupportedReason => _unsupportedReason;

  @override
  String? get detail => _detail;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<void> initialize({required Set<MediaAction> actions}) async {
    _channel.setMethodCallHandler(_handlePlatformCall);
    try {
      final reason = await _channel.invokeMethod<String?>('initialize', {
        'actions': actions.map((a) => a.name).toList(),
        'showNotification': showNotification,
        'notificationChannelName': notificationChannelName,
      });
      // The platform returns null when it claimed a session, or a string
      // saying why not. It does NOT throw for that case: "MediaSession is
      // unavailable here" is an expected outcome, not a failure to catch.
      _supported = reason == null;
      _unsupportedReason = reason;
      if (_supported) {
        _detail = await _channel.invokeMethod<String>('describe');
      }
    } on MissingPluginException {
      _supported = false;
      _unsupportedReason =
          'miniav_media_session_flutter is not registered in this build';
    } on PlatformException catch (e) {
      _supported = false;
      _unsupportedReason = e.message ?? e.code;
    }
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'onCommand') return null;
    final args = (call.arguments as Map).cast<String, Object?>();
    final actionName = args['action'] as String?;
    MediaAction? action;
    for (final candidate in MediaAction.values) {
      if (candidate.name == actionName) {
        action = candidate;
        break;
      }
    }
    // An unknown action means the JVM half declared a control this Dart
    // version does not model. Drop it rather than pushing a null through.
    if (action == null || _commands.isClosed) return null;

    final positionUs = (args['positionUs'] as num?)?.toInt() ?? -1;
    final offsetUs = (args['offsetUs'] as num?)?.toInt() ?? -1;
    _commands.add(
      MediaCommand(
        action,
        position: positionUs < 0 ? null : Duration(microseconds: positionUs),
        offset: offsetUs < 0 ? null : Duration(microseconds: offsetUs),
      ),
    );
    return null;
  }

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      // A single rejected update must not tear the session down; the card just
      // goes stale until the next push.
      _unsupportedReason = e.message ?? e.code;
    }
  }

  @override
  Future<void> setMetadata(MediaMetadata metadata) {
    final artwork = metadata.artwork;
    return _invoke('setMetadata', {
      'title': metadata.title,
      'artist': metadata.artist,
      'album': metadata.album,
      'durationUs': metadata.duration?.inMicroseconds ?? -1,
      'trackNumber': metadata.trackNumber ?? 0,
      'artworkPath': switch (artwork) {
        FileArtwork(:final path) => path,
        UriArtwork(:final uri) => uri.toString(),
        _ => null,
      },
      // Passed as the original Uint8List so the standard codec sends it as a
      // typed byte buffer rather than boxing every element — cover art is
      // routinely a megabyte or more.
      'artworkBytes': switch (artwork) {
        BytesArtwork(:final bytes) => bytes,
        _ => null,
      },
    });
  }

  @override
  Future<void> setPlaybackState(MediaPlaybackState state) =>
      _invoke('setPlaybackState', {'state': state.name});

  @override
  Future<void> setPosition(MediaPosition position) => _invoke('setPosition', {
    'positionUs': position.position.inMicroseconds,
    'durationUs': position.duration?.inMicroseconds ?? -1,
    'speed': position.speed,
  });

  @override
  Future<void> setActions(Set<MediaAction> actions) =>
      _invoke('setActions', {'actions': actions.map((a) => a.name).toList()});

  @override
  Future<void> dispose() async {
    await _invoke('dispose');
    _supported = false;
    _channel.setMethodCallHandler(null);
    await _commands.close();
  }
}
