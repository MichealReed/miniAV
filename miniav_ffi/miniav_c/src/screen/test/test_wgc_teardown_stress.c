// Teardown/callback race stress harness for the Windows Graphics Capture
// backend (src/screen/windows/screen_context_win_wgc.cpp).
//
// WHAT IT EXERCISES
//   WGC delivers frames on WinRT threadpool threads, and wgc_on_frame_arrived
//   blocks in its FPS pacing loop *after* releasing the context's critical
//   section. Stopping/destroying the context from the main thread during that
//   window used to close the handles the callback was waiting on and free the
//   memory it was still reading. This harness slams that window: start
//   capture, sleep a randomised sub-frame interval, stop and/or destroy,
//   hundreds of times, at a deliberately LOW fps so the pacing loop is parked
//   for hundreds of milliseconds per frame.
//
// HOW IT DETECTS THE BUG
//   The backend keeps a liveness canary in the context (WGC_CTX_MAGIC_*) and
//   poisons it immediately before miniav_free(). Every threadpool entry point
//   and the pacing loop check it and log a line tagged "WGC-UAF-CANARY".
//   This harness counts those log lines and also reads the exported counter
//   miniav_wgc_debug_ctx_uaf_hits(). Non-zero at exit == the race fired.
//
// POSITIVE CONTROL
//   MINIAV_WGC_STRESS_NO_DRAIN=1    restore the pre-fix teardown (no drain,
//                                   stop-event-blind pacing fallback)
//   MINIAV_WGC_STRESS_PACE_SLEEP=1  force the pacing loop onto the no-waitable-
//                                   timer fallback, where the pre-fix window
//                                   was a full frame interval wide
//   Expected matrix (200 iterations, 2 fps):
//     NO_DRAIN=1 PACE_SLEEP=1 -> FAIL (canary hits)   <- reproduces the bug
//     NO_DRAIN=1              -> PASS (window is sub-microsecond on the
//                                      waitable-timer path)
//                PACE_SLEEP=1 -> PASS (drain alone closes it)
//     neither                 -> PASS
//
// USAGE
//   test_wgc_teardown_stress.exe [iterations] [fps] [max_sleep_ms]
//   defaults: 200 iterations, 2 fps, 320 ms

#include "../../../include/miniav.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

static volatile LONG g_uaf_log_hits = 0;
static volatile LONG g_drain_timeouts = 0;
static volatile LONG g_frames = 0;
static int g_verbose = 0;

static void stress_log_callback(MiniAVLogLevel level, const char *message,
                                void *user_data) {
  (void)user_data;
  if (message && strstr(message, "WGC-UAF-CANARY")) {
    InterlockedIncrement(&g_uaf_log_hits);
    fprintf(stderr, "[CANARY] %s\n", message);
    fflush(stderr);
    return;
  }
  if (message && strstr(message, "timed out") && strstr(message, "draining")) {
    InterlockedIncrement(&g_drain_timeouts);
    fprintf(stderr, "[DRAIN-TIMEOUT] %s\n", message);
    fflush(stderr);
    return;
  }
  (void)level;
  if (g_verbose) {
    fprintf(stderr, "[miniav] %s\n", message);
  }
}

static void stress_buffer_callback(const MiniAVBuffer *buffer,
                                   void *user_data) {
  (void)user_data;
  if (!buffer)
    return;
  InterlockedIncrement(&g_frames);
  if (buffer->internal_handle)
    MiniAV_ReleaseBuffer(buffer->internal_handle);
}

