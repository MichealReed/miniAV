// Per-process loopback ISOLATION harness (Windows/WASAPI).
//
// WHAT IT EXERCISES
//   Whether a "pid:<id>" loopback target delivers THAT PROCESS'S audio, or
//   just the whole system's with a process-shaped label on it.
//
//   The backend used to call
//       IAudioClient3::InitializeSharedAudioStream(flags, <PID>, fmt, NULL)
//   putting the target PID in the PeriodInFrames argument. That always failed
//   with AUDCLNT_E_INVALID_DEVICE_PERIOD and the backend quietly fell back to
//   whole-system loopback, so per-process capture had never once worked: every
//   caller got the entire machine's audio, correctly formatted.
//
// WHY "AUDIO ARRIVED" IS NOT AN ORACLE
//   The broken code delivered audio too — plenty of it, at the right sample
//   rate, in self-consistent buffers. Any check that only counts buffers, or
//   only measures loudness, passes on the bug. The oracle has to be able to
//   say WHOSE audio it is.
//
// HOW IT DETECTS IT
//   The harness re-executes ITSELF twice as a tone renderer (--tone <hz>):
//   child A emits 997 Hz, child B emits 3001 Hz. Both are audible to
//   whole-system loopback simultaneously. Then, for each capture target, a
//   Goertzel filter measures the energy at 997 Hz and at 3001 Hz in the
//   captured PCM and the harness asserts on the RATIO:
//
//     capture "pid:<A>"  -> 997 present, 3001 absent   (ratio >= 10x)
//     capture "pid:<B>"  -> 3001 present, 997 absent   (ratio >= 10x)
//     capture "pid:<C>"  -> neither present            (C renders silence)
//     capture NULL       -> BOTH present                (system-wide, the
//                                                        common path, must
//                                                        not regress)
//
//   Whole-system audio returned for a "pid:" target contains BOTH tones, so it
//   fails the first three assertions arithmetically. Frequencies are chosen
//   away from each other's harmonics (3001 is not a multiple of 997) so one
//   tone cannot masquerade as the other.
//
//   A fifth case checks that a dead PID is REFUSED rather than answered with
//   an endless silent stream (activation succeeds for a nonexistent PID at the
//   OS level — see TRAP 3 in the backend).
//
// POSITIVE CONTROL (restores the pre-fix behaviour)
//   MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK=1  (skip real process loopback)
//   MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK=1       (allow the silent
//                                                  substitution)
//   With BOTH set the harness INVERTS its expectations: the scoped captures
//   must now contain BOTH tones, and it exits non-zero if the bug does NOT
//   reproduce, so "the control ran and proved nothing" cannot pass for a pass.
//
// USAGE
//   test_loopback_process_isolation.exe [capture_seconds]   (default 3)
//   test_loopback_process_isolation.exe --tone <hz>         (internal)

#include "../../../include/miniav.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <windows.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define TONE_A_HZ 997.0
#define TONE_B_HZ 3001.0
#define ISOLATION_RATIO 10.0

static int g_verbose = 0;

static void iso_log_callback(MiniAVLogLevel level, const char *message,
                             void *user_data) {
  (void)user_data;
  (void)level;
  if (g_verbose && message)
    fprintf(stderr, "[miniav] %s\n", message);
}

// ---------------------------------------------------------------------------
// Tone renderer (child mode). Deliberately NOT MiniAV_AudioOutput: this must
// be raw WASAPI render so the harness is testing the capture side only, and so
// the child has no dependency on the module under test.
// ---------------------------------------------------------------------------
static const CLSID kCLSID_MMDeviceEnumerator = {
    0xbcde0395,
    0xe52f,
    0x467c,
    {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}};
static const IID kIID_IMMDeviceEnumerator = {
    0xa95664d2,
    0x9614,
    0x4f35,
    {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}};
static const IID kIID_IAudioClient = {
    0x1cb9ad4c,
    0xdbfa,
    0x4c32,
    {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2}};
static const IID kIID_IAudioRenderClient = {
    0xf294acfc,
    0x3146,
    0x4483,
    {0xa7, 0xbf, 0xad, 0xdc, 0xa7, 0xc2, 0x60, 0xe2}};

