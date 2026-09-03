import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'backend.dart';
import 'media_metadata.dart';
import 'media_playback.dart';
import 'media_session_native.dart';

/// Bitmask value for [action] in the C ABI.
int _bitOf(MediaAction action) => switch (action) {
  MediaAction.play => MsAction.play,
  MediaAction.pause => MsAction.pause,
  MediaAction.playPause => MsAction.playPause,
  MediaAction.stop => MsAction.stop,
  MediaAction.next => MsAction.next,
  MediaAction.previous => MsAction.previous,
  MediaAction.seekTo => MsAction.seekTo,
  MediaAction.seekForward => MsAction.seekForward,
  MediaAction.seekBackward => MsAction.seekBackward,
};

int _maskOf(Set<MediaAction> actions) =>
    actions.fold(0, (mask, a) => mask | _bitOf(a));

MediaAction? _actionOfBit(int bit) {
  for (final a in MediaAction.values) {
    if (_bitOf(a) == bit) return a;
  }
  return null;
}

int _stateOf(MediaPlaybackState state) => switch (state) {
  MediaPlaybackState.none => MsState.none,
  MediaPlaybackState.playing => MsState.playing,
  MediaPlaybackState.paused => MsState.paused,
  MediaPlaybackState.stopped => MsState.stopped,
};

/// Native backend: Windows SMTC, macOS/iOS Now Playing, Linux MPRIS, Android
/// MediaSession — whichever one `native/` was built with for this platform.
class FfiMediaSessionBackend implements MediaSessionBackend {
  final String appName;

  /// Windows only: an existing top-level window to host the SMTC session.
  final int? hostWindowHandle;

  Pointer<NativeMediaSession> _session = nullptr;
  NativeCallable<MsCommandCallbackNative>? _callback;
  bool _supported = false;
  String? _unsupportedReason;

  final _commands = StreamController<MediaCommand>.broadcast();

  FfiMediaSessionBackend({required this.appName, this.hostWindowHandle});

  @override
  String get name => 'native';

  @override
  bool get isSupported => _supported;

  @override
  String? get unsupportedReason => _unsupportedReason;

  @override
  String? get detail {
    if (_session == nullptr) return null;
    final text = msDescribeString();
    return text.isEmpty ? null : text;
  }

  @override
  Stream<MediaCommand> get commands => _commands.stream;

  @override
  Future<void> initialize({required Set<MediaAction> actions}) async {
    if (hostWindowHandle != null) {
      msSetHostWindow(Pointer<Void>.fromAddress(hostWindowHandle!));
    }

    // A listener (not isolateLocal) callback: the OS fires commands on its own
    // thread — the SMTC apartment, a run loop, the D-Bus thread — and only
    // NativeCallable.listener can hop that onto the Dart isolate. The C side
    // passes scalars precisely so there is nothing whose lifetime has to
    // survive that hop.
    final callback = NativeCallable<MsCommandCallbackNative>.listener(
      _onNativeCommand,
    );
    _callback = callback;

    final arena = Arena();
    try {
      final outSession = arena<Pointer<NativeMediaSession>>();
      final result = msCreate(
        appName.toNativeUtf8(allocator: arena),
        _maskOf(actions),
        callback.nativeFunction,
        nullptr,
        outSession,
      );
      if (result != MsResult.ok) {
        _supported = false;
        _unsupportedReason = msLastErrorString();
        // Close immediately: an open listener holds the isolate alive, and an
        // unsupported platform would otherwise keep it alive forever for a
        // callback that can never fire.
        callback.close();
        _callback = null;
        return;
      }
      _session = outSession.value;
      _supported = true;
      _unsupportedReason = null;
    } finally {
      arena.releaseAll();
    }
  }

  void _onNativeCommand(
    int actionBit,
    int positionUs,
    int offsetUs,
    Pointer<Void> _,
  ) {
    final action = _actionOfBit(actionBit);
    // An unknown bit means the native half declared a control this Dart
    // version does not model. Drop it rather than pushing a null action into
    // every consumer's switch.
    if (action == null) return;
    if (_commands.isClosed) return;
    _commands.add(
      MediaCommand(
        action,
        position: positionUs < 0
            ? null
            : Duration(microseconds: positionUs),
        offset: offsetUs < 0 ? null : Duration(microseconds: offsetUs),
      ),
    );
  }

  @override
  Future<void> setMetadata(MediaMetadata metadata) async {
    if (_session == nullptr) return;
    final arena = Arena();
    try {
      final native = arena<NativeMediaMetadata>();
      final m = native.ref;
      m.title = metadata.title.toNativeUtf8(allocator: arena);
      m.artist = metadata.artist?.toNativeUtf8(allocator: arena) ?? nullptr;
      m.album = metadata.album?.toNativeUtf8(allocator: arena) ?? nullptr;
      m.durationUs = metadata.duration?.inMicroseconds ?? -1;
      m.trackNumber = metadata.trackNumber ?? 0;
      m.artworkPath = nullptr;
      m.artworkBytes = nullptr;
      m.artworkBytesLen = 0;
      m.artworkMime = nullptr;

      switch (metadata.artwork) {
        case FileArtwork(:final path):
          m.artworkPath = path.toNativeUtf8(allocator: arena);
        case UriArtwork(:final uri):
          m.artworkPath = uri.toString().toNativeUtf8(allocator: arena);
        case BytesArtwork(:final bytes, :final mimeType):
          final buf = arena<Uint8>(bytes.length);
          buf.asTypedList(bytes.length).setAll(0, bytes);
          m.artworkBytes = buf;
          m.artworkBytesLen = bytes.length;
          m.artworkMime = mimeType.toNativeUtf8(allocator: arena);
        case null:
          break;
      }

      msSetMetadata(_session, native);
    } finally {
      // Safe to free here: the C contract says every string and buffer is
      // COPIED before the setter returns.
      arena.releaseAll();
    }
  }

  @override
  Future<void> setPlaybackState(MediaPlaybackState state) async {
    if (_session == nullptr) return;
    msSetPlaybackState(_session, _stateOf(state));
  }

  @override
  Future<void> setPosition(MediaPosition position) async {
    if (_session == nullptr) return;
    final arena = Arena();
    try {
      final native = arena<NativeMediaPosition>();
      native.ref
        ..positionUs = position.position.inMicroseconds
        ..durationUs = position.duration?.inMicroseconds ?? -1
        ..speed = position.speed;
      msSetPosition(_session, native);
    } finally {
      arena.releaseAll();
    }
  }

  @override
  Future<void> setActions(Set<MediaAction> actions) async {
    if (_session == nullptr) return;
    msSetActions(_session, _maskOf(actions));
  }

  @override
  Future<void> dispose() async {
    if (_session != nullptr) {
      // Destroy blocks until the backend guarantees no further callback, which
      // is what makes closing the NativeCallable on the next line safe. Closing
      // it first would risk the OS invoking a closed callable.
      msDestroy(_session);
      _session = nullptr;
    }
    _callback?.close();
    _callback = null;
    await _commands.close();
  }
}

/// Whether the native library reports an OS session on this machine.
bool ffiMediaSessionSupported() => msIsSupported() != 0;

/// Reason the native library gave for the last failure, if any.
String ffiMediaSessionLastError() => msLastErrorString();
