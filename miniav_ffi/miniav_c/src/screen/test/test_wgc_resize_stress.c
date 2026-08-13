// Frame-pool resize harness for the Windows Graphics Capture backend
// (src/screen/windows/screen_context_win_wgc.cpp).
//
// WHAT IT EXERCISES
//   1. FRAME POOL vs CONTENT SIZE. The Direct3D11CaptureFramePool was created
//      once from capture_item.Size() at StartCapture and never recreated, but
//      per-frame dimensions were taken from the live frame.ContentSize(). Grow
//      a captured window mid-capture and the CPU path computed
//      data_size_bytes = RowPitch(pool-sized) * height(new, larger) — a length
//      that runs past the end of the mapped staging buffer. The GPU path had
//      the same shape (width*height*4 against a pool-sized texture).
//   2. WINDOW CAPTURE WITH AUDIO. The same window is first configured with
//      capture_audio = true. Before the "PID:"/"pid:" parse fix that silently
//      produced a video-only capture that still returned MINIAV_SUCCESS.
//
// HOW IT DETECTS (1)
//   The backend now cross-checks every delivered buffer against D3D's OWN
//   report of what it mapped/allocated (mapped RowPitch * texture height, or
//   texture width*height*4) and counts violations in
//   miniav_wgc_debug_oversize_reports(). That oracle does not depend on the
//   frame-pool bookkeeping being fixed, so it stays valid either way.
//   miniav_wgc_debug_pool_recreates() proves the resize actually happened
//   rather than the window silently refusing to grow.
//
// POSITIVE CONTROLS
//   MINIAV_WGC_STRESS_NO_POOL_RECREATE=1  pool is never recreated AND buffer
//                                         sizes are reported from the raw
//                                         ContentSize -> oversize reports MUST
//                                         be non-zero (the harness fails if the
//                                         bug does NOT reproduce).
//   MINIAV_WGC_STRESS_UPPERCASE_PID=1 together with
//   MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID=1
//                                         restores BOTH halves of the original
//                                         mismatch (producer writes "PID:",
//                                         consumer matches case-sensitively)
//                                         -> the audio target cannot resolve.
//                                         ConfigureWindow MUST now fail; it
//                                         used to return SUCCESS and hand back
//                                         a video-only capture.
//
// USAGE
//   test_wgc_resize_stress.exe [grow_steps] [fps]      defaults: 12, 30

#include "../../../include/miniav.h"
// miniav.h does not pull in the playback API; without this the audio-output
// handle would be implicitly declared as int and truncated.
#include "../../../include/miniav_playback.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static int g_verbose = 0;
static volatile LONG g_frames = 0;
static volatile LONG g_audio_buffers = 0;
static volatile LONG g_oversize_logs = 0;
static volatile LONG g_max_w = 0, g_max_h = 0;

static void resize_log_callback(MiniAVLogLevel level, const char *message,
                                void *user_data) {
  (void)user_data;
  (void)level;
  if (message && strstr(message, "WGC-OVERSIZE")) {
    if (InterlockedIncrement(&g_oversize_logs) <= 5) {
      fprintf(stderr, "[OVERSIZE] %s\n", message);
      fflush(stderr);
    }
    return;
  }
  if (g_verbose && message)
    fprintf(stderr, "[miniav] %s\n", message);
}

static void frame_callback(const MiniAVBuffer *buffer, void *user_data) {
  (void)user_data;
  if (!buffer)
    return;
  if (buffer->type == MINIAV_BUFFER_TYPE_VIDEO) {
    InterlockedIncrement(&g_frames);
    LONG w = (LONG)buffer->data.video.info.width;
    LONG h = (LONG)buffer->data.video.info.height;
    if (w > g_max_w)
      g_max_w = w;
    if (h > g_max_h)
      g_max_h = h;
  } else if (buffer->type == MINIAV_BUFFER_TYPE_AUDIO) {
    InterlockedIncrement(&g_audio_buffers);
  }
  if (buffer->internal_handle)
    MiniAV_ReleaseBuffer(buffer->internal_handle);
}

// --- A near-inaudible render stream, so loopback has something to capture ----
typedef struct {
  MiniAVAudioOutputContextHandle ctx;
  HANDLE thread;
  volatile LONG stop;
} ToneSource;