static int run_tone_child(double freq) {
  IMMDeviceEnumerator *en = NULL;
  IMMDevice *dev = NULL;
  IAudioClient *ac = NULL;
  IAudioRenderClient *rc = NULL;
  WAVEFORMATEX *mix = NULL;
  UINT32 buf_frames = 0;

  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(CoCreateInstance(&kCLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                              &kIID_IMMDeviceEnumerator, (void **)&en)))
    return 1;
  if (FAILED(en->lpVtbl->GetDefaultAudioEndpoint(en, eRender, eConsole, &dev)))
    return 1;
  if (FAILED(dev->lpVtbl->Activate(dev, &kIID_IAudioClient, CLSCTX_ALL, NULL,
                                   (void **)&ac)))
    return 1;
  if (FAILED(ac->lpVtbl->GetMixFormat(ac, &mix)))
    return 1;
  if (FAILED(ac->lpVtbl->Initialize(ac, AUDCLNT_SHAREMODE_SHARED, 0, 2000000, 0,
                                    mix, NULL)))
    return 1;
  ac->lpVtbl->GetBufferSize(ac, &buf_frames);
  if (FAILED(ac->lpVtbl->GetService(ac, &kIID_IAudioRenderClient, (void **)&rc)))
    return 1;
  ac->lpVtbl->Start(ac);

  const int is_float =
      (mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) ||
      (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE && mix->wBitsPerSample == 32);
  const double step = 2.0 * M_PI * freq / (double)mix->nSamplesPerSec;
  double phase = 0.0;

  printf("child pid=%lu hz=%.0f\n", GetCurrentProcessId(), freq);
  fflush(stdout);

  // Exits on its own if the parent dies, so a crashed harness cannot leave
  // tone generators running on the user's machine.
  HANDLE parent = NULL;
  {
    const char *ppid_s = getenv("MINIAV_ISO_PARENT_PID");
    if (ppid_s)
      parent = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)strtoul(ppid_s, NULL, 10));
  }

  for (;;) {
    if (parent && WaitForSingleObject(parent, 0) == WAIT_OBJECT_0)
      break;
    UINT32 pad = 0;
    if (FAILED(ac->lpVtbl->GetCurrentPadding(ac, &pad)))
      break;
    UINT32 avail = buf_frames - pad;
    if (avail == 0) {
      Sleep(5);
      continue;
    }
    BYTE *data = NULL;
    if (FAILED(rc->lpVtbl->GetBuffer(rc, avail, &data)))
      break;
    for (UINT32 i = 0; i < avail; ++i) {
      // -26 dBFS: comfortably above any noise floor, well below full scale.
      const double s = (freq > 0.0) ? sin(phase) * 0.05 : 0.0;
      phase += step;
      if (phase > 2.0 * M_PI)
        phase -= 2.0 * M_PI;
      for (UINT32 c = 0; c < mix->nChannels; ++c) {
        if (is_float)
          ((float *)data)[i * mix->nChannels + c] = (float)s;
        else
          ((short *)data)[i * mix->nChannels + c] = (short)(s * 32767.0);
      }
    }
    rc->lpVtbl->ReleaseBuffer(rc, avail, 0);
    Sleep(5);
  }
  ac->lpVtbl->Stop(ac);
  return 0;
}

// ---------------------------------------------------------------------------
// Capture side + Goertzel oracle
// ---------------------------------------------------------------------------
typedef struct {
  double s_prev_a, s_prev2_a, coeff_a;
  double s_prev_b, s_prev2_b, coeff_b;
  double sumsq;
  uint64_t samples;
  uint32_t rate;
  uint32_t channels;
  MiniAVAudioFormat format;
  volatile LONG buffers;
  CRITICAL_SECTION lock;
  int primed;
} Analyzer;

static void analyzer_prime(Analyzer *an, const MiniAVAudioInfo *info) {
  an->rate = info->sample_rate;
  an->channels = info->channels;
  an->format = info->format;
  an->coeff_a = 2.0 * cos(2.0 * M_PI * TONE_A_HZ / (double)an->rate);
  an->coeff_b = 2.0 * cos(2.0 * M_PI * TONE_B_HZ / (double)an->rate);
  an->primed = 1;
}

static double sample_at(const void *data, size_t index, MiniAVAudioFormat f) {
  switch (f) {
  case MINIAV_AUDIO_FORMAT_F32:
    return (double)((const float *)data)[index];
  case MINIAV_AUDIO_FORMAT_S16:
    return ((const short *)data)[index] / 32768.0;
  case MINIAV_AUDIO_FORMAT_S32:
    return ((const int *)data)[index] / 2147483648.0;
  case MINIAV_AUDIO_FORMAT_U8:
    return (((const unsigned char *)data)[index] - 128) / 128.0;
  default:
    return 0.0;
  }
}

