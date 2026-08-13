/// OS media-session integration for miniav_tools.
///
/// Publishes what is playing to the system shell and receives transport
/// commands back from it — hardware media keys, the Windows volume flyout, the
/// macOS Control Center tile, lock-screen widgets, and Bluetooth headsets.
///
/// The two halves are one feature, not two. On every platform the OS routes
/// media keys to whichever app owns the registered session, so publishing is
/// the prerequisite for the keys working at all — there is no way to "just
/// read the media key". (A global keyboard hook can see them on Windows, but
/// only by stealing them from every other media app on the machine.)
///
/// See `docs/MEDIA_SESSION_PLAN.md` for per-platform backend status.
library;

export 'src/backend.dart' show MediaSessionBackend;
export 'src/media_metadata.dart';
export 'src/media_playback.dart';
export 'src/media_session.dart';