static DWORD WINAPI tone_thread(LPVOID param) {
  ToneSource *t = (ToneSource *)param;
  const uint32_t chunk = 480, channels = 2, rate = 48000;
  float *pcm = (float *)malloc(sizeof(float) * chunk * channels);
  if (!pcm)
    return 1;
  double phase = 0.0;
  const double step = 2.0 * M_PI * 440.0 / (double)rate;
  while (!InterlockedCompareExchange(&t->stop, 0, 0)) {
    for (uint32_t i = 0; i < chunk; ++i) {
      const float s = (float)(sin(phase) * 0.002); // ~ -54 dBFS
      phase += step;
      if (phase > 2.0 * M_PI)
        phase -= 2.0 * M_PI;
      pcm[i * channels + 0] = s;
      pcm[i * channels + 1] = s;
    }
    if (MiniAV_AudioOutput_WriteFrames(t->ctx, pcm, chunk) < 0)
      break;
    Sleep(5);
  }
  free(pcm);
  return 0;
}

static ToneSource *tone_start(void) {
  ToneSource *t = (ToneSource *)calloc(1, sizeof(ToneSource));
  if (!t)
    return NULL;
  t->ctx = MiniAV_AudioOutput_CreateContext();
  if (!t->ctx) {
    free(t);
    return NULL;
  }
  if (MiniAV_AudioOutput_Configure(t->ctx, NULL, MINIAV_AUDIO_FORMAT_F32, 48000,
                                   2, 0) != MINIAV_SUCCESS ||
      MiniAV_AudioOutput_Start(t->ctx) != MINIAV_SUCCESS) {
    MiniAV_AudioOutput_DestroyContext(t->ctx);
    free(t);
    return NULL;
  }
  t->thread = CreateThread(NULL, 0, tone_thread, t, 0, NULL);
  return t;
}

static void tone_stop(ToneSource *t) {
  if (!t)
    return;
  InterlockedExchange(&t->stop, 1);
  if (t->thread) {
    WaitForSingleObject(t->thread, 2000);
    CloseHandle(t->thread);
  }
  MiniAV_AudioOutput_Stop(t->ctx);
  MiniAV_AudioOutput_DestroyContext(t->ctx);
  free(t);
}

// --- A plain, static capture target ----------------------------------------
// Solid fill, repainted only when Windows asks. Deliberately no animation.
static HWND g_target_hwnd = NULL;
static volatile LONG g_window_ready = 0;

static LRESULT CALLBACK target_wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
  if (m == WM_PAINT) {
    PAINTSTRUCT ps;
    HDC dc = BeginPaint(h, &ps);
    HBRUSH br = CreateSolidBrush(RGB(40, 70, 110));
    FillRect(dc, &ps.rcPaint, br);
    DeleteObject(br);
    EndPaint(h, &ps);
    return 0;
  }
  if (m == WM_CLOSE)
    return 0; // only the harness closes it
  return DefWindowProcW(h, m, w, l);
}