static void capture_callback(const MiniAVBuffer *buffer, void *user_data) {
  Analyzer *an = (Analyzer *)user_data;
  if (!buffer || buffer->type != MINIAV_BUFFER_TYPE_AUDIO || !an)
    goto release;

  InterlockedIncrement(&an->buffers);
  if (buffer->data_size_bytes == 0 || !buffer->data.audio.data)
    goto release;

  EnterCriticalSection(&an->lock);
  if (!an->primed)
    analyzer_prime(an, &buffer->data.audio.info);
  {
    const MiniAVAudioInfo info = buffer->data.audio.info;
    const uint32_t ch = info.channels ? info.channels : 1;
    const uint32_t frames = buffer->data.audio.frame_count;
    for (uint32_t i = 0; i < frames; ++i) {
      // Mono-sum: a tone rendered to both channels stays a tone.
      double x = 0.0;
      for (uint32_t c = 0; c < ch; ++c)
        x += sample_at(buffer->data.audio.data, (size_t)i * ch + c, info.format);
      x /= (double)ch;

      double s = x + an->coeff_a * an->s_prev_a - an->s_prev2_a;
      an->s_prev2_a = an->s_prev_a;
      an->s_prev_a = s;

      s = x + an->coeff_b * an->s_prev_b - an->s_prev2_b;
      an->s_prev2_b = an->s_prev_b;
      an->s_prev_b = s;

      an->sumsq += x * x;
      an->samples++;
    }
  }
  LeaveCriticalSection(&an->lock);

release:
  if (buffer && buffer->internal_handle)
    MiniAV_ReleaseBuffer(buffer->internal_handle);
}

// Goertzel magnitude, normalised by sample count so runs of different length
// are comparable.
static double goertzel_mag(double s_prev, double s_prev2, double coeff,
                           uint64_t n) {
  if (n == 0)
    return 0.0;
  const double power =
      s_prev * s_prev + s_prev2 * s_prev2 - coeff * s_prev * s_prev2;
  return sqrt(power > 0.0 ? power : 0.0) / (double)n;
}

typedef struct {
  double mag_a;
  double mag_b;
  double rms;
  long buffers;
  uint64_t samples;
  MiniAVResultCode configure_result;
  MiniAVLoopbackTargetType active_scope;
  uint32_t active_pid;
  MiniAVAudioInfo format;
} CaptureResult;

static CaptureResult capture_target(const char *target_id, unsigned seconds) {
  CaptureResult out;
  Analyzer an;
  MiniAVLoopbackContextHandle lb = NULL;
  MiniAVAudioInfo want;

  memset(&out, 0, sizeof(out));
  memset(&an, 0, sizeof(an));
  InitializeCriticalSection(&an.lock);

  memset(&want, 0, sizeof(want));
  want.format = MINIAV_AUDIO_FORMAT_F32;
  want.channels = 2;
  want.sample_rate = 48000;

  out.configure_result = MiniAV_Loopback_CreateContext(&lb);
  if (out.configure_result != MINIAV_SUCCESS)
    goto done;

  out.configure_result = MiniAV_Loopback_Configure(lb, target_id, &want);
  if (out.configure_result != MINIAV_SUCCESS) {
    MiniAV_Loopback_DestroyContext(lb);
    lb = NULL;
    goto done;
  }

  MiniAV_Loopback_GetConfiguredFormat(lb, &out.format);
  {
    MiniAVLoopbackTargetInfo active;
    memset(&active, 0, sizeof(active));
    if (MiniAV_Loopback_GetActiveTargetInfo(lb, &active) == MINIAV_SUCCESS) {
      out.active_scope = active.type;
      out.active_pid = active.TARGETHANDLE.process_id;
    }
  }

  if (MiniAV_Loopback_StartCapture(lb, capture_callback, &an) !=
      MINIAV_SUCCESS) {
    out.configure_result = MINIAV_ERROR_SYSTEM_CALL_FAILED;
    MiniAV_Loopback_DestroyContext(lb);
    lb = NULL;
    goto done;
  }
  Sleep(seconds * 1000);
  MiniAV_Loopback_StopCapture(lb);
  MiniAV_Loopback_DestroyContext(lb);
  lb = NULL;

  EnterCriticalSection(&an.lock);
  out.buffers = an.buffers;
  out.samples = an.samples;
  out.mag_a = goertzel_mag(an.s_prev_a, an.s_prev2_a, an.coeff_a, an.samples);
  out.mag_b = goertzel_mag(an.s_prev_b, an.s_prev2_b, an.coeff_b, an.samples);
  out.rms = an.samples ? sqrt(an.sumsq / (double)an.samples) : 0.0;
  LeaveCriticalSection(&an.lock);

done:
  DeleteCriticalSection(&an.lock);
  return out;
}

