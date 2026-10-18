## 0.1.0

- Initial release. `MiniavMediaSession` publishes now-playing metadata, playback
  state and position to the OS and delivers transport commands back as a
  `MediaCommand` stream. The OS allows one session per app, so `create` throws
  `StateError` on a second concurrent session.
- Windows, over System Media Transport Controls: the session adopts the app's
  own visible top-level window, or `create(hostWindowHandle:)` names one. A
  windowless process gets a hidden helper window, which gives working media keys
  but no card in the shell. `MediaArtwork.bytes` is supported, the usual case
  for MP3 cover art.
- Web, over `navigator.mediaSession`: browsers show a session only while the
  page plays audible media started by a user gesture.
- Linux, over MPRIS2 in pure Dart: no `libdbus-1` needed.
- macOS/iOS, over `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`: written,
  not yet built or verified.
- Android comes from the companion package `miniav_media_session_flutter`,
  through `MiniavMediaSession.backendOverride`.
- A platform without a working backend reports `isSupported == false` with a
  reason instead of accepting calls and publishing nothing.
  `MiniavMediaSession.backendDetail` says which window or fallback was used, for
  when a session registers but no card appears.
- The native half ships as a code asset; its C ABI is
  `native/include/miniav_media_session.h`.
