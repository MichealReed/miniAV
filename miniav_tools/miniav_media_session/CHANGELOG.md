## 0.1.0

- Initial release. `MiniavMediaSession` publishes now-playing metadata,
  playback state and position to the OS shell and delivers transport commands
  back as a `MediaCommand` stream.
- Windows backend implemented over System Media Transport Controls
  (C++/WinRT). Owns a hidden top-level host window and a message-pump thread;
  `create(hostWindowHandle:)` adopts an existing `HWND` instead.
- Web backend implemented over `navigator.mediaSession`, gated by
  `dart test -p chrome` — the one backend that never sees the Dart VM, so a
  `dart:js_interop` mistake in it is invisible to `dart analyze`.
- TRAP (web): browsers surface a session only while the page is actually
  playing audible media, started from a user gesture. Setting metadata on a
  silent page produces no notification and no media-key routing.
- TRAP (web): `setPositionState` throws when duration is absent, position
  exceeds it, or the rate is zero — all reachable from a normal poll. Guarded,
  not caught, so no TypeError reaches the app's zone.
- Linux backend implemented in pure Dart over MPRIS2 (D-Bus is a wire
  protocol, not an OS API), so it needs no `libdbus-1` and can be analysed and
  unit-tested on any host.
- Android is supplied by the companion package `miniav_media_session_flutter`
  via `MiniavMediaSession.backendOverride`; `MediaSession` needs a JVM
  `Context` a code asset cannot reach.
- macOS/iOS backend added in `native/src/apple/` (MPNowPlayingInfoCenter +
  MPRemoteCommandCenter). Written but never compiled — CI must gate it.
- macOS/iOS Now Playing, Linux MPRIS and Android MediaSession are scaffolded
  but not implemented; they report `isSupported == false` with a reason rather
  than accepting calls and publishing nothing.
- Windows adopts the host app's own visible top-level window when it has one,
  falling back to a hidden helper window only for windowless processes. The
  shell draws its card from the app identity behind that HWND, so a hidden
  window yields working media keys and NO card.
- `MediaArtwork.bytes` is supported on Windows — materialised to a temp file
  (SMTC takes a stream reference, not a buffer). This is the common path for
  mp3, where cover art arrives as an ID3 APIC frame.
- `MiniavMediaSession.backendDetail` reports which window was adopted or which
  fallback tier was taken, because "session registered but no card appeared" is
  otherwise invisible from the result code.
- TRAP (Windows): artwork temp files use a fresh name per track. SMTC keys the
  thumbnail off the URI, so rewriting one path leaves the FIRST cover on screen
  for the rest of the session.
- TRAP (Windows): SMTC will not publish for a message-only window
  (`HWND_MESSAGE`), and a session whose `IsEnabled`, button flags,
  `PlaybackStatus` and `DisplayUpdater.Update()` are not all set is silently
  invisible — which reads as "the API did not work".
- TRAP (Windows): the apartment probe runs on a throwaway thread. Initialising
  an apartment on the dart:ffi caller's thread would permanently change a
  thread the VM lends out — the bug class miniav_c already had to unpick.
- Native half ships as a code asset built by `hook/build.dart`; C ABI in
  `native/include/miniav_media_session.h`.
- `create` throws `StateError` on a second concurrent session — the OS allows
  one per app, so two would compete for the lock screen.
- TRAP: the native command callback passes scalars only. `NativeCallable.listener`
  marshals arguments asynchronously, so a pointer argument would dangle by the
  time the Dart handler runs.