// ---------------------------------------------------------------------------
static HANDLE spawn_tone(const char *self_path, double hz, DWORD *pid_out,
                         HANDLE *read_out) {
  char cmd[1024];
  SECURITY_ATTRIBUTES sa;
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  HANDLE rd = NULL, wr = NULL;

  memset(&sa, 0, sizeof(sa));
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  if (!CreatePipe(&rd, &wr, &sa, 0))
    return NULL;
  SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);

  snprintf(cmd, sizeof(cmd), "\"%s\" --tone %.0f", self_path, hz);

  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = wr;
  si.hStdError = wr;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  memset(&pi, 0, sizeof(pi));

  if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL,
                      &si, &pi)) {
    CloseHandle(rd);
    CloseHandle(wr);
    return NULL;
  }
  CloseHandle(wr);
  CloseHandle(pi.hThread);
  *pid_out = pi.dwProcessId;
  *read_out = rd;
  return pi.hProcess;
}

static void kill_child(HANDLE h, HANDLE rd) {
  if (h) {
    TerminateProcess(h, 0);
    WaitForSingleObject(h, 2000);
    CloseHandle(h);
  }
  if (rd)
    CloseHandle(rd);
}

static const char *scope_name(MiniAVLoopbackTargetType t) {
  switch (t) {
  case MINIAV_LOOPBACK_TARGET_PROCESS:
    return "PROCESS";
  case MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO:
    return "SYSTEM_AUDIO";
  case MINIAV_LOOPBACK_TARGET_WINDOW:
    return "WINDOW";
  default:
    return "NONE";
  }
}

static void report(const char *label, const CaptureResult *r) {
  printf("  %-22s scope=%-12s pid=%-6u buffers=%-5ld  "
         "E(997)=%.6f  E(3001)=%.6f  rms=%.6f\n",
         label, scope_name(r->active_scope), r->active_pid, r->buffers,
         r->mag_a, r->mag_b, r->rms);
}

