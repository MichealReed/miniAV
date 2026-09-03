/*
 * Public C API for miniav_media_session: argument validation, session
 * lifetime, thread-local error reporting, and command fan-out to the owner.
 * All OS-specific work lives behind ms_platform_* (media_session_internal.h).
 */
#include <stdlib.h>
#include <string.h>

#include "media_session_internal.h"

#if defined(_MSC_VER)
#define MS_THREAD_LOCAL __declspec(thread)
#else
#define MS_THREAD_LOCAL __thread
#endif

#define MS_ERROR_MAX 256

/* Thread-local so two isolates calling into this library cannot clobber each
 * other's reason string. Sized to a fixed buffer rather than malloc'd: the
 * error path must not itself be able to fail. */
static MS_THREAD_LOCAL char g_last_error[MS_ERROR_MAX];

void ms_set_last_error(const char *message) {
  if (message == NULL) {
    g_last_error[0] = '\0';
    return;
  }
  size_t n = strlen(message);
  if (n >= MS_ERROR_MAX) n = MS_ERROR_MAX - 1;
  memcpy(g_last_error, message, n);
  g_last_error[n] = '\0';
}

size_t MiniAV_MediaSession_LastError(char *buf, size_t buf_len) {
  const size_t n = strlen(g_last_error);
  if (buf != NULL && buf_len > 0) {
    const size_t copy = (n < buf_len - 1) ? n : buf_len - 1;
    memcpy(buf, g_last_error, copy);
    buf[copy] = '\0';
  }
  return n;
}

size_t MiniAV_MediaSession_Describe(char *buf, size_t buf_len) {
  return ms_platform_describe(buf, buf_len);
}

void ms_emit_command(MiniAVMediaSession *session, uint32_t action,
                     int64_t position_us, int64_t offset_us) {
  if (session == NULL || session->on_command == NULL) return;
  /* Never surface a control the app did not declare. */
  if ((session->actions & action) == 0) return;
  session->on_command(action, position_us, offset_us, session->user_data);
}

int MiniAV_MediaSession_IsSupported(void) { return ms_platform_is_supported(); }

void MiniAV_MediaSession_SetHostWindow(void *hwnd) {
  ms_platform_set_host_window(hwnd);
}

MiniAVMediaSessionResult MiniAV_MediaSession_Create(
    const char *app_name, uint32_t actions,
    MiniAVMediaSessionCommandCallback on_command, void *user_data,
    MiniAVMediaSession **out_session) {
  if (out_session == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  *out_session = NULL;
  if (app_name == NULL || app_name[0] == '\0') {
    ms_set_last_error("app_name is required");
    return MINIAV_MS_ERROR_INVALID_ARG;
  }

  ms_set_last_error(NULL);

  MiniAVMediaSession *session = calloc(1, sizeof(MiniAVMediaSession));
  if (session == NULL) {
    ms_set_last_error("out of memory");
    return MINIAV_MS_ERROR_INTERNAL;
  }
  session->on_command = on_command;
  session->user_data = user_data;
  session->actions = actions;

  const MiniAVMediaSessionResult r = ms_platform_create(session, app_name);
  if (r != MINIAV_MS_OK) {
    /* The backend owns nothing on a failed create — it either published a
     * session or it did not. Freeing here keeps that invariant in one place. */
    free(session);
    return r;
  }

  *out_session = session;
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult MiniAV_MediaSession_Destroy(
    MiniAVMediaSession *session) {
  if (session == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  const MiniAVMediaSessionResult r = ms_platform_destroy(session);
  /* Drop the callback before freeing so a backend that failed to fully quiesce
   * cannot reach a dangling Dart NativeCallable through freed memory. The
   * session struct itself is still freed: a backend that cannot guarantee
   * quiescence must say so by blocking in ms_platform_destroy, not by leaving
   * the handle alive. */
  session->on_command = NULL;
  session->user_data = NULL;
  free(session);
  return r;
}

MiniAVMediaSessionResult MiniAV_MediaSession_SetMetadata(
    MiniAVMediaSession *session, const MiniAVMediaSessionMetadata *metadata) {
  if (session == NULL || metadata == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  return ms_platform_set_metadata(session, metadata);
}

MiniAVMediaSessionResult MiniAV_MediaSession_SetPlaybackState(
    MiniAVMediaSession *session, MiniAVMediaSessionState state) {
  if (session == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  return ms_platform_set_state(session, state);
}

MiniAVMediaSessionResult MiniAV_MediaSession_SetPosition(
    MiniAVMediaSession *session, const MiniAVMediaSessionPosition *position) {
  if (session == NULL || position == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  return ms_platform_set_position(session, position);
}

MiniAVMediaSessionResult MiniAV_MediaSession_SetActions(
    MiniAVMediaSession *session, uint32_t actions) {
  if (session == NULL) return MINIAV_MS_ERROR_INVALID_ARG;
  session->actions = actions;
  return ms_platform_set_actions(session, actions);
}
