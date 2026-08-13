// Loopback format-honesty + target-ID parsing harness (Windows/WASAPI).
//
// WHAT IT EXERCISES
//   Two bugs that both made the loopback backend report something other than
//   what it was doing, with no error and no log:
//
//   A. FORMAT HONESTY. MiniAV_Loopback_Configure used to overwrite the
//      backend's negotiated format with the CALLER'S REQUEST. WASAPI
//      shared-mode loopback has no format negotiation at all — it always runs
//      at the endpoint mix format — so on any endpoint whose mix format is not
//      what the caller asked for, MiniAV_Loopback_GetConfiguredFormat and the
//      `info` stamped on every delivered PCM buffer described a format the
//      bytes were not in. Muxing that audio writes the wrong sample rate into
//      the container header: audible pitch/speed corruption.
//
//   B. TARGET-ID PARSING. The WGC screen backend formatted its per-process
//      audio target as "PID:%lu" while this API parsed a case-SENSITIVE
//      "pid:". Every per-window audio request therefore fell through to the
//      "assume an MMDevice ID" branch and failed.
//
// HOW IT DETECTS THEM (oracles that do not trust the code under test)
//   A1. GetConfiguredFormat must equal MiniAV_Loopback_GetDefaultFormat (the
//       endpoint mix format read straight from IAudioClient::GetMixFormat),
//       NOT the deliberately-wrong format we requested.
//   A2. For every non-silent delivered buffer:
//           data_size_bytes == frame_count * channels * bytes_per_sample
//       computed from the buffer's OWN reported info. WASAPI produces
//       nBlockAlign-sized frames at the mix format, so a mislabelled buffer
//       fails this arithmetically — no special endpoint hardware required.
//   B1. Configuring with the uppercase "PID:<self>" that WGC actually emitted
//       must succeed.
//
// POSITIVE CONTROLS (restore the pre-fix behaviour)
//   MINIAV_LOOPBACK_STRESS_REQUESTED_FORMAT=1   -> A1/A2 must FAIL
//   MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID=1  -> B1 must FAIL
//   With a flag set the harness INVERTS its expectation: it exits non-zero if
//   the bug does NOT reproduce, so "the control ran and proved nothing" cannot
//   be mistaken for a pass.
//
// USAGE
//   test_loopback_format_honesty.exe [capture_seconds]   (default 4)

#include "../../../include/miniav.h"
// NOTE: miniav.h is the umbrella header but does NOT pull in the playback API;
// without this include MiniAV_AudioOutput_CreateContext is implicitly declared
// as returning int, the handle is truncated to 32 bits, and the harness
// segfaults inside ma_engine_init.
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

static void honesty_log_callback(MiniAVLogLevel level, const char *message,
                                 void *user_data) {
  (void)user_data;
  (void)level;
  if (g_verbose && message) {
    fprintf(stderr, "[miniav] %s\n", message);
  }
}

static const char *fmt_name(MiniAVAudioFormat f) {
  switch (f) {
  case MINIAV_AUDIO_FORMAT_U8:
    return "U8";
  case MINIAV_AUDIO_FORMAT_S16:
    return "S16";
  case MINIAV_AUDIO_FORMAT_S32:
    return "S32";
  case MINIAV_AUDIO_FORMAT_F32:
    return "F32";
  case MINIAV_AUDIO_FORMAT_F64:
    return "F64";
  default:
    return "UNKNOWN";
  }
}

static uint32_t bytes_per_sample(MiniAVAudioFormat f) {
  switch (f) {
  case MINIAV_AUDIO_FORMAT_U8:
    return 1;
  case MINIAV_AUDIO_FORMAT_S16:
    return 2;
  case MINIAV_AUDIO_FORMAT_S32:
    return 4;
  case MINIAV_AUDIO_FORMAT_F32:
    return 4;
  case MINIAV_AUDIO_FORMAT_F64:
    return 8;
  default:
    return 0;
  }
}

// --- Capture-side accounting -------------------------------------------------
static volatile LONG g_buffers = 0;
static volatile LONG g_nonsilent = 0;
static volatile LONG g_size_mismatches = 0;
static volatile LONG g_info_mismatches = 0;
static MiniAVAudioInfo g_expected_info;   // the endpoint mix format
static MiniAVAudioInfo g_first_seen_info; // whatever the first buffer claimed
static volatile LONG g_first_seen = 0;

