/*
 * Internal seam between the public C API (media_session_api.c) and the one
 * platform backend that compiles into this library.
 *
 * There is no vtable and no runtime dispatch: exactly one backend translation
 * unit is added to the target by CMakeLists.txt, so the linker resolves
 * ms_platform_* directly. A backend that is not built for this platform simply
 * is not compiled — it cannot be selected by accident.
 */
#ifndef MINIAV_MEDIA_SESSION_INTERNAL_H
#define MINIAV_MEDIA_SESSION_INTERNAL_H

#include "miniav_media_session.h"

#ifdef __cplusplus
extern "C" {
#endif

struct MiniAVMediaSession {
  MiniAVMediaSessionCommandCallback on_command;
  void *user_data;
  uint32_t actions;
  /* Backend-private state, owned and freed by ms_platform_destroy. */
  void *platform;
};

/* Implemented by exactly one of src/<platform>/. */
MiniAVMediaSessionResult ms_platform_create(MiniAVMediaSession *session,
                                            const char *app_name);
MiniAVMediaSessionResult ms_platform_destroy(MiniAVMediaSession *session);
MiniAVMediaSessionResult
ms_platform_set_metadata(MiniAVMediaSession *session,
                         const MiniAVMediaSessionMetadata *metadata);
MiniAVMediaSessionResult ms_platform_set_state(MiniAVMediaSession *session,
                                               MiniAVMediaSessionState state);
MiniAVMediaSessionResult
ms_platform_set_position(MiniAVMediaSession *session,
                         const MiniAVMediaSessionPosition *position);
MiniAVMediaSessionResult ms_platform_set_actions(MiniAVMediaSession *session,
                                                 uint32_t actions);
int ms_platform_is_supported(void);
/* Short human-readable note about what the backend actually did (which window
 * it adopted, which tier it fell back to). Same buffer protocol as
 * MiniAV_MediaSession_LastError. Diagnostic only — never parsed. */
size_t ms_platform_describe(char *buf, size_t buf_len);
/* Windows backend overrides this; others get the no-op in media_session_api.c
 * through a weak-by-convention empty implementation in their own TU. */
void ms_platform_set_host_window(void *hwnd);

/* Record why the last call failed. Thread-local; safe to call from a backend
 * thread. Passing NULL clears it. */
void ms_set_last_error(const char *message);

/* Deliver a command to the owner. Filters out actions the session never
 * declared, so a backend that over-reports (Android's MediaSession will happily
 * hand you SKIP_TO_NEXT whether or not you advertised it) cannot surface a
 * control the app said it does not implement. */
void ms_emit_command(MiniAVMediaSession *session, uint32_t action,
                     int64_t position_us, int64_t offset_us);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* MINIAV_MEDIA_SESSION_INTERNAL_H */