static DWORD WINAPI window_thread(LPVOID param) {
  (void)param;
  WNDCLASSEXW wc;
  memset(&wc, 0, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = target_wndproc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.lpszClassName = L"MiniAVResizeStressTarget";
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  RegisterClassExW(&wc);

  g_target_hwnd = CreateWindowExW(
      WS_EX_APPWINDOW, wc.lpszClassName, L"miniAV WGC resize target",
      WS_OVERLAPPEDWINDOW, 80, 80, 640, 360, NULL, NULL, wc.hInstance, NULL);
  if (!g_target_hwnd) {
    InterlockedExchange(&g_window_ready, -1);
    return 1;
  }
  ShowWindow(g_target_hwnd, SW_SHOWNOACTIVATE);
  UpdateWindow(g_target_hwnd);
  InterlockedExchange(&g_window_ready, 1);

  MSG msg;
  while (GetMessageW(&msg, NULL, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  return 0;
}

typedef long (*wgc_counter_fn)(void);
static wgc_counter_fn resolve_counter(const char *name) {
  HMODULE m = GetModuleHandleA("miniav_c.dll");
  if (!m)
    m = GetModuleHandleA(NULL);
  return m ? (wgc_counter_fn)GetProcAddress(m, name) : NULL;
}

int main(int argc, char **argv) {
  const unsigned steps = (argc > 1) ? (unsigned)strtoul(argv[1], NULL, 10) : 12u;
  const unsigned fps = (argc > 2) ? (unsigned)strtoul(argv[2], NULL, 10) : 30u;
  if (getenv("MINIAV_STRESS_VERBOSE"))
    g_verbose = 1;

  const char *no_recreate = getenv("MINIAV_WGC_STRESS_NO_POOL_RECREATE");
  const char *legacy_id = getenv("MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID");
  const char *legacy_pid = getenv("MINIAV_WGC_STRESS_UPPERCASE_PID");
  const char *audio_opt = getenv("MINIAV_SCREEN_STRESS_AUDIO_OPTIONAL");
  const int audio_optional_mode = (audio_opt && audio_opt[0] == '1');
  const int legacy_pool_mode = (no_recreate && no_recreate[0] == '1');
  // Both halves of the original mismatch must be restored for the audio target
  // to become unresolvable again.
  const int legacy_id_mode =
      (legacy_id && legacy_id[0] == '1') && (legacy_pid && legacy_pid[0] == '1');

  printf("WGC resize stress: %u grow steps @ %u fps, pool=%s, target-id=%s\n",
         steps, fps,
         legacy_pool_mode ? "LEGACY/never recreated (positive control)"
                          : "recreated on resize (fixed)",
         legacy_id_mode
             ? "LEGACY/\"PID:\" producer + case-sensitive consumer (positive "
               "control)"
             : "lowercase producer + case-insensitive consumer (fixed)");
  fflush(stdout);

  MiniAV_SetLogCallback(resize_log_callback, NULL);
  MiniAV_SetLogLevel(g_verbose ? MINIAV_LOG_LEVEL_DEBUG
                               : MINIAV_LOG_LEVEL_ERROR);

  wgc_counter_fn oversize_fn = resolve_counter("miniav_wgc_debug_oversize_reports");
  wgc_counter_fn recreate_fn = resolve_counter("miniav_wgc_debug_pool_recreates");
  if (!oversize_fn || !recreate_fn) {
    fprintf(stderr,
            "Could not resolve the WGC debug counters — the loaded miniav_c is "
            "STALE (rebuilt binary required).\n");
    return 2;
  }
  const long oversize_before = oversize_fn();
  const long recreate_before = recreate_fn();

  HANDLE wt = CreateThread(NULL, 0, window_thread, NULL, 0, NULL);
  if (!wt) {
    fprintf(stderr, "CreateThread for the target window failed\n");
    return 2;
  }
  for (int i = 0; i < 200 && InterlockedCompareExchange(&g_window_ready, 0, 0) == 0; ++i)
    Sleep(10);
  if (InterlockedCompareExchange(&g_window_ready, 0, 0) != 1 || !g_target_hwnd) {
    fprintf(stderr, "Target window did not come up\n");
    return 2;
  }
  char window_id[MINIAV_DEVICE_ID_MAX_LEN];
  snprintf(window_id, sizeof(window_id), "HWND:0x%p", (void *)g_target_hwnd);
  printf("Target window: %s\n", window_id);

  int failures = 0;

  MiniAVScreenContextHandle ctx = NULL;
  if (MiniAV_Screen_CreateContext(&ctx) != MINIAV_SUCCESS) {
    fprintf(stderr, "Screen CreateContext failed\n");
    return 2;
  }

  MiniAVVideoInfo fmt;
  memset(&fmt, 0, sizeof(fmt));
  fmt.width = 640;
  fmt.height = 360;
  fmt.output_preference = MINIAV_OUTPUT_PREFERENCE_CPU;
  fmt.frame_rate_numerator = fps;
  fmt.frame_rate_denominator = 1;

  // ---- Window capture WITH AUDIO ----
  printf("\n[audio] ConfigureWindow(capture_audio = true)\n");
  MiniAVResultCode cfg = MiniAV_Screen_ConfigureWindow(ctx, window_id, &fmt, true);
  if (legacy_id_mode && audio_optional_mode) {
    // Full pre-fix reproduction: the target ID cannot resolve AND the backend
    // degrades silently. Expect SUCCESS with no audio at all.
    if (cfg != MINIAV_SUCCESS) {
      fprintf(stderr,
              "  FAIL: control did not reproduce — expected the silent "
              "SUCCESS, got %s\n",
              MiniAV_GetErrorString(cfg));
      ++failures;
    } else {
      printf("  control: ConfigureWindow -> SUCCESS (audio target "
             "unresolvable, degraded silently)\n");
    }
  } else if (legacy_id_mode) {
    if (cfg == MINIAV_SUCCESS) {
      fprintf(stderr,
              "  FAIL: control did not reproduce — audio target could not be "
              "resolved yet ConfigureWindow returned SUCCESS\n");
      ++failures;
    } else {
      printf("  control reproduced: ConfigureWindow -> %s (audio target "
             "unresolvable; the honesty gate declines instead of degrading)\n",
             MiniAV_GetErrorString(cfg));
    }
  } else {
    if (cfg != MINIAV_SUCCESS) {
      fprintf(stderr, "  FAIL: ConfigureWindow with audio -> %s\n",
              MiniAV_GetErrorString(cfg));
      ++failures;
    } else {
      MiniAVVideoInfo gv;
      MiniAVAudioInfo ga;
      memset(&gv, 0, sizeof(gv));
      memset(&ga, 0, sizeof(ga));
      if (MiniAV_Screen_GetConfiguredFormats(ctx, &gv, &ga) == MINIAV_SUCCESS &&
          ga.sample_rate > 0 && ga.channels > 0) {
        printf("  audio configured — %u Hz, %u ch, fmt %d\n", ga.sample_rate,
               ga.channels, (int)ga.format);
      } else {
        fprintf(stderr, "  FAIL: ConfigureWindow succeeded but no audio format "
                        "is reported\n");
        ++failures;
      }
    }
  }

  // Does audio actually ARRIVE? "Configured" is not "delivering".
  if (cfg == MINIAV_SUCCESS) {
    ToneSource *tone = tone_start();
    if (!tone) {
      fprintf(stderr, "  audio delivery check SKIPPED: no output device to "
                      "drive the endpoint.\n");
    } else {
      Sleep(400);
      if (MiniAV_Screen_StartCapture(ctx, frame_callback, NULL) ==
          MINIAV_SUCCESS) {
        Sleep(2500);
        MiniAV_Screen_StopCapture(ctx);
      }
      tone_stop(tone);
      printf("  audio buffers delivered during window capture: %ld (video: "
             "%ld)\n",
             (long)g_audio_buffers, (long)g_frames);
      if (legacy_id_mode) {
        if (g_audio_buffers != 0) {
          fprintf(stderr, "  FAIL: control delivered audio it should not "
                          "have\n");
          ++failures;
        } else {
          printf("  control reproduced: capture was reported as started but "
                 "delivered ZERO audio buffers\n");
        }
      } else if (g_audio_buffers == 0) {
        fprintf(stderr, "  FAIL: window capture with audio delivered NO audio "
                        "buffers\n");
        ++failures;
      } else {
        printf("  PASS: window capture with audio delivers audio\n");
      }
    }
    g_frames = 0;
    g_max_w = 0;
    g_max_h = 0;
  }

  // ---- Resize under capture (video only, so the run is not gated on audio) ----
  printf("\n[resize] video-only capture while the window grows\n");
  if (MiniAV_Screen_ConfigureWindow(ctx, window_id, &fmt, false) !=
      MINIAV_SUCCESS) {
    fprintf(stderr, "  ConfigureWindow (no audio) failed\n");
    MiniAV_Screen_DestroyContext(ctx);
    return 2;
  }
  if (MiniAV_Screen_StartCapture(ctx, frame_callback, NULL) != MINIAV_SUCCESS) {
    fprintf(stderr, "  StartCapture failed\n");
    MiniAV_Screen_DestroyContext(ctx);
    return 2;
  }

  Sleep(400); // a few frames at the original size first
  int w = 640, h = 360;
  for (unsigned i = 0; i < steps; ++i) {
    w += 64;
    h += 36;
    SetWindowPos(g_target_hwnd, NULL, 80, 80, w, h,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    Sleep(180); // several frames at each new size
  }
  Sleep(400);

  MiniAV_Screen_StopCapture(ctx);
  MiniAV_Screen_DestroyContext(ctx);

  PostMessageW(g_target_hwnd, WM_QUIT, 0, 0);
  WaitForSingleObject(wt, 2000);
  CloseHandle(wt);

  const long oversize = oversize_fn() - oversize_before;
  const long recreates = recreate_fn() - recreate_before;

  printf("\n  frames=%ld, largest reported frame=%ldx%ld\n", (long)g_frames,
         (long)g_max_w, (long)g_max_h);
  printf("  pool recreates=%ld    oversize reports=%ld (log hits=%ld)\n",
         recreates, oversize, (long)g_oversize_logs);

  if (g_frames == 0) {
    fprintf(stderr, "  INCONCLUSIVE: no frames were delivered.\n");
    return 3;
  }

  if (legacy_pool_mode) {
    if (oversize == 0) {
      fprintf(stderr, "  FAIL: control did not reproduce — expected buffers "
                      "advertising more bytes than were mapped.\n");
      ++failures;
    } else {
      printf("  control reproduced: %ld buffer(s) advertised more bytes than "
             "were mapped.\n",
             oversize);
    }
  } else {
    if (oversize != 0) {
      fprintf(stderr, "  FAIL: %ld buffer(s) advertised more bytes than were "
                      "mapped.\n",
              oversize);
      ++failures;
    } else if (recreates == 0) {
      fprintf(stderr, "  INCONCLUSIVE: the frame pool was never recreated, so "
                      "the resize path was not exercised.\n");
      return 3;
    } else {
      printf("  PASS: %ld pool recreate(s), no oversized buffers.\n", recreates);
    }
  }

  printf("\n=== %s ===\n", failures == 0 ? "PASS" : "FAIL");
  return failures == 0 ? 0 : 1;
}