static void capture_callback(const MiniAVBuffer *buffer, void *user_data) {
  (void)user_data;
  if (!buffer || buffer->type != MINIAV_BUFFER_TYPE_AUDIO)
    return;
  InterlockedIncrement(&g_buffers);

  const MiniAVAudioInfo info = buffer->data.audio.info;
  if (InterlockedExchange(&g_first_seen, 1) == 0) {
    g_first_seen_info = info;
  }

  if (info.sample_rate != g_expected_info.sample_rate ||
      info.channels != g_expected_info.channels ||
      info.format != g_expected_info.format) {
    InterlockedIncrement(&g_info_mismatches);
  }

  // Oracle A2: the buffer must be self-consistent.
  if (buffer->data_size_bytes > 0) {
    InterlockedIncrement(&g_nonsilent);
    const uint32_t bps = bytes_per_sample(info.format);
    const size_t expect =
        (size_t)buffer->data.audio.frame_count * info.channels * bps;
    if (bps == 0 || expect != buffer->data_size_bytes) {
      InterlockedIncrement(&g_size_mismatches);
      if (g_size_mismatches <= 3) {
        fprintf(stderr,
                "[MISLABEL] buffer says %u Hz / %u ch / %s -> %zu bytes "
                "expected for %u frames, but carries %zu bytes\n",
                info.sample_rate, info.channels, fmt_name(info.format), expect,
                buffer->data.audio.frame_count, buffer->data_size_bytes);
      }
    }
  }

  if (buffer->internal_handle)
    MiniAV_ReleaseBuffer(buffer->internal_handle);
}

// --- A very quiet in-process tone, so the endpoint is actually running -------
// WASAPI loopback delivers nothing (or SILENT-flagged packets carrying zero
// bytes) from an idle endpoint, and a silent packet cannot exercise the
// byte-size oracle. Amplitude is deliberately near-inaudible.
typedef struct {
  MiniAVAudioOutputContextHandle ctx;
  HANDLE thread;
  volatile LONG stop;
  uint32_t rate;
  uint32_t channels;
} ToneSource;

