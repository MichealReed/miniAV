/*
 * Placeholder backend: compiles everywhere, publishes nothing, and says so.
 *
 * This exists so the whole chain — Dart → dart:ffi → native asset → build hook
 * → CMake — is real and testable before any OS backend lands. Replace it one
 * platform at a time by adding the real translation unit to
 * MINIAV_MS_BACKEND_SOURCES in ../CMakeLists.txt; the linker then resolves
 * ms_platform_* to the real backend and this file is dropped from the build.
 *
 * It reports UNSUPPORTED rather than OK. A backend that accepted every call and
 * quietly did nothing would be indistinguishable from a working one that the
 * shell happens not to be showing — the exact failure mode that let miniAV's
 * per-process loopback report success for months while capturing the wrong
 * audio. Unimplemented must be observable.
 */
#include "media_session_internal.h"

static const char *ms_reason(void) {
#if defined(_WIN32)
  return "Windows SMTC backend not implemented yet "
         "(src/windows/media_session_smtc.cpp)";
#elif defined(__APPLE__)
  return "MPNowPlayingInfoCenter backend not implemented yet "
         "(src/apple/media_session_nowplaying.mm)";
#elif defined(__ANDROID__)
  return "Android MediaSession backend not implemented yet "
         "(src/android/media_session_android.c + JVM companion)";
#elif defined(__linux__)
  return "MPRIS backend not implemented yet "
         "(src/linux/media_session_mpris.c)";
#else
  return "no media-session backend for this platform";
#endif
}

int ms_platform_is_supported(void) { return 0; }

size_t ms_platform_describe(char *buf, size_t buf_len) {
  if (buf != NULL && buf_len > 0) buf[0] = '\0';
  return 0;
}

void ms_platform_set_host_window(void *hwnd) { (void)hwnd; }

MiniAVMediaSessionResult ms_platform_create(MiniAVMediaSession *session,
                                            const char *app_name) {
  (void)session;
  (void)app_name;
  ms_set_last_error(ms_reason());
  return MINIAV_MS_ERROR_UNSUPPORTED;
}

/* Every setter below is unreachable while create() fails — a session handle
 * only exists after a successful create. They are defined because the API
 * contract, not the current backend, decides which symbols must resolve. */
MiniAVMediaSessionResult ms_platform_destroy(MiniAVMediaSession *session) {
  (void)session;
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_metadata(
    MiniAVMediaSession *session, const MiniAVMediaSessionMetadata *metadata) {
  (void)session;
  (void)metadata;
  return MINIAV_MS_ERROR_UNSUPPORTED;
}

MiniAVMediaSessionResult ms_platform_set_state(MiniAVMediaSession *session,
                                               MiniAVMediaSessionState state) {
  (void)session;
  (void)state;
  return MINIAV_MS_ERROR_UNSUPPORTED;
}

MiniAVMediaSessionResult ms_platform_set_position(
    MiniAVMediaSession *session, const MiniAVMediaSessionPosition *position) {
  (void)session;
  (void)position;
  return MINIAV_MS_ERROR_UNSUPPORTED;
}

MiniAVMediaSessionResult ms_platform_set_actions(MiniAVMediaSession *session,
                                                 uint32_t actions) {
  (void)session;
  (void)actions;
  return MINIAV_MS_ERROR_UNSUPPORTED;
}