int main(int argc, char **argv) {
  unsigned iterations = (argc > 1) ? (unsigned)strtoul(argv[1], NULL, 10) : 200u;
  unsigned fps = (argc > 2) ? (unsigned)strtoul(argv[2], NULL, 10) : 2u;
  unsigned max_sleep_ms =
      (argc > 3) ? (unsigned)strtoul(argv[3], NULL, 10) : 320u;
  if (fps == 0)
    fps = 1;
  if (getenv("MINIAV_STRESS_VERBOSE"))
    g_verbose = 1;

  const char *no_drain = getenv("MINIAV_WGC_STRESS_NO_DRAIN");
  const char *pace_sleep = getenv("MINIAV_WGC_STRESS_PACE_SLEEP");
  printf("WGC teardown stress: %u iterations, %u fps, sleep 0..%u ms, "
         "teardown=%s, pacing=%s\n",
         iterations, fps, max_sleep_ms,
         (no_drain && no_drain[0] == '1') ? "LEGACY/no-drain (positive control)"
                                          : "drained (fixed)",
         (pace_sleep && pace_sleep[0] == '1') ? "no-timer fallback (forced)"
                                              : "waitable timer");
  fflush(stdout);

  MiniAV_SetLogCallback(stress_log_callback, NULL);
  MiniAV_SetLogLevel(g_verbose ? MINIAV_LOG_LEVEL_DEBUG
                               : MINIAV_LOG_LEVEL_WARN);

  // Resolve a display once; the per-iteration context does the rest.
  MiniAVDeviceInfo *displays = NULL;
  uint32_t display_count = 0;
  if (MiniAV_Screen_EnumerateDisplays(&displays, &display_count) !=
          MINIAV_SUCCESS ||
      display_count == 0) {
    fprintf(stderr, "No displays available — cannot run stress.\n");
    return 2;
  }
  char display_id[MINIAV_DEVICE_ID_MAX_LEN];
  strncpy(display_id, displays[0].device_id, sizeof(display_id) - 1);
  display_id[sizeof(display_id) - 1] = '\0';
  printf("Using display '%s' (%s)\n", displays[0].name, display_id);
  MiniAV_FreeDeviceList(displays, display_count);

  srand(0xC0FFEE); // deterministic schedule so runs are comparable

  unsigned started = 0, start_failures = 0;
  const unsigned frame_ms = 1000u / fps;

  for (unsigned i = 0; i < iterations; ++i) {
    MiniAVScreenContextHandle ctx = NULL;
    if (MiniAV_Screen_CreateContext(&ctx) != MINIAV_SUCCESS) {
      fprintf(stderr, "iter %u: CreateContext failed\n", i);
      ++start_failures;
      continue;
    }

    MiniAVVideoInfo fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.width = 1280;
    fmt.height = 720;
    fmt.output_preference = MINIAV_OUTPUT_PREFERENCE_CPU;
    fmt.frame_rate_numerator = fps;
    fmt.frame_rate_denominator = 1;

    if (MiniAV_Screen_ConfigureDisplay(ctx, display_id, &fmt, false) !=
        MINIAV_SUCCESS) {
      fprintf(stderr, "iter %u: ConfigureDisplay failed\n", i);
      MiniAV_Screen_DestroyContext(ctx);
      ++start_failures;
      continue;
    }

    if (MiniAV_Screen_StartCapture(ctx, stress_buffer_callback, NULL) !=
        MINIAV_SUCCESS) {
      fprintf(stderr, "iter %u: StartCapture failed\n", i);
      MiniAV_Screen_DestroyContext(ctx);
      ++start_failures;
      continue;
    }
    ++started;

    // Land the teardown at a random point, biased to fall INSIDE the pacing
    // wait (which spans most of a frame interval at low fps).
    unsigned sleep_ms = (unsigned)(rand() % (int)(max_sleep_ms + 1));
    if ((i & 3u) == 0u)
      sleep_ms = frame_ms / 2 + (unsigned)(rand() % 16); // dead centre
    Sleep(sleep_ms);

    // Alternate the two teardown entry points: explicit stop then destroy, and
    // destroy-while-streaming (which must do the same ordered teardown).
    ULONGLONG t0 = GetTickCount64();
    if ((i & 1u) == 0u)
      MiniAV_Screen_StopCapture(ctx);
    MiniAV_Screen_DestroyContext(ctx);
    ULONGLONG teardown_ms = GetTickCount64() - t0;

    if (teardown_ms > 1500) {
      fprintf(stderr,
              "iter %u: teardown took %llu ms (drain may be blocking)\n", i,
              (unsigned long long)teardown_ms);
    }

    if (((i + 1) % 25) == 0) {
      printf("  ...%u/%u iterations, frames=%ld, canary hits=%ld\n", i + 1,
             iterations, (long)g_frames, (long)g_uaf_log_hits);
      fflush(stdout);
    }
  }

  long exported_hits = -1;
  {
    HMODULE m = GetModuleHandleA("miniav_c.dll");
    if (!m)
      m = GetModuleHandleA(NULL);
    if (m) {
      typedef long (*uaf_fn)(void);
      uaf_fn fn = (uaf_fn)GetProcAddress(m, "miniav_wgc_debug_ctx_uaf_hits");
      if (fn)
        exported_hits = fn();
    }
  }

  printf("\n=== WGC teardown stress summary ===\n");
  printf("iterations started : %u (failed to start: %u)\n", started,
         start_failures);
  printf("frames delivered   : %ld\n", (long)g_frames);
  printf("UAF canary hits    : %ld (log) / %ld (exported counter)\n",
         (long)g_uaf_log_hits, exported_hits);
  printf("drain timeouts     : %ld\n", (long)g_drain_timeouts);
  fflush(stdout);

  if (g_uaf_log_hits != 0 || exported_hits > 0) {
    printf("RESULT: FAIL — callback threads touched destroyed contexts.\n");
    return 1;
  }
  if (g_drain_timeouts != 0) {
    printf("RESULT: FAIL — teardown drain timed out.\n");
    return 1;
  }
  printf("RESULT: PASS — no callback outlived its context.\n");
  return 0;
}