static DWORD WINAPI tone_thread(LPVOID param) {
  ToneSource *t = (ToneSource *)param;
  const uint32_t chunk = 480;
  float *pcm = (float *)malloc(sizeof(float) * chunk * t->channels);
  if (!pcm)
    return 1;
  double phase = 0.0;
  const double step = 2.0 * M_PI * 440.0 / (double)t->rate;
  while (!InterlockedCompareExchange(&t->stop, 0, 0)) {
    for (uint32_t i = 0; i < chunk; ++i) {
      const float s = (float)(sin(phase) * 0.002); // ~ -54 dBFS
      phase += step;
      if (phase > 2.0 * M_PI)
        phase -= 2.0 * M_PI;
      for (uint32_t c = 0; c < t->channels; ++c)
        pcm[i * t->channels + c] = s;
    }
    int written = MiniAV_AudioOutput_WriteFrames(t->ctx, pcm, chunk);
    if (written < 0)
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
  t->rate = 48000;
  t->channels = 2;
  t->ctx = MiniAV_AudioOutput_CreateContext();
  if (!t->ctx) {
    free(t);
    return NULL;
  }
  if (MiniAV_AudioOutput_Configure(t->ctx, NULL, MINIAV_AUDIO_FORMAT_F32,
                                   t->rate, t->channels, 0) != MINIAV_SUCCESS ||
      MiniAV_AudioOutput_Start(t->ctx) != MINIAV_SUCCESS) {
    MiniAV_AudioOutput_DestroyContext(t->ctx);
    free(t);
    return NULL;
  }
  t->thread = CreateThread(NULL, 0, tone_thread, t, 0, NULL);
  if (!t->thread) {
    MiniAV_AudioOutput_DestroyContext(t->ctx);
    free(t);
    return NULL;
  }
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

// --- Test B: target-ID prefix parsing ---------------------------------------
static int run_target_id_test(int expect_uppercase_to_work) {
  char id_upper[64], id_lower[64];
  const DWORD self = GetCurrentProcessId();
  // "PID:" is byte-for-byte what the WGC screen backend used to emit.
  snprintf(id_upper, sizeof(id_upper), "PID:%lu", self);
  snprintf(id_lower, sizeof(id_lower), "pid:%lu", self);

  MiniAVAudioInfo want;
  memset(&want, 0, sizeof(want));
  want.format = MINIAV_AUDIO_FORMAT_F32;
  want.channels = 2;
  want.sample_rate = 48000;

  int failures = 0;
  const char *ids[2] = {id_upper, id_lower};
  for (int i = 0; i < 2; ++i) {
    MiniAVLoopbackContextHandle ctx = NULL;
    if (MiniAV_Loopback_CreateContext(&ctx) != MINIAV_SUCCESS) {
      fprintf(stderr, "  [B] CreateContext failed\n");
      return 1;
    }
    MiniAVResultCode r = MiniAV_Loopback_Configure(ctx, ids[i], &want);
    const int ok = (r == MINIAV_SUCCESS);
    const int expected = (i == 0) ? expect_uppercase_to_work : 1;
    printf("  [B] Configure(\"%s\") -> %s%s\n", ids[i],
           ok ? "SUCCESS" : MiniAV_GetErrorString(r),
           ok == expected ? "" : "   <-- UNEXPECTED");
    if (ok != expected)
      ++failures;
    MiniAV_Loopback_DestroyContext(ctx);
  }
  return failures;
}

int main(int argc, char **argv) {
  const unsigned seconds = (argc > 1) ? (unsigned)strtoul(argv[1], NULL, 10) : 4u;
  if (getenv("MINIAV_STRESS_VERBOSE"))
    g_verbose = 1;

  const char *legacy_fmt = getenv("MINIAV_LOOPBACK_STRESS_REQUESTED_FORMAT");
  const char *legacy_id = getenv("MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID");
  const int legacy_format_mode = (legacy_fmt && legacy_fmt[0] == '1');
  const int legacy_id_mode = (legacy_id && legacy_id[0] == '1');

  printf("Loopback format-honesty harness: format=%s, target-id=%s\n",
         legacy_format_mode ? "LEGACY/requested (positive control)"
                            : "negotiated (fixed)",
         legacy_id_mode ? "LEGACY/case-sensitive (positive control)"
                        : "case-insensitive (fixed)");
  fflush(stdout);

  MiniAV_SetLogCallback(honesty_log_callback, NULL);
  MiniAV_SetLogLevel(g_verbose ? MINIAV_LOG_LEVEL_DEBUG
                               : MINIAV_LOG_LEVEL_ERROR);

  int failures = 0;

  // Start the render stream first so the endpoint is already running by the
  // time capture starts.
  ToneSource *tone = tone_start();

  // ---- B: target-ID prefix parsing ----
  printf("\n[B] Per-process target-ID prefix parsing\n");
  failures += run_target_id_test(/*expect_uppercase_to_work=*/!legacy_id_mode);

  // ---- A: format honesty ----
  printf("\n[A] Reported format vs endpoint mix format\n");
  MiniAVAudioInfo mix;
  memset(&mix, 0, sizeof(mix));
  if (MiniAV_Loopback_GetDefaultFormat(NULL, &mix) != MINIAV_SUCCESS ||
      mix.sample_rate == 0 || mix.channels == 0) {
    fprintf(stderr, "  GetDefaultFormat failed — no default render endpoint?\n");
    return 2;
  }
  printf("  Endpoint mix format (IAudioClient::GetMixFormat): %u Hz, %u ch, %s\n",
         mix.sample_rate, mix.channels, fmt_name(mix.format));

  // Ask for something the endpoint demonstrably is NOT. WASAPI shared-mode
  // loopback cannot honour any of this, which is the whole point.
  MiniAVAudioInfo wrong;
  memset(&wrong, 0, sizeof(wrong));
  wrong.sample_rate = (mix.sample_rate == 44100) ? 48000 : 44100;
  wrong.channels = (mix.channels == 1) ? 2 : 1;
  wrong.format = (mix.format == MINIAV_AUDIO_FORMAT_S16)
                     ? MINIAV_AUDIO_FORMAT_F32
                     : MINIAV_AUDIO_FORMAT_S16;
  wrong.num_frames = 1024;
  printf("  Requesting (deliberately unsupported):              %u Hz, %u ch, "
         "%s\n",
         wrong.sample_rate, wrong.channels, fmt_name(wrong.format));

  MiniAVLoopbackContextHandle lb = NULL;
  if (MiniAV_Loopback_CreateContext(&lb) != MINIAV_SUCCESS) {
    fprintf(stderr, "  CreateContext failed\n");
    return 2;
  }
  if (MiniAV_Loopback_Configure(lb, NULL, &wrong) != MINIAV_SUCCESS) {
    fprintf(stderr, "  Configure failed\n");
    MiniAV_Loopback_DestroyContext(lb);
    return 2;
  }

  MiniAVAudioInfo reported;
  memset(&reported, 0, sizeof(reported));
  if (MiniAV_Loopback_GetConfiguredFormat(lb, &reported) != MINIAV_SUCCESS) {
    fprintf(stderr, "  GetConfiguredFormat failed\n");
    MiniAV_Loopback_DestroyContext(lb);
    return 2;
  }
  printf("  GetConfiguredFormat reports:                        %u Hz, %u ch, "
         "%s\n",
         reported.sample_rate, reported.channels, fmt_name(reported.format));

  const int reports_mix = (reported.sample_rate == mix.sample_rate &&
                           reported.channels == mix.channels &&
                           reported.format == mix.format);
  const int reports_request = (reported.sample_rate == wrong.sample_rate &&
                               reported.channels == wrong.channels &&
                               reported.format == wrong.format);
  if (legacy_format_mode) {
    if (!reports_request) {
      fprintf(stderr, "  [A1] FAIL: control did not reproduce the bug "
                      "(expected the REQUESTED format to be reported)\n");
      ++failures;
    } else {
      printf("  [A1] control reproduced: reports the REQUESTED format\n");
    }
  } else {
    if (!reports_mix) {
      fprintf(stderr, "  [A1] FAIL: does not report the negotiated mix "
                      "format\n");
      ++failures;
    } else {
      printf("  [A1] PASS: reports the NEGOTIATED mix format\n");
    }
  }

  // ---- A2: per-buffer self-consistency ----
  g_expected_info = mix;
  if (!tone) {
    fprintf(stderr, "  [A2] SKIPPED: could not open an output device to drive "
                    "the endpoint (an idle endpoint yields no PCM to check).\n");
    MiniAV_Loopback_DestroyContext(lb);
    return failures ? 1 : 3;
  }
  Sleep(400); // let the render stream come up

  if (MiniAV_Loopback_StartCapture(lb, capture_callback, NULL) !=
      MINIAV_SUCCESS) {
    fprintf(stderr, "  StartCapture failed\n");
    tone_stop(tone);
    MiniAV_Loopback_DestroyContext(lb);
    return 2;
  }
  printf("  capturing %u s...\n", seconds);
  fflush(stdout);
  Sleep(seconds * 1000);
  MiniAV_Loopback_StopCapture(lb);
  tone_stop(tone);
  MiniAV_Loopback_DestroyContext(lb);

  printf("\n  buffers=%ld (non-silent=%ld)\n", (long)g_buffers,
         (long)g_nonsilent);
  if (g_first_seen) {
    printf("  buffers stamped: %u Hz, %u ch, %s\n", g_first_seen_info.sample_rate,
           g_first_seen_info.channels, fmt_name(g_first_seen_info.format));
  }
  printf("  info != mix format: %ld    size != frames*ch*bps: %ld\n",
         (long)g_info_mismatches, (long)g_size_mismatches);

  if (g_nonsilent == 0) {
    fprintf(stderr, "  [A2] INCONCLUSIVE: no non-silent PCM was delivered; the "
                    "byte-size oracle never ran.\n");
    return failures ? 1 : 3;
  }

  if (legacy_format_mode) {
    if (g_size_mismatches == 0 || g_info_mismatches == 0) {
      fprintf(stderr, "  [A2] FAIL: control did not reproduce the mislabelling "
                      "(expected every buffer to be mislabelled)\n");
      ++failures;
    } else {
      printf("  [A2] control reproduced: every delivered buffer is "
             "mislabelled\n");
    }
  } else {
    if (g_size_mismatches != 0 || g_info_mismatches != 0) {
      fprintf(stderr, "  [A2] FAIL: delivered buffers are mislabelled\n");
      ++failures;
    } else {
      printf("  [A2] PASS: every delivered buffer is self-consistent and "
             "matches the mix format\n");
    }
  }

  printf("\n=== %s ===\n", failures == 0 ? "PASS" : "FAIL");
  return failures == 0 ? 0 : 1;
}
