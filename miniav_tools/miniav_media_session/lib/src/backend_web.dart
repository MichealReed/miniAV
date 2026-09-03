import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'backend.dart';
import 'media_metadata.dart';
import 'media_playback.dart';

/// Browser backend over `navigator.mediaSession`.
///
/// Drives the media notification on Android/Chrome OS, the macOS Now Playing
/// tile for Safari/Chrome, the Windows flyout for Edge/Chrome, and hardware
/// media keys in every browser that implements the API.
class WebMediaSessionBackend implements MediaSessionBackend {
  final _commands = StreamController<MediaCommand>.broadcast();

  bool _supported = false;
  String? _unsupportedReason;
  Set<MediaAction> _actions = const {};

  /// Blob URL minted for [BytesArtwork], kept so it can be revoked when the
  /// next track replaces it. Without this every track change would leak a blob
  /// for the lifetime of the document.
  String? _artworkObjectUrl;

  @override
  String get name => 'web';

  @override
  bool get isSupported => _supported;

  @override
  String? get unsupportedReason => _unsupportedReason;

  @override
  String? get detail =>
      _supported ? 'navigator.mediaSession (this document)' : null;

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  web.MediaSession get _session => web.window.navigator.mediaSession;

  @override
  Future<void> initialize({required Set<MediaAction> actions}) async {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('mediaSession')) {
      _supported = false;
      _unsupportedReason =
          'navigator.mediaSession is not implemented by this browser';
      return;
    }
    _supported = true;
    _unsupportedReason = null;
    await setActions(actions);
  }

  @override
  Future<void> setActions(Set<MediaAction> actions) async {
    if (!_supported) return;
    // Clear the previous set first: handlers persist on the singleton session,
    // so an action dropped between calls would otherwise keep firing.
    for (final action in _actions) {
      for (final name in _webNamesFor(action, _actions)) {
        _setHandler(name, null);
      }
    }
    _actions = actions;
    for (final action in actions) {
      for (final name in _webNamesFor(action, actions)) {
        _setHandler(name, action);
      }
    }
  }

  /// Web action names that should drive [action].
  ///
  /// The web API has no `playpause`: a hardware play/pause key arrives as a
  /// discrete `play` or `pause` because the browser knows the current state.
  /// So [MediaAction.playPause] is served by subscribing to both — but only
  /// when the app did not also declare the discrete actions, otherwise the same
  /// key press would emit two commands.
  List<String> _webNamesFor(MediaAction action, Set<MediaAction> declared) {
    switch (action) {
      case MediaAction.play:
        return const ['play'];
      case MediaAction.pause:
        return const ['pause'];
      case MediaAction.playPause:
        final hasDiscrete =
            declared.contains(MediaAction.play) ||
            declared.contains(MediaAction.pause);
        return hasDiscrete ? const [] : const ['play', 'pause'];
      case MediaAction.stop:
        return const ['stop'];
      case MediaAction.next:
        return const ['nexttrack'];
      case MediaAction.previous:
        return const ['previoustrack'];
      case MediaAction.seekTo:
        return const ['seekto'];
      case MediaAction.seekForward:
        return const ['seekforward'];
      case MediaAction.seekBackward:
        return const ['seekbackward'];
    }
  }

  void _setHandler(String webName, MediaAction? action) {
    void handler(JSObject details) {
      if (action == null || _commands.isClosed) return;
      final seekTime = details.getProperty<JSNumber?>('seekTime'.toJS);
      final seekOffset = details.getProperty<JSNumber?>('seekOffset'.toJS);
      _commands.add(
        MediaCommand(
          action,
          position: seekTime == null
              ? null
              : Duration(
                  microseconds: (seekTime.toDartDouble * 1e6).round(),
                ),
          offset: seekOffset == null
              ? null
              : Duration(
                  microseconds: (seekOffset.toDartDouble * 1e6).round(),
                ),
        ),
      );
    }

    try {
      _session.setActionHandler(
        webName,
        action == null ? null : handler.toJS,
      );
    } catch (_) {
      // Browsers throw (NotSupportedError / TypeError) for actions they do not
      // implement — Safari has historically rejected `seekto`. One unsupported
      // action must not abort the rest of the set.
    }
  }

  @override
  Future<void> setMetadata(MediaMetadata metadata) async {
    if (!_supported) return;

    final artwork = <web.MediaImage>[];
    final art = metadata.artwork;
    _revokeArtworkUrl();
    switch (art) {
      case UriArtwork(:final uri):
        artwork.add(web.MediaImage(src: uri.toString()));
      case BytesArtwork(:final bytes, :final mimeType):
        final blob = web.Blob(
          [bytes.toJS].toJS,
          web.BlobPropertyBag(type: mimeType),
        );
        final url = web.URL.createObjectURL(blob);
        _artworkObjectUrl = url;
        artwork.add(web.MediaImage(src: url, type: mimeType));
      case FileArtwork():
        // A browser cannot read an arbitrary local path. Silently dropping it
        // would leave the card art-less with no explanation, so the docs on
        // MediaArtwork.file call this out; there is nothing to do at runtime.
        break;
      case null:
        break;
    }

    _session.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: metadata.title,
        artist: metadata.artist ?? '',
        album: metadata.album ?? '',
        artwork: artwork.toJS,
      ),
    );
  }

  void _revokeArtworkUrl() {
    final url = _artworkObjectUrl;
    if (url == null) return;
    web.URL.revokeObjectURL(url);
    _artworkObjectUrl = null;
  }

  @override
  Future<void> setPlaybackState(MediaPlaybackState state) async {
    if (!_supported) return;
    // The web API models three states. `stopped` collapses to `paused` rather
    // than `none`: `none` tears the notification down entirely, which is wrong
    // for a track that is merely rewound and still loaded.
    _session.playbackState = switch (state) {
      MediaPlaybackState.none => 'none',
      MediaPlaybackState.playing => 'playing',
      MediaPlaybackState.paused => 'paused',
      MediaPlaybackState.stopped => 'paused',
    };
  }

  @override
  Future<void> setPosition(MediaPosition position) async {
    if (!_supported) return;
    final duration = position.duration;
    // setPositionState THROWS a TypeError when duration is absent or when
    // position exceeds it — which is reachable in normal use, because a poll
    // can observe a position from the outgoing track against the duration of
    // the incoming one. Guard rather than catch: a thrown TypeError here would
    // surface as an unhandled error in the app's zone.
    if (duration == null || duration <= Duration.zero) return;
    if (position.position > duration) return;
    if (position.position < Duration.zero) return;
    if (position.speed <= 0) return;

    _session.setPositionState(
      web.MediaPositionState(
        duration: duration.inMicroseconds / 1e6,
        position: position.position.inMicroseconds / 1e6,
        playbackRate: position.speed,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_supported) {
      await setActions(const {});
      _session.metadata = null;
      _session.playbackState = 'none';
    }
    _revokeArtworkUrl();
    await _commands.close();
  }
}
