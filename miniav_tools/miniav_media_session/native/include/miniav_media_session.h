/*
 * miniav_media_session — OS media-session integration.
 *
 * Publishes "now playing" to the system shell and receives transport commands
 * back from it (hardware media keys, lock screen, Control Center, Bluetooth
 * headsets, the Windows volume flyout).
 *
 * One backend per platform, selected at compile time:
 *   windows/  System Media Transport Controls  (C++/WinRT)
 *   apple/    MPNowPlayingInfoCenter + MPRemoteCommandCenter  (ObjC++, macOS+iOS)
 *   linux/    MPRIS2 over D-Bus
 *   android/  android.media.session.MediaSession via JNI
 *
 * Web has no native half at all — browsers expose navigator.mediaSession, so
 * that backend lives in Dart (lib/src/backend_web.dart).
 *
 * THREADING
 * ---------
 * Every setter may be called from any thread and returns promptly; backends
 * marshal to whatever thread their OS API demands (the SMTC apartment, the
 * main run loop, the D-Bus connection thread). The command callback fires on
 * an OS-owned thread — see the note on MiniAVMediaSessionCommandCallback.
 */
#ifndef MINIAV_MEDIA_SESSION_H
#define MINIAV_MEDIA_SESSION_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define MINIAV_MS_API __declspec(dllexport)
#else
#define MINIAV_MS_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MiniAVMediaSession MiniAVMediaSession;

typedef enum {
  MINIAV_MS_OK = 0,
  /* No OS session available here: Windows build too old, no D-Bus session bus,
   * headless macOS, MediaSession not reachable. An EXPECTED outcome, not a
   * failure — the caller keeps playing audio, the shell just shows no card. */
  MINIAV_MS_ERROR_UNSUPPORTED = 1,
  MINIAV_MS_ERROR_INVALID_ARG = 2,
  MINIAV_MS_ERROR_INTERNAL = 3,
} MiniAVMediaSessionResult;

typedef enum {
  MINIAV_MS_STATE_NONE = 0,
  MINIAV_MS_STATE_PLAYING = 1,
  MINIAV_MS_STATE_PAUSED = 2,
  MINIAV_MS_STATE_STOPPED = 3,
} MiniAVMediaSessionState;

/* Actions are a SET, so they cross the boundary as a bitmask — no array
 * allocation, no length parameter, no ownership question. */
typedef enum {
  MINIAV_MS_ACTION_PLAY = 1u << 0,
  MINIAV_MS_ACTION_PAUSE = 1u << 1,
  MINIAV_MS_ACTION_PLAY_PAUSE = 1u << 2,
  MINIAV_MS_ACTION_STOP = 1u << 3,
  MINIAV_MS_ACTION_NEXT = 1u << 4,
  MINIAV_MS_ACTION_PREVIOUS = 1u << 5,
  MINIAV_MS_ACTION_SEEK_TO = 1u << 6,
  MINIAV_MS_ACTION_SEEK_FORWARD = 1u << 7,
  MINIAV_MS_ACTION_SEEK_BACKWARD = 1u << 8,
} MiniAVMediaSessionAction;

/* All strings are UTF-8 and are COPIED by the callee before it returns, so the
 * caller may free them immediately. (Dart allocates these in a temporary arena
 * per call; borrowing them would outlive the arena.) */
typedef struct {
  const char *title;  /* required; NULL or "" renders a blank card */
  const char *artist; /* nullable */
  const char *album;  /* nullable */
  int64_t duration_us;  /* < 0 when unknown */
  int32_t track_number; /* <= 0 when unknown */

  /* Artwork. At most one of path / bytes is used; path wins when both are set.
   * Backends that need a different form materialise it themselves (Windows and
   * Linux write a temp file for byte art; Apple and Android decode an image). */
  const char *artwork_path; /* local path or URI, nullable */
  const uint8_t *artwork_bytes;
  size_t artwork_bytes_len;
  const char *artwork_mime; /* e.g. "image/jpeg"; required with artwork_bytes */
} MiniAVMediaSessionMetadata;

typedef struct {
  int64_t position_us;
  int64_t duration_us; /* < 0 when unknown (live/unbounded) */
  /* Playback rate. Platforms EXTRAPOLATE the playhead from this between
   * updates instead of redrawing per tick, which is why position does not need
   * pushing at frame rate — and why a wrong rate makes the bar visibly drift. */
  double speed;
} MiniAVMediaSessionPosition;

