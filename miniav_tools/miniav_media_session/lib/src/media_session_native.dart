/// Native bindings to the `miniav_media_session_native` code asset, built by
/// `hook/build.dart` from `native/`.
///
/// The asset is bound to this library by the hook
/// (`names: {'miniav_media_session_native': 'media_session_native.dart'}`), so
/// the `@Native(symbol:)` externs below resolve to it at runtime.
@DefaultAsset('package:miniav_media_session/media_session_native.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Mirrors `MiniAVMediaSessionResult`.
abstract final class MsResult {
  static const ok = 0;
  static const unsupported = 1;
  static const invalidArg = 2;
  static const internal = 3;
}

/// Mirrors `MiniAVMediaSessionState`.
abstract final class MsState {
  static const none = 0;
  static const playing = 1;
  static const paused = 2;
  static const stopped = 3;
}

/// Mirrors the `MiniAVMediaSessionAction` bitmask.
abstract final class MsAction {
  static const play = 1 << 0;
  static const pause = 1 << 1;
  static const playPause = 1 << 2;
  static const stop = 1 << 3;
  static const next = 1 << 4;
  static const previous = 1 << 5;
  static const seekTo = 1 << 6;
  static const seekForward = 1 << 7;
  static const seekBackward = 1 << 8;
}

/// Mirrors `MiniAVMediaSessionMetadata`.
///
/// Field order and types must track the C struct exactly. Appending a field
/// preserves every existing OFFSET but changes `sizeOf`, and `sizeOf` is what
/// the allocation uses — so a Dart struct that has drifted short of the C one
/// hands native a buffer that is too small and the last field is written past
/// the end. miniAV shipped exactly that bug in `MiniAVInputConfig`.
final class NativeMediaMetadata extends Struct {
  external Pointer<Utf8> title;
  external Pointer<Utf8> artist;
  external Pointer<Utf8> album;
  @Int64()
  external int durationUs;
  @Int32()
  external int trackNumber;
  external Pointer<Utf8> artworkPath;
  external Pointer<Uint8> artworkBytes;
  @Size()
  external int artworkBytesLen;
  external Pointer<Utf8> artworkMime;
}

/// Mirrors `MiniAVMediaSessionPosition`.
final class NativeMediaPosition extends Struct {
  @Int64()
  external int positionUs;
  @Int64()
  external int durationUs;
  @Double()
  external double speed;
}

/// Opaque `MiniAVMediaSession*`.
final class NativeMediaSession extends Opaque {}

/// Scalar-only command callback — see the note in `miniav_media_session.h`.
typedef MsCommandCallbackNative =
    Void Function(Uint32 action, Int64 positionUs, Int64 offsetUs,
        Pointer<Void> userData);
typedef MsCommandCallbackDart =
    void Function(int action, int positionUs, int offsetUs,
        Pointer<Void> userData);

@Native<Int32 Function()>(symbol: 'MiniAV_MediaSession_IsSupported')
external int msIsSupported();

@Native<Void Function(Pointer<Void>)>(
  symbol: 'MiniAV_MediaSession_SetHostWindow',
)
external void msSetHostWindow(Pointer<Void> hwnd);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Uint32,
    Pointer<NativeFunction<MsCommandCallbackNative>>,
    Pointer<Void>,
    Pointer<Pointer<NativeMediaSession>>,
  )
>(symbol: 'MiniAV_MediaSession_Create')
external int msCreate(
  Pointer<Utf8> appName,
  int actions,
  Pointer<NativeFunction<MsCommandCallbackNative>> onCommand,
  Pointer<Void> userData,
  Pointer<Pointer<NativeMediaSession>> outSession,
);

@Native<Int32 Function(Pointer<NativeMediaSession>)>(
  symbol: 'MiniAV_MediaSession_Destroy',
)
external int msDestroy(Pointer<NativeMediaSession> session);

@Native<
  Int32 Function(Pointer<NativeMediaSession>, Pointer<NativeMediaMetadata>)
>(symbol: 'MiniAV_MediaSession_SetMetadata')
external int msSetMetadata(
  Pointer<NativeMediaSession> session,
  Pointer<NativeMediaMetadata> metadata,
);

@Native<Int32 Function(Pointer<NativeMediaSession>, Int32)>(
  symbol: 'MiniAV_MediaSession_SetPlaybackState',
)
external int msSetPlaybackState(
  Pointer<NativeMediaSession> session,
  int state,
);

@Native<
  Int32 Function(Pointer<NativeMediaSession>, Pointer<NativeMediaPosition>)
>(symbol: 'MiniAV_MediaSession_SetPosition')
external int msSetPosition(
  Pointer<NativeMediaSession> session,
  Pointer<NativeMediaPosition> position,
);

@Native<Int32 Function(Pointer<NativeMediaSession>, Uint32)>(
  symbol: 'MiniAV_MediaSession_SetActions',
)
external int msSetActions(Pointer<NativeMediaSession> session, int actions);

@Native<Size Function(Pointer<Utf8>, Size)>(
  symbol: 'MiniAV_MediaSession_LastError',
)
external int msLastError(Pointer<Utf8> buf, int bufLen);

@Native<Size Function(Pointer<Utf8>, Size)>(
  symbol: 'MiniAV_MediaSession_Describe',
)
external int msDescribe(Pointer<Utf8> buf, int bufLen);

String _readNativeString(int Function(Pointer<Utf8>, int) reader, int cap) {
  final buf = calloc<Uint8>(cap);
  try {
    reader(buf.cast<Utf8>(), cap);
    return buf.cast<Utf8>().toDartString();
  } finally {
    calloc.free(buf);
  }
}

/// Reads the thread-local reason string for the most recent failure.
String msLastErrorString() => _readNativeString(msLastError, 256);

/// Reads the backend's note about what it actually did.
String msDescribeString() => _readNativeString(msDescribe, 512);