int main(int argc, char **argv) {
  if (argc >= 3 && strcmp(argv[1], "--tone") == 0)
    return run_tone_child(atof(argv[2]));

  const unsigned seconds =
      (argc > 1) ? (unsigned)strtoul(argv[1], NULL, 10) : 3u;
  if (getenv("MINIAV_STRESS_VERBOSE"))
    g_verbose = 1;

  const char *no_pl = getenv("MINIAV_LOOPBACK_STRESS_NO_PROCESS_LOOPBACK");
  const char *allow_fb = getenv("MINIAV_LOOPBACK_ALLOW_SYSTEM_FALLBACK");
  const int control_mode =
      (no_pl && no_pl[0] == '1') && (allow_fb && allow_fb[0] == '1');

  printf("Loopback per-process ISOLATION harness: mode=%s\n",
         control_mode ? "LEGACY/whole-system substitution (positive control)"
                      : "real per-process loopback (fixed)");
  fflush(stdout);

  MiniAV_SetLogCallback(iso_log_callback, NULL);
  MiniAV_SetLogLevel(g_verbose ? MINIAV_LOG_LEVEL_DEBUG
                               : MINIAV_LOG_LEVEL_ERROR);

  char self_path[MAX_PATH];
  GetModuleFileNameA(NULL, self_path, MAX_PATH);
  {
    char ppid[32];
    snprintf(ppid, sizeof(ppid), "%lu", GetCurrentProcessId());
    SetEnvironmentVariableA("MINIAV_ISO_PARENT_PID", ppid);
  }

  DWORD pid_a = 0, pid_b = 0, pid_silent = 0;
  HANDLE rd_a = NULL, rd_b = NULL, rd_s = NULL;
  HANDLE h_a = spawn_tone(self_path, TONE_A_HZ, &pid_a, &rd_a);
  HANDLE h_b = spawn_tone(self_path, TONE_B_HZ, &pid_b, &rd_b);
  HANDLE h_s = spawn_tone(self_path, 0.0, &pid_silent, &rd_s);
  if (!h_a || !h_b || !h_s) {
    fprintf(stderr, "  could not spawn tone children\n");
    kill_child(h_a, rd_a);
    kill_child(h_b, rd_b);
    kill_child(h_s, rd_s);
    return 2;
  }
  printf("  tone A (%.0f Hz) pid=%lu, tone B (%.0f Hz) pid=%lu, silent "
         "pid=%lu\n",
         TONE_A_HZ, pid_a, TONE_B_HZ, pid_b, pid_silent);
  Sleep(1200); // let the render streams come up

  char id_a[64], id_b[64], id_s[64], id_dead[64];
  snprintf(id_a, sizeof(id_a), "pid:%lu", pid_a);
  snprintf(id_b, sizeof(id_b), "pid:%lu", pid_b);
  snprintf(id_s, sizeof(id_s), "pid:%lu", pid_silent);

  // A PID that is definitely not running: spawn a child and let it exit.
  {
    DWORD dead_pid = 0;
    HANDLE rd_d = NULL;
    HANDLE h_d = spawn_tone(self_path, 0.0, &dead_pid, &rd_d);
    if (h_d) {
      TerminateProcess(h_d, 0);
      WaitForSingleObject(h_d, 2000);
      CloseHandle(h_d);
      CloseHandle(rd_d);
    }
    snprintf(id_dead, sizeof(id_dead), "pid:%lu", dead_pid ? dead_pid : 999998u);
  }

  int failures = 0;

  printf("\n[1] Whole-system loopback (NULL target) — must hear BOTH tones\n");
  CaptureResult sys = capture_target(NULL, seconds);
  report("system", &sys);
  if (sys.configure_result != MINIAV_SUCCESS) {
    fprintf(stderr, "  FAIL: system-wide Configure -> %s\n",
            MiniAV_GetErrorString(sys.configure_result));
    ++failures;
  } else if (sys.buffers == 0 || sys.samples == 0) {
    fprintf(stderr, "  INCONCLUSIVE: system loopback delivered no PCM; the "
                    "endpoint may be disabled. Nothing below can be trusted.\n");
    kill_child(h_a, rd_a);
    kill_child(h_b, rd_b);
    kill_child(h_s, rd_s);
    return 3;
  } else if (sys.active_scope != MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO) {
    fprintf(stderr, "  FAIL: system target reports scope %s\n",
            scope_name(sys.active_scope));
    ++failures;
  }

  // Reference levels: what each tone looks like when it IS present. Taken
  // from the system capture, which by construction contains both.
  const double ref_a = sys.mag_a;
  const double ref_b = sys.mag_b;
  if (ref_a <= 0.0 || ref_b <= 0.0 ||
      ref_a < 10.0 * (sys.rms * 1e-3) /* sanity */) {
    fprintf(stderr,
            "  INCONCLUSIVE: system capture does not contain both reference "
            "tones (E997=%.6f E3001=%.6f). Cannot judge isolation.\n",
            sys.mag_a, sys.mag_b);
    kill_child(h_a, rd_a);
    kill_child(h_b, rd_b);
    kill_child(h_s, rd_s);
    return 3;
  }

  printf("\n[2] pid:<A> — must hear 997 and NOT 3001\n");
  CaptureResult ca = capture_target(id_a, seconds);
  report(id_a, &ca);
  printf("\n[3] pid:<B> — must hear 3001 and NOT 997\n");
  CaptureResult cb = capture_target(id_b, seconds);
  report(id_b, &cb);
  printf("\n[4] pid:<silent> — must hear NEITHER\n");
  CaptureResult cs = capture_target(id_s, seconds);
  report(id_s, &cs);

  printf("\n[5] pid:<dead> — must be REFUSED, not answered with silence\n");
  CaptureResult cd = capture_target(id_dead, 0);
  printf("  %-22s Configure -> %s\n", id_dead,
         cd.configure_result == MINIAV_SUCCESS
             ? "SUCCESS"
             : MiniAV_GetErrorString(cd.configure_result));

  printf("\n--- verdict ---\n");

  if (control_mode) {
    // The control must REPRODUCE the bug: the "scoped" captures are really
    // whole-system, so they contain both tones.
    const int a_leaks = ca.configure_result == MINIAV_SUCCESS &&
                        ca.mag_b > ref_b / ISOLATION_RATIO;
    const int b_leaks = cb.configure_result == MINIAV_SUCCESS &&
                        cb.mag_a > ref_a / ISOLATION_RATIO;
    const int s_leaks = cs.configure_result == MINIAV_SUCCESS &&
                        (cs.mag_a > ref_a / ISOLATION_RATIO ||
                         cs.mag_b > ref_b / ISOLATION_RATIO);
    if (!a_leaks || !b_leaks || !s_leaks) {
      fprintf(stderr,
              "  FAIL: control did not reproduce — expected every 'scoped' "
              "capture to contain the OTHER process's tone "
              "(A leaks=%d, B leaks=%d, silent leaks=%d)\n",
              a_leaks, b_leaks, s_leaks);
      ++failures;
    } else {
      printf("  control reproduced: every 'pid:' capture carries the whole "
             "system's audio\n");
    }
    if (ca.active_scope != MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO) {
      fprintf(stderr, "  FAIL: substituted capture must REPORT SYSTEM_AUDIO, "
                      "reported %s\n",
              scope_name(ca.active_scope));
      ++failures;
    } else {
      printf("  and it is reported honestly: GetActiveTargetInfo -> "
             "SYSTEM_AUDIO\n");
    }
  } else {
    struct {
      const char *label;
      CaptureResult *r;
      double want;  // magnitude that must be PRESENT (0 = none)
      double *ref_want;
      double *ref_other;
      double other; // magnitude that must be ABSENT
      DWORD pid;
    } cases[3] = {
        {"pid:<A>", &ca, ca.mag_a, (double *)&ref_a, (double *)&ref_b, ca.mag_b,
         pid_a},
        {"pid:<B>", &cb, cb.mag_b, (double *)&ref_b, (double *)&ref_a, cb.mag_a,
         pid_b},
        {"pid:<silent>", &cs, 0.0, NULL, NULL, 0.0, pid_silent},
    };

    for (int i = 0; i < 3; ++i) {
      CaptureResult *r = cases[i].r;
      if (r->configure_result != MINIAV_SUCCESS) {
        fprintf(stderr, "  FAIL: %s Configure -> %s\n", cases[i].label,
                MiniAV_GetErrorString(r->configure_result));
        ++failures;
        continue;
      }
      if (r->active_scope != MINIAV_LOOPBACK_TARGET_PROCESS ||
          r->active_pid != cases[i].pid) {
        fprintf(stderr,
                "  FAIL: %s reports scope %s pid %u — not real process "
                "scope\n",
                cases[i].label, scope_name(r->active_scope), r->active_pid);
        ++failures;
        continue;
      }
      if (i == 2) {
        // Silent process: NEITHER tone may appear.
        const int leaks = (r->mag_a > ref_a / ISOLATION_RATIO) ||
                          (r->mag_b > ref_b / ISOLATION_RATIO);
        if (leaks) {
          fprintf(stderr,
                  "  FAIL: %s carries other processes' audio "
                  "(E997=%.6f vs ref %.6f, E3001=%.6f vs ref %.6f)\n",
                  cases[i].label, r->mag_a, ref_a, r->mag_b, ref_b);
          ++failures;
        } else {
          printf("  PASS: %s is silent — no other process leaked in\n",
                 cases[i].label);
        }
        continue;
      }
      const double present = cases[i].want;
      const double absent = cases[i].other;
      const double ref_present = *cases[i].ref_want;
      const double ref_absent = *cases[i].ref_other;
      const int has_own = present > ref_present / ISOLATION_RATIO;
      const int has_other = absent > ref_absent / ISOLATION_RATIO;
      if (!has_own) {
        fprintf(stderr,
                "  FAIL: %s did not carry its OWN tone (%.6f, ref %.6f)\n",
                cases[i].label, present, ref_present);
        ++failures;
      } else if (has_other) {
        fprintf(stderr,
                "  FAIL: %s carried the OTHER process's tone (%.6f, ref "
                "%.6f) — this is whole-system audio, not scoped\n",
                cases[i].label, absent, ref_absent);
        ++failures;
      } else {
        printf("  PASS: %s carries only its own tone (own %.6f, other %.6f, "
               "%.0fx separation)\n",
               cases[i].label, present, absent,
               absent > 0.0 ? present / absent : 999.0);
      }
    }

    if (cd.configure_result == MINIAV_SUCCESS) {
      fprintf(stderr, "  FAIL: a dead PID was accepted — it would have "
                      "delivered silence forever with no error\n");
      ++failures;
    } else {
      printf("  PASS: a dead PID is refused (%s)\n",
             MiniAV_GetErrorString(cd.configure_result));
    }
  }

  kill_child(h_a, rd_a);
  kill_child(h_b, rd_b);
  kill_child(h_s, rd_s);

  printf("\n=== %s ===\n", failures == 0 ? "PASS" : "FAIL");
  return failures == 0 ? 0 : 1;
}