/*
 * Fired when the user operates the OS transport.
 *
 * Arguments are SCALARS ONLY, deliberately. A Dart `NativeCallable.listener`
 * marshals its arguments asynchronously — the C stack frame is long gone by
 * the time the Dart handler runs — so any pointer passed here would dangle.
 * miniav_c already learned this the hard way with its log callback and had to
 * adopt a malloc-in-C / free-in-Dart handoff. Scalars need no handoff at all,
 * so this callback simply cannot have that bug.
 *
 * `position_us` is the target for MINIAV_MS_ACTION_SEEK_TO, `offset_us` the
 * jump distance for SEEK_FORWARD/SEEK_BACKWARD; both are < 0 when the platform
 * supplied no value.
 *
 * Called on an OS-owned thread. Do NOT call back into this API from inside it.
 */
typedef void (*MiniAVMediaSessionCommandCallback)(uint32_t action,
                                                  int64_t position_us,
                                                  int64_t offset_us,
                                                  void *user_data);

/*
 * Windows only; ignored elsewhere. Adopt an existing top-level window as the
 * SMTC host instead of letting the backend create its own hidden one.
 *
 * SMTC is obtained through ISystemMediaTransportControlsInterop::GetForWindow,
 * so a window is mandatory. When the host app already has one (any Flutter
 * desktop app does), handing it over avoids a second top-level window and its
 * message pump. Must be called BEFORE MiniAV_MediaSession_Create.
 *
 * TRAP: the window must be a real top-level window. A message-only window
 * (HWND_MESSAGE) is not associated with a display surface and SMTC will not
 * publish for it.
 */
MINIAV_MS_API void MiniAV_MediaSession_SetHostWindow(void *hwnd);

/*
 * Create the session and claim the OS transport.
 *
 * `app_name` is UTF-8 and identifies the app to the shell: the MPRIS bus name
 * component on Linux, the source label on Windows. Required.
 *
 * Returns MINIAV_MS_ERROR_UNSUPPORTED (with *out_session left NULL) when this
 * machine has no session to claim; call MiniAV_MediaSession_LastError for the
 * reason.
 */
MINIAV_MS_API MiniAVMediaSessionResult MiniAV_MediaSession_Create(
    const char *app_name, uint32_t actions,
    MiniAVMediaSessionCommandCallback on_command, void *user_data,
    MiniAVMediaSession **out_session);

MINIAV_MS_API MiniAVMediaSessionResult MiniAV_MediaSession_SetMetadata(
    MiniAVMediaSession *session, const MiniAVMediaSessionMetadata *metadata);

MINIAV_MS_API MiniAVMediaSessionResult MiniAV_MediaSession_SetPlaybackState(
    MiniAVMediaSession *session, MiniAVMediaSessionState state);

MINIAV_MS_API MiniAVMediaSessionResult MiniAV_MediaSession_SetPosition(
    MiniAVMediaSession *session, const MiniAVMediaSessionPosition *position);

MINIAV_MS_API MiniAVMediaSessionResult
MiniAV_MediaSession_SetActions(MiniAVMediaSession *session, uint32_t actions);

/*
 * Tear the session down. The shell card disappears and media keys stop routing
 * here. Blocks until the backend guarantees no further command callback will
 * fire, so the caller may close its NativeCallable immediately afterwards.
 */
MINIAV_MS_API MiniAVMediaSessionResult
MiniAV_MediaSession_Destroy(MiniAVMediaSession *session);

/*
 * Whether a session could be claimed on this machine, without claiming one.
 * Cheap and side-effect free. Returns 1 or 0.
 */
MINIAV_MS_API int MiniAV_MediaSession_IsSupported(void);

/*
 * Reason for the most recent UNSUPPORTED/INTERNAL result on THIS thread.
 *
 * Copies a NUL-terminated UTF-8 string into `buf` and returns the number of
 * bytes it wanted to write (excluding the NUL), so a caller can size a buffer
 * by passing (NULL, 0) first. Thread-local: two isolates cannot clobber each
 * other's reason.
 */
MINIAV_MS_API size_t MiniAV_MediaSession_LastError(char *buf, size_t buf_len);

/*
 * Short human-readable note about what the live backend actually did — which
 * window it adopted, which fallback tier it landed on.
 *
 * Exists because "the session registered but no card appeared" is the
 * characteristic SMTC failure, and it is invisible from the result code: the
 * session IS live and media keys DO route to it, the shell just has no app
 * identity to draw with. Same buffer protocol as MiniAV_MediaSession_LastError.
 * Diagnostic only — the text is not stable and must not be parsed.
 */
MINIAV_MS_API size_t MiniAV_MediaSession_Describe(char *buf, size_t buf_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* MINIAV_MEDIA_SESSION_H */
