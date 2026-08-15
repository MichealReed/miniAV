/* mf_encoder.c — Windows Media Foundation H.264/HEVC video ENCODE.
 *
 * The encode analogue of mf_decoder.c. Prefers a HARDWARE (async) encoder MFT
 * and falls back to the sync MS software MFT, consuming system-memory NV12 and
 * emitting an elementary bitstream + SPS/PPS. Zero FFmpeg.
 *
 * Hardware MFTs are ASYNC: they must be unlocked, then driven through their
 * IMFMediaEventGenerator (one ProcessInput per METransformNeedInput, one
 * ProcessOutput per METransformHaveOutput). Enumerating with SYNCMFT alone
 * filters every hardware encoder out, which is what kept this software-only.
 *
 * Still a follow-up: D3D11 zero-copy TEXTURE input (input is CPU NV12, so a GPU
 * frame is read back before it reaches the encoder).
 *
 * Reuses the lessons from mf_aac.c: output-type-before-input for encoders, and
 * PRE-ALLOCATE the output IMFSample (the MS encoders don't provide their own →
 * ProcessOutput returns E_INVALIDARG otherwise).
 */

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#define COBJMACROS
#include <windows.h>
#include <codecapi.h>
#include <strmif.h> /* ICodecAPI (codecapi.h only declares its property GUIDs) */
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <mftransform.h>
#include <d3d11.h>
#include <d3d11_1.h> /* ID3D11Device1 / OpenSharedResource1 (NT handles) */
#include <dxgi1_2.h> /* IDXGIResource1::CreateSharedHandle (NT-handle sharing) */
#include <mfobjects.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MFENC_API __declspec(dllexport)

/* MF packs FRAME_SIZE / FRAME_RATE / PAR as a UINT64 = (hi << 32) | lo. This
 * avoids linking MFSetAttributeSize/Ratio. */
#define PACK64(hi, lo) (((UINT64)(UINT32)(hi) << 32) | (UINT32)(lo))

/* NV12 staging slots. A hardware encoder MFT signals NeedInput only when it has
 * a free input slot, so the number of samples it holds at once is small; four
 * is comfortably above that and costs ~11 MB of VRAM at 4K. */
#define MFENC_NV12_RING 4
/* Imported source textures kept open. The GPU processor feeding this path
 * recycles a shallow output ring, so a handful of entries turns the per-frame
 * OpenSharedResource into a pointer compare. */
#define MFENC_IMPORT_CACHE 4

/* TEST-ONLY fault injection — see miniav_shim_mfenc_set_fault.
 *
 * PER SESSION, deliberately: there is no global, no static and no environment
 * variable here. `dart test` runs every test FILE in its own isolate inside ONE
 * process, and these sessions all share that process (and its single MTA
 * worker), so a process-wide test flag is visible to every suite running
 * concurrently and would make unrelated encoders fail non-deterministically.
 * A field on the session the test itself created cannot leak that way. */
#define MFENC_FAULT_NONE 0        /* normal MFT behaviour */
#define MFENC_FAULT_NEVER_DRAIN 1 /* drain_state never reports complete */
#define MFENC_FAULT_NO_OUTPUT 2   /* input accepted, receive() yields nothing */

typedef struct {
  uint8_t *data; /* malloc'd elementary bitstream; caller frees */
  int size;
  int is_keyframe;
  int64_t pts_us;
} MiniAVMfEncFrame;

typedef struct {
  IMFTransform *mft;
  int width;
  int height;
  int64_t frame_dur_100ns; /* per-frame duration in 100-ns units */
  uint8_t extradata[256];  /* SPS/PPS (MF_MT_MPEG_SEQUENCE_HEADER) */
  int extradata_len;
  int started;

  /* Hardware / async MFT state. A hardware encoder MFT is an ASYNC MFT: it
   * does not answer ProcessInput/ProcessOutput on demand, it raises
   * METransformNeedInput / METransformHaveOutput on its event generator and we
   * may only call the matching method once per event. Sync software MFTs leave
   * all of this NULL/0 and take the original straight-line path. */
  IMFMediaEventGenerator *event_gen;
  int is_async;
  int is_hardware;
  int need_input;  /* unconsumed METransformNeedInput count */
  int have_output; /* unconsumed METransformHaveOutput count */
  /* Drain state machine. THREE states, and conflating any two of them wedges
   * the encoder:
   *   draining      — MFT_MESSAGE_COMMAND_DRAIN issued, tail still coming out.
   *   drain_done    — METransformDrainComplete seen for THAT drain.
   *   stream_ended  — the MFT has been drained and, per the MFT contract, will
   *                   not accept input again until it is told the stream
   *                   restarted. Without that message an async MFT never raises
   *                   another METransformNeedInput, so every submit path spins
   *                   to its timeout forever — flush() then encode() used to
   *                   wedge the shared MTA worker for every session. */
  int draining;
  int drain_done;
  int stream_ended;
  /* Bounded output-type renegotiations after MF_E_TRANSFORM_STREAM_CHANGE. An
   * MFT that keeps signalling a change must not turn receive() into a loop. */
  int stream_change_retries;
  /* MFENC_FAULT_* — a misbehaving MFT, simulated for THIS session only. Zero
   * for every session that does not deliberately set it, so the production
   * paths below are unchanged. See miniav_shim_mfenc_set_fault. */
  int fault;
  char mft_name[128]; /* MFT_FRIENDLY_NAME_Attribute, for diagnostics/tests */

  /* D3D11 zero-copy input. Present only on the hardware path: the MFT is bound
   * to this device via MFT_MESSAGE_SET_D3D_MANAGER *before* the media types are
   * set, which is what lets it consume a texture instead of system memory. */
  ID3D11Device *device;
  /* 0 when the device was injected by the caller -- we hold a reference either
   * way, so teardown is identical; this only records provenance. */
  int owns_device;
  IMFDXGIDeviceManager *dxgi_mgr;
  UINT reset_token;

  /* D3D11 VideoProcessor, for RGBA/BGRA texture input (the recorder's
   * scale/effects path). Built lazily on the first texture frame: a session
   * that only ever sees NV12 never pays for it.
   *
   * EVERYTHING here is built once and reused. The per-frame path must allocate
   * nothing: opening a shared resource is a kernel-object operation and
   * creating a processor view is a driver allocation, and paying either one
   * 60 times a second is exactly the kind of overhead that shows up as frame
   * pacing jitter rather than as a number in a profile. */
  ID3D11DeviceContext *ctx;
  ID3D11VideoDevice *vdev;
  ID3D11VideoContext *vctx;
  ID3D11VideoProcessorEnumerator *vp_enum;
  ID3D11VideoProcessor *vp;

  /* NV12 staging RING, not a single texture.
   *
   * A single shared staging texture is a read-write hazard: ProcessInput hands
   * the MFT a sample that merely REFERENCES the texture, and an async hardware
   * MFT reads it whenever it gets to it — so blitting the next frame into the
   * same surface can overwrite a picture the encoder is still consuming. That
   * is a tear, and it is intermittent and load-dependent, which is the worst
   * kind. The ring gives the encoder room to hold a couple of frames in
   * flight; [mfenc_pick_nv12] refuses to reuse a slot the MFT still holds. */
  ID3D11Texture2D *nv12_tex[MFENC_NV12_RING];
  ID3D11VideoProcessorOutputView *nv12_ov[MFENC_NV12_RING];
  /* Reference count of a slot that nothing but this session holds, sampled
   * once at construction. It is not necessarily 1: an output view keeps a
   * reference to its resource too, and how many is a driver detail. Calibrate
   * rather than assume. */
  unsigned long nv12_base_rc[MFENC_NV12_RING];
  int nv12_next;
  int nv12_last;       /* slot most recently blitted — read by the diagnostic */
  int nv12_busy_streak; /* consecutive "no free slot" answers; see below */

  /* One reusable fence for the blt, and the imported-source cache. */
  ID3D11Query *blt_fence;

  /* The surface handed to the MFT most recently, retained.
   *
   * A duplicate frame -- what the recorder emits to fill an idle CFR slot -- is
   * the SAME picture with a new timestamp. Re-importing the producer's texture
   * to express that is both wasteful and fragile: the producer owns that
   * surface's lifetime and may have recycled or released it by the time the
   * idle timer fires, which is exactly how duplicates ended up failing while
   * live frames succeeded. Holding our own reference makes a repeat
   * self-contained. */
  ID3D11Texture2D *last_sub;

  /* Why the most recent submission failed. Diagnostics, but load-bearing ones:
   * "could not import" is the same message for a QueryInterface miss, a
   * refused CreateSharedHandle and a cross-adapter OpenSharedResource, and
   * those have completely different fixes. Guessing between them from the
   * outside is what turned this into several wrong fixes in a row. Every
   * failure return in this file writes one. */
  char imp_err[224];
  struct {
    /* The producer's texture, REFERENCED — not a bare pointer.
     *
     * A pointer is not an identity: free a texture and the next allocation can
     * land on the same address, which on a resize or a ring rebuild is routine.
     * A pointer-keyed hit would then hand the encoder the OLD imported texture
     * and every frame would encode a stale picture forever, with success
     * reported at every step. Holding a reference makes the address
     * unreusable for as long as the entry lives.
     *
     * The tradeoff is VRAM: up to MFENC_IMPORT_CACHE producer surfaces stay
     * resident (4 x W x H x 4 B — ~135 MB at 4K, ~5 MB at 720p) until they are
     * evicted by a newer import, the session is destroyed, or the caller calls
     * miniav_shim_mfenc_invalidate_imports. That is why the invalidation entry
     * point exists: on a resolution change the producer's old surfaces are
     * dead weight AND a stale-hit hazard. */
    ID3D11Texture2D *key;
    ID3D11Texture2D *tex;
    ID3D11VideoProcessorInputView *iv;
    IDXGIKeyedMutex *km; /* NULL for MISC_SHARED sources, which have none */
  } imp[MFENC_IMPORT_CACHE];
  int imp_next;
} MfVidEnc;

/* Drain every queued event without blocking, tallying the ones we act on.
 * GetEvent has no timeout parameter, so NO_WAIT + an explicit sleep in the
 * caller is the only way to bound the wait. */
static void mfenc_pump(MfVidEnc *s) {
  if (!s->event_gen) return;
  for (;;) {
    IMFMediaEvent *ev = NULL;
    HRESULT hr = IMFMediaEventGenerator_GetEvent(s->event_gen,
                                                 MF_EVENT_FLAG_NO_WAIT, &ev);
    if (FAILED(hr) || !ev) break;
    MediaEventType met = 0;
    IMFMediaEvent_GetType(ev, &met);
    if (met == METransformNeedInput) {
      s->need_input++;
    } else if (met == METransformHaveOutput) {
      s->have_output++;
    } else if (met == METransformDrainComplete) {
      s->drain_done = 1;
      /* The MFT is now at end-of-stream and will refuse input until it is told
       * the stream restarted. Recorded here so the next submit can do it. */
      s->stream_ended = 1;
    }
    IMFMediaEvent_Release(ev);
  }
}

/* Wait (bounded) for the MFT to raise any event we care about.
 *
 * Two failure modes to avoid, both hit during development:
 *   - A BLOCKING GetEvent (flags=0) deadlocks whenever the expected event never
 *     comes — e.g. draining with nothing left to drain.
 *   - Polling with Sleep(1) costs a ~15.6 ms Windows timer quantum per
 *     iteration, which measured 3.05 s PER FRAME.
 * So: yield-spin (no timer involved) for a short budget, then degrade to coarse
 * sleeping, and give up rather than hang. Same shape as minigpu's event drain.
 * Returns 0 if an event of interest landed, -1 on timeout/closed generator. */
static int mfenc_wait_event(MfVidEnc *s) {
  if (!s->event_gen) return -1;

  /* An async MFT stops issuing METransformNeedInput until we take the output it
   * already has. Waiting for NeedInput while output is pending therefore stalls
   * until the timeout — report "not accepting" so the caller drains first. */
  mfenc_pump(s);
  /* drain_done is a wake condition ONLY while a drain is outstanding. Treating
   * it as one unconditionally made this return 0 instantly forever after the
   * first flush, and both submit paths spin `while (need_input == 0)` on that
   * answer — a livelock that never reached the timeout escape below. */
  if (s->need_input || (s->draining && s->drain_done)) return 0;
  if (s->have_output) return 1;

  /* Budget the spin in TIME, not iterations: SwitchToThread returns in ~ns when
   * nothing else is runnable, so an iteration count elapses instantly and drops
   * into the sleep path, where every Sleep(1) costs a ~15.6 ms timer quantum. */
  LARGE_INTEGER freq, t0, now;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t0);
  const double budget_s = 0.008; /* 8 ms — well inside a 30 fps frame */
  for (;;) {
    mfenc_pump(s);
    if (s->need_input || (s->draining && s->drain_done)) return 0;
    if (s->have_output) return 1;
    QueryPerformanceCounter(&now);
    if ((double)(now.QuadPart - t0.QuadPart) / (double)freq.QuadPart > budget_s)
      break;
    SwitchToThread();
  }
  return -1;
}

/* Bounded wait for DRAIN progress, specifically.
 *
 * mfenc_wait_event treats METransformNeedInput as a wake condition. That is
 * right on the submit path and wrong here: nothing consumes input credit during
 * a drain, and leftover credit is the NORMAL state at flush time — an async MFT
 * raises one METransformNeedInput per free input slot and the caller stops
 * submitting when it runs out of frames, not when the MFT is full. So
 * wait_event returned 0 with zero elapsed time on every drain poll, and the
 * "bounded ~8 ms" wait the flush loop is built on never happened: the Dart poll
 * loop became a hot spin issuing two marshalled round-trips per iteration,
 * holding the single shared MTA worker's gate against every other session.
 * Wake only on what a drain can actually make progress on.
 * Returns 0 if drain_done or output landed, -1 on timeout/closed generator. */
static int mfenc_wait_drain(MfVidEnc *s) {
  if (!s->event_gen) return -1;
  mfenc_pump(s);
  if (s->drain_done || s->have_output) return 0;

  LARGE_INTEGER freq, t0, now;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t0);
  const double budget_s = 0.008; /* same budget as the submit-side wait */
  for (;;) {
    mfenc_pump(s);
    if (s->drain_done || s->have_output) return 0;
    QueryPerformanceCounter(&now);
    if ((double)(now.QuadPart - t0.QuadPart) / (double)freq.QuadPart > budget_s)
      break;
    SwitchToThread();
  }
  return -1;
}

/* Yield-spin ~1 ms. Used ONLY by the injected drain fault: the real poll costs
 * a bounded ~8 ms inside mfenc_wait_drain, and returning instantly instead
 * would turn the caller's timeout loop into thousands of marshalled round-trips
 * a second, all of them holding the one shared MTA worker's gate against every
 * other session in the process. Yield rather than Sleep(1) for the same reason
 * mfenc_wait_event does: a Sleep costs a ~15.6 ms timer quantum. */
static void mfenc_fault_pause(void) {
  LARGE_INTEGER freq, t0, now;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&t0);
  const double budget_s = 0.001;
  for (;;) {
    QueryPerformanceCounter(&now);
    if ((double)(now.QuadPart - t0.QuadPart) / (double)freq.QuadPart > budget_s)
      return;
    SwitchToThread();
  }
}

/* Put the MFT back into "accepting input" before a new frame is submitted.
 *
 * MFT_MESSAGE_COMMAND_DRAIN ends the stream: the MFT must not be given more
 * input until MFT_MESSAGE_NOTIFY_START_OF_STREAM arrives. That message used to
 * be sent exactly once, at create — so flush() followed by encode() left an
 * async MFT that would never raise METransformNeedInput again. A drain that
 * timed out is treated the same way: restarting is the only recovery, and it
 * is cheaper than a wedged session.
 *
 * Called from every path that hands the MFT a new sample. */
static void mfenc_restart_stream(MfVidEnc *s) {
  if (!s->stream_ended && !s->draining) return;
  s->stream_ended = 0;
  s->draining = 0;
  s->drain_done = 0;
  /* Take everything already queued first, then FORGET the input credit: an MFT
   * re-issues METransformNeedInput from scratch in response to
   * MFT_MESSAGE_NOTIFY_START_OF_STREAM, so a credit counted before the drain is
   * not spendable now and calling ProcessInput on it is an error. Output
   * credit is left alone — it may still be the tail of the last segment. */
  mfenc_pump(s);
  s->need_input = 0;
  IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  mfenc_pump(s);
}

static int mfenc_started;

/* ICodecAPI + the two encoder-property GUIDs we need, declared locally so we
 * don't have to link strmiids/INITGUID (which would collide with the MF GUIDs
 * the CMake build already pulls from mfuuid.lib). Values are the canonical
 * Windows SDK codecapi.h / strmif.h definitions.
 *   AVLowLatencyMode  — TRUE disables B-frames + lookahead (live, low delay).
 *   AVEncMPVDefaultBPictureCount — belt-and-braces 0 B-frames. */
static const GUID kIID_ICodecAPI = {
    0x901db4c7,
    0x31ce,
    0x41a2,
    {0x85, 0xdc, 0x8f, 0xa0, 0xbf, 0x41, 0xb8, 0xda}};
static const GUID kCODECAPI_AVLowLatencyMode = {
    0x9c27891a,
    0xed7a,
    0x40e1,
    {0x88, 0xe8, 0xb2, 0x27, 0x27, 0xa0, 0x24, 0xee}};
static const GUID kCODECAPI_AVEncMPVDefaultBPictureCount = {
    0x8d390aac,
    0xdc5c,
    0x4200,
    {0xb5, 0x7f, 0x81, 0x4d, 0x04, 0xba, 0xba, 0xb2}};

/* ===================== MTA worker thread =====================
 *
 * Media Foundation requires MTA. A thread already initialised as STA makes
 * CoInitializeEx(COINIT_MULTITHREADED) fail with RPC_E_CHANGED_MODE, and
 * Flutter's UI thread IS STA — so every entry point below used to return
 * "no MFT" inside any Flutter app, and the encoder silently lost every
 * negotiation. Measured on an STA thread before this existed:
 *     mfenc_has_mft(h264) = 0 , mfenc_list_hw(h264) = -1
 *
 * Fix: own a dedicated thread that has never been CoInitialized, make it MTA
 * once, and marshal EVERY public call onto it. Chosen over hosting the encoder
 * in a Dart isolate because D3D11 shared handles are process-wide — they cross
 * a thread hop for free, so zero-copy survives — while an isolate would force
 * frame data across an isolate boundary.
 *
 * ALL calls go through here, including on threads that are already MTA. That
 * costs one hop but buys thread affinity: the MFT is created, driven and
 * destroyed on a single thread, which is what the async event model wants.
 *
 * Jobs run ONE AT A TIME. Encode calls for a session are already serialised by
 * the Dart side; concurrent *sessions* will contend on this lock. That is a
 * known limit, not an oversight — revisit with a per-session worker if a
 * multi-encoder workload ever needs it.
 */

typedef int (*mfenc_job_fn)(void *arg);

static CRITICAL_SECTION mfenc_w_lock;      /* guards the single job slot     */
static CRITICAL_SECTION mfenc_w_gate;      /* serialises submitters          */
static CONDITION_VARIABLE mfenc_w_todo;    /* signalled when a job is posted */
static CONDITION_VARIABLE mfenc_w_done;    /* signalled when a job finished  */
static HANDLE mfenc_w_thread = NULL;
static INIT_ONCE mfenc_w_once = INIT_ONCE_STATIC_INIT;
static mfenc_job_fn mfenc_w_fn = NULL;
static void *mfenc_w_arg = NULL;
static int mfenc_w_result = 0;
static int mfenc_w_pending = 0;
static int mfenc_w_ready = 0; /* worker reached its MTA loop */

static DWORD WINAPI mfenc_worker_main(LPVOID unused) {
  (void)unused;
  /* This thread has never been CoInitialized, so MTA always succeeds here. */
  HRESULT co = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  EnterCriticalSection(&mfenc_w_lock);
  mfenc_w_ready = SUCCEEDED(co) ? 1 : -1;
  WakeAllConditionVariable(&mfenc_w_done);
  for (;;) {
    while (!mfenc_w_pending)
      SleepConditionVariableCS(&mfenc_w_todo, &mfenc_w_lock, INFINITE);
    mfenc_job_fn fn = mfenc_w_fn;
    void *arg = mfenc_w_arg;
    LeaveCriticalSection(&mfenc_w_lock);

    int r = fn ? fn(arg) : 0;

    EnterCriticalSection(&mfenc_w_lock);
    mfenc_w_result = r;
    mfenc_w_pending = 0;
    mfenc_w_fn = NULL;
    WakeAllConditionVariable(&mfenc_w_done);
  }
}

static BOOL CALLBACK mfenc_worker_init(PINIT_ONCE o, PVOID p, PVOID *ctx) {
  (void)o; (void)p; (void)ctx;
  InitializeCriticalSection(&mfenc_w_lock);
  InitializeCriticalSection(&mfenc_w_gate);
  InitializeConditionVariable(&mfenc_w_todo);
  InitializeConditionVariable(&mfenc_w_done);
  mfenc_w_thread = CreateThread(NULL, 0, mfenc_worker_main, NULL, 0, NULL);
  if (!mfenc_w_thread) return FALSE;
  /* Wait for the apartment to be established before anyone posts work. */
  EnterCriticalSection(&mfenc_w_lock);
  while (!mfenc_w_ready)
    SleepConditionVariableCS(&mfenc_w_done, &mfenc_w_lock, INFINITE);
  LeaveCriticalSection(&mfenc_w_lock);
  return TRUE;
}

/* Run `fn(arg)` on the MTA worker and return its result. `fail` is returned if
 * the worker could not be started at all (never expected in practice). */
static int mfenc_on_worker(mfenc_job_fn fn, void *arg, int fail) {
  if (!InitOnceExecuteOnce(&mfenc_w_once, mfenc_worker_init, NULL, NULL))
    return fail;
  if (mfenc_w_ready != 1) return fail;

  EnterCriticalSection(&mfenc_w_gate); /* one submitter at a time */
  EnterCriticalSection(&mfenc_w_lock);
  mfenc_w_fn = fn;
  mfenc_w_arg = arg;
  mfenc_w_pending = 1;
  WakeAllConditionVariable(&mfenc_w_todo);
  while (mfenc_w_pending)
    SleepConditionVariableCS(&mfenc_w_done, &mfenc_w_lock, INFINITE);
  int r = mfenc_w_result;
  LeaveCriticalSection(&mfenc_w_lock);
  LeaveCriticalSection(&mfenc_w_gate);
  return r;
}

static int mf_up(void) {
  /* Always runs on the worker (MTA), so this now succeeds; S_FALSE for an
   * already-initialised thread is not a failure. */
  HRESULT co = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (co == RPC_E_CHANGED_MODE) return -1;
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return -1;
  mfenc_started++;
  return 0;
}

static void mf_down(void) {
  if (mfenc_started > 0) {
    mfenc_started--;
    MFShutdown();
  }
}

/* Availability: is there a video encoder MFT for this codec? codec 0=H264 1=HEVC */
static int mfenc_has_mft_impl(int codec) {
  if (mf_up() != 0) return 0;
  MFT_REGISTER_TYPE_INFO out = {MFMediaType_Video,
                                codec == 1 ? MFVideoFormat_HEVC
                                           : MFVideoFormat_H264};
  /* Must mirror create()'s union of passes, or availability disagrees with
   * what actually opens. */
  UINT32 flags = MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT |
                 MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_LOCALMFT |
                 MFT_ENUM_FLAG_SORTANDFILTER;
  IMFActivate **acts = NULL;
  UINT32 count = 0;
  HRESULT hr =
      MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, flags, NULL, &out, &acts, &count);
  if (SUCCEEDED(hr) && acts) {
    for (UINT32 i = 0; i < count; i++) IMFActivate_Release(acts[i]);
    CoTaskMemFree(acts);
  }
  mf_down();
  return (SUCCEEDED(hr) && count > 0) ? 1 : 0;
}

/* Diagnostic: list the HARDWARE video-encoder MFTs the OS exposes for a codec.
 * Writes "name|name|..." into out. Returns the count. Hardware MF encode is not
 * universal — notably NVIDIA does not ship an NVENC MFT on many systems — so a
 * caller needs to be able to see the real list rather than infer from a
 * fallback. */
static int mfenc_list_hw_impl(int codec, char *out, int cap) {
  if (out && cap > 0) out[0] = 0;
  if (mf_up() != 0) return -1;
  MFT_REGISTER_TYPE_INFO ot = {MFMediaType_Video,
                               codec == 1 ? MFVideoFormat_HEVC
                                          : MFVideoFormat_H264};
  IMFActivate **acts = NULL;
  UINT32 count = 0;
  HRESULT hr = MFTEnumEx(
      MFT_CATEGORY_VIDEO_ENCODER,
      MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_SORTANDFILTER,
      NULL, &ot, &acts, &count);
  int used = 0;
  if (SUCCEEDED(hr) && acts) {
    for (UINT32 i = 0; i < count; i++) {
      LPWSTR wname = NULL;
      UINT32 wlen = 0;
      if (out && SUCCEEDED(IMFActivate_GetAllocatedString(
                     acts[i], &MFT_FRIENDLY_NAME_Attribute, &wname, &wlen)) &&
          wname) {
        char tmp[128];
        WideCharToMultiByte(CP_UTF8, 0, wname, -1, tmp, sizeof(tmp) - 1, NULL, NULL);
        tmp[sizeof(tmp) - 1] = 0;
        int n = (int)strlen(tmp);
        if (used + n + 2 < cap) {
          if (used) out[used++] = '|';
          memcpy(out + used, tmp, (size_t)n);
          used += n;
          out[used] = 0;
        }
        CoTaskMemFree(wname);
      }
      IMFActivate_Release(acts[i]);
    }
    CoTaskMemFree(acts);
  }
  mf_down();
  return SUCCEEDED(hr) ? (int)count : -1;
}

static void *mfenc_create_impl(int codec, int width, int height,
                               int bitrate_bps, int fps_num, int fps_den,
                               int gop, int want_hardware, int candidate,
                               void *existing_device) {
  if (width <= 0 || height <= 0) return NULL;
  if (bitrate_bps <= 0) bitrate_bps = 4000000;
  if (fps_num <= 0) fps_num = 30;
  if (fps_den <= 0) fps_den = 1;
  if (mf_up() != 0) return NULL;

  MfVidEnc *s = (MfVidEnc *)calloc(1, sizeof(MfVidEnc));
  if (!s) {
    mf_down();
    return NULL;
  }
  s->width = width;
  s->height = height;
  s->frame_dur_100ns = (int64_t)10000000 * fps_den / fps_num;

  /* Enumerate an encoder MFT of the requested class.
   *
   * A hardware encoder is an ASYNC MFT, so MFT_ENUM_FLAG_HARDWARE must be
   * paired with ASYNCMFT — asking for SYNCMFT only (as this used to) filters
   * every hardware encoder out by construction, which is what kept this
   * software-only. TRANSCODE_ONLY is dropped from the hardware pass: it
   * restricts the list to MFTs registered for transcode and some vendor
   * encoders do not carry that registration. */
  {
    MFT_REGISTER_TYPE_INFO out = {MFMediaType_Video,
                                  codec == 1 ? MFVideoFormat_HEVC
                                             : MFVideoFormat_H264};
    UINT32 flags = want_hardware
                       ? (MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_ASYNCMFT |
                          MFT_ENUM_FLAG_SORTANDFILTER)
                       : (MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_LOCALMFT |
                          MFT_ENUM_FLAG_TRANSCODE_ONLY |
                          MFT_ENUM_FLAG_SORTANDFILTER);
    IMFActivate **acts = NULL;
    UINT32 count = 0;
    if (FAILED(MFTEnumEx(MFT_CATEGORY_VIDEO_ENCODER, flags, NULL, &out, &acts,
                         &count)) ||
        count == 0) {
      if (acts) CoTaskMemFree(acts);
      goto fail;
    }
    int seen = 0;
    for (UINT32 i = 0; i < count; i++) {
      if (!s->mft && (int)i >= candidate) {
        seen = 1;
        if (SUCCEEDED(IMFActivate_ActivateObject(acts[i], &IID_IMFTransform,
                                                 (void **)&s->mft)) &&
            s->mft) {
          s->is_hardware = want_hardware;
          /* Record the friendly name so a caller can prove WHICH MFT ran —
           * "it produced a bitstream" is not evidence of hardware. */
          LPWSTR wname = NULL;
          UINT32 wlen = 0;
          if (SUCCEEDED(IMFActivate_GetAllocatedString(
                  acts[i], &MFT_FRIENDLY_NAME_Attribute, &wname, &wlen)) &&
              wname) {
            WideCharToMultiByte(CP_UTF8, 0, wname, -1, s->mft_name,
                                (int)sizeof(s->mft_name) - 1, NULL, NULL);
            CoTaskMemFree(wname);
          }
        } else {
          s->mft = NULL;
        }
      }
      IMFActivate_Release(acts[i]);
    }
    CoTaskMemFree(acts);
    (void)seen;
    if (!s->mft) goto fail;
  }

  /* An async MFT refuses every call until it is unlocked, and this must happen
   * before the media types are set. */
  {
    IMFAttributes *attrs = NULL;
    if (SUCCEEDED(IMFTransform_GetAttributes(s->mft, &attrs)) && attrs) {
      UINT32 is_async = 0;
      IMFAttributes_GetUINT32(attrs, &MF_TRANSFORM_ASYNC, &is_async);
      if (is_async) {
        s->is_async = 1;
        IMFAttributes_SetUINT32(attrs, &MF_TRANSFORM_ASYNC_UNLOCK, TRUE);
      }
      IMFAttributes_Release(attrs);
    }
  }

  /* D3D11 device + DXGI manager, bound BEFORE the media types so the MFT can
   * negotiate a texture input pool. Hardware only; a failure here is not fatal
   * — the encoder still works from system memory. */
  if (want_hardware) {
    static const D3D_FEATURE_LEVEL kLevels[] = {D3D_FEATURE_LEVEL_11_1,
                                                D3D_FEATURE_LEVEL_11_0};
    UINT flags = D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    /* Prefer the caller's device.
     *
     * Creating our own means D3D11CreateDevice(NULL, ...) picks the DEFAULT
     * adapter, which is not necessarily the one the frames live on -- and even
     * on the same adapter it is a DIFFERENT device, so every frame has to be
     * shared and re-opened. When the producer hands us the device its textures
     * already live on, the import disappears entirely: the texture is simply
     * ours. That is both faster and one less thing that can fail. */
    /* An injected device is only usable if it can actually do the work.
     *
     * The texture path converts RGBA->NV12 with a VideoProcessor, which needs
     * to allocate an NV12 RENDER TARGET on this device. A device created
     * without D3D11_CREATE_DEVICE_VIDEO_SUPPORT -- which is the normal case for
     * a rendering device such as Dawn's -- QueryInterfaces to ID3D11VideoDevice
     * quite happily and then fails that allocation. Adopting it regardless
     * bought a same-device import and lost the conversion, which is the worse
     * half of the trade. Check before committing. */
    if (existing_device) {
      UINT sup = 0;
      HRESULT hs = ID3D11Device_CheckFormatSupport(
          (ID3D11Device *)existing_device, DXGI_FORMAT_NV12, &sup);
      const UINT need =
          D3D11_FORMAT_SUPPORT_TEXTURE2D | D3D11_FORMAT_SUPPORT_RENDER_TARGET;
      if (SUCCEEDED(hs) && (sup & need) == need) {
        s->device = (ID3D11Device *)existing_device;
        ID3D11Device_AddRef(s->device);
        s->owns_device = 0;
      }
    }
    if (!s->device && SUCCEEDED(D3D11CreateDevice(
                   NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags, kLevels,
                   ARRAYSIZE(kLevels), D3D11_SDK_VERSION, &s->device, NULL,
                   NULL))) {
      s->owns_device = 1;
    }
    if (s->device) {
      /* The MFT encodes on its own threads — without this the device is not
       * safe to share and drivers intermittently corrupt or crash. */
      ID3D10Multithread *mt = NULL;
      if (SUCCEEDED(ID3D11Device_QueryInterface(s->device, &IID_ID3D10Multithread,
                                                (void **)&mt)) && mt) {
        ID3D10Multithread_SetMultithreadProtected(mt, TRUE);
        ID3D10Multithread_Release(mt);
      }
      if (SUCCEEDED(MFCreateDXGIDeviceManager(&s->reset_token, &s->dxgi_mgr)) &&
          s->dxgi_mgr) {
        if (SUCCEEDED(IMFDXGIDeviceManager_ResetDevice(
                s->dxgi_mgr, (IUnknown *)s->device, s->reset_token))) {
          IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_SET_D3D_MANAGER,
                                      (ULONG_PTR)s->dxgi_mgr);
        }
      }
    }
  }

  /* OUTPUT type first (encoders require it). */
  {
    IMFMediaType *ot = NULL;
    if (FAILED(MFCreateMediaType(&ot))) goto fail;
    IMFMediaType_SetGUID(ot, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(ot, &MF_MT_SUBTYPE,
                         codec == 1 ? &MFVideoFormat_HEVC : &MFVideoFormat_H264);
    IMFMediaType_SetUINT32(ot, &MF_MT_AVG_BITRATE, (UINT32)bitrate_bps);
    IMFMediaType_SetUINT32(ot, &MF_MT_INTERLACE_MODE,
                           MFVideoInterlace_Progressive);
    IMFMediaType_SetUINT64(ot, &MF_MT_FRAME_SIZE, PACK64(width, height));
    IMFMediaType_SetUINT64(ot, &MF_MT_FRAME_RATE, PACK64(fps_num, fps_den));
    IMFMediaType_SetUINT64(ot, &MF_MT_PIXEL_ASPECT_RATIO, PACK64(1, 1));
    IMFMediaType_SetUINT32(
        ot, &MF_MT_MPEG2_PROFILE,
        codec == 1 ? eAVEncH265VProfile_Main_420_8
                   : (want_hardware ? eAVEncH264VProfile_Main
                                    : eAVEncH264VProfile_Base));
    HRESULT hr = IMFTransform_SetOutputType(s->mft, 0, ot, 0);
    IMFMediaType_Release(ot);
    if (FAILED(hr)) goto fail;
  }

  /* INPUT type (NV12). */
  {
    IMFMediaType *it = NULL;
    if (FAILED(MFCreateMediaType(&it))) goto fail;
    IMFMediaType_SetGUID(it, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
    IMFMediaType_SetGUID(it, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
    IMFMediaType_SetUINT32(it, &MF_MT_INTERLACE_MODE,
                           MFVideoInterlace_Progressive);
    IMFMediaType_SetUINT64(it, &MF_MT_FRAME_SIZE, PACK64(width, height));
    IMFMediaType_SetUINT64(it, &MF_MT_FRAME_RATE, PACK64(fps_num, fps_den));
    IMFMediaType_SetUINT64(it, &MF_MT_PIXEL_ASPECT_RATIO, PACK64(1, 1));
    /* ODD WIDTH: 4:2:0 chroma comes in PAIRS, so one NV12 row is an even number
     * of bytes and a system-memory frame at width 641 is laid out on a 642-byte
     * stride (see mfenc_send_nv12_impl, and the staging ring, which pads the
     * same way). Without this the MFT would assume stride == width and read
     * every row shifted. Set only when it differs, and fall back if the MFT
     * refuses the attribute — an encoder that will not take a stride hint is
     * still better off with the frame size alone than with no session at all,
     * and the texture path does not depend on it. */
    HRESULT hr;
    if (((width + 1) & ~1) != width) {
      IMFMediaType_SetUINT32(it, &MF_MT_DEFAULT_STRIDE,
                             (UINT32)((width + 1) & ~1));
      hr = IMFTransform_SetInputType(s->mft, 0, it, 0);
      if (FAILED(hr)) {
        IMFMediaType_DeleteItem(it, &MF_MT_DEFAULT_STRIDE);
        hr = IMFTransform_SetInputType(s->mft, 0, it, 0);
      }
    } else {
      hr = IMFTransform_SetInputType(s->mft, 0, it, 0);
    }
    IMFMediaType_Release(it);
    if (FAILED(hr)) goto fail;
  }

  /* Low-latency: the MS H.264 encoder defaults to B-frames + a lookahead that
   * add reorder delay (fine for VOD, wrong for a live preview — this was the
   * "weird latency delay" on h264; the HEVC MFT defaults to 0 B-frames, so it
   * didn't show it). Turn on low-latency mode (disables B-frames) and pin the
   * B-picture count to 0. Best-effort: some encoder MFTs don't expose ICodecAPI
   * or a given property, so ignore failures. Must run before streaming; done
   * here (after the types, before the SPS blob) so the extradata reflects it. */
  {
    ICodecAPI *api = NULL;
    if (SUCCEEDED(IMFTransform_QueryInterface(s->mft, &kIID_ICodecAPI,
                                              (void **)&api)) &&
        api) {
      VARIANT v;
      VariantInit(&v);
      v.vt = VT_BOOL;
      v.boolVal = VARIANT_TRUE;
      ICodecAPI_SetValue(api, &kCODECAPI_AVLowLatencyMode, &v);
      VariantClear(&v);
      v.vt = VT_UI4;
      v.ulVal = 0;
      ICodecAPI_SetValue(api, &kCODECAPI_AVEncMPVDefaultBPictureCount, &v);
      VariantClear(&v);
      ICodecAPI_Release(api);
    }
  }

  /* GOP: left to the encoder default; callers force IDRs via the keyframe flag
   * on send_nv12 (an ICodecAPI GOP knob is a follow-up — its header/lib pull-in
   * isn't worth it for the first cut). */
  (void)gop;

  /* SPS/PPS from the output type's sequence header. */
  {
    IMFMediaType *cur = NULL;
    if (SUCCEEDED(IMFTransform_GetOutputCurrentType(s->mft, 0, &cur)) && cur) {
      UINT32 n = 0;
      IMFMediaType_GetBlobSize(cur, &MF_MT_MPEG_SEQUENCE_HEADER, &n);
      if (n > 0 && n <= sizeof(s->extradata)) {
        if (SUCCEEDED(IMFMediaType_GetBlob(cur, &MF_MT_MPEG_SEQUENCE_HEADER,
                                           s->extradata, n, NULL))) {
          s->extradata_len = (int)n;
        }
      }
      IMFMediaType_Release(cur);
    }
  }

  if (s->is_async) {
    if (FAILED(IMFTransform_QueryInterface(s->mft, &IID_IMFMediaEventGenerator,
                                           (void **)&s->event_gen)) ||
        !s->event_gen) {
      /* Async MFT with no event generator is unusable — there is no legal way
       * to drive it. Fail here rather than deadlock on the first frame. */
      goto fail;
    }
  }

  IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
  IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
  s->started = 1;
  return s;

fail:
  if (s->event_gen) IMFMediaEventGenerator_Release(s->event_gen);
  if (s->dxgi_mgr) IMFDXGIDeviceManager_Release(s->dxgi_mgr);
  if (s->device) ID3D11Device_Release(s->device);
  if (s->mft) IMFTransform_Release(s->mft);
  free(s);
  mf_down();
  return NULL;
}

/* Hardware first, then software. The retry covers the WHOLE attempt, not just
 * activation: a vendor MFT that activates and then rejects our media types
 * (profile, frame rate, resolution) must still leave a working encoder, or a
 * machine with hardware would end up worse off than one without. */
static void *mfenc_create_pub_impl(int codec, int width, int height,
                                   int bitrate_bps, int fps_num, int fps_den,
                                   int gop, void *existing_device) {
  /* Try EVERY hardware candidate before giving up on hardware. A box can list
   * several vendor MFTs (e.g. an AMD entry from a driver whose GPU is absent,
   * plus the NVIDIA one); activation succeeds for all of them, but only the one
   * matching real silicon will accept our media types. Stopping at the first
   * failure is what left this on the software encoder. */
  for (int cand = 0; cand < 8; cand++) {
    void *s = mfenc_create_impl(codec, width, height, bitrate_bps, fps_num,
                                fps_den, gop, 1, cand, existing_device);
    if (s) return s;
  }
  return mfenc_create_impl(codec, width, height, bitrate_bps, fps_num, fps_den,
                           gop, 0, 0, existing_device);
}

static int mfenc_get_extradata_impl(void *session, uint8_t *out, int cap) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return -1;
  if (!out) return s->extradata_len;
  if (cap < s->extradata_len) return -1;
  if (s->extradata_len > 0) memcpy(out, s->extradata, (size_t)s->extradata_len);
  return s->extradata_len;
}

/* Bytes one system-memory NV12 frame occupies for this session.
 *
 * NOT width*height*3/2. 4:2:0 chroma is subsampled 2x2, so:
 *   - a row is an even number of bytes (chroma arrives in U,V PAIRS), hence the
 *     padded stride — the same (w+1)&~1 convention the staging ring uses;
 *   - there are CEIL(h/2) chroma rows, not floor. At 2576x1119 the floored
 *     count is 559 instead of 560 and the frame is 2576 B short, which is
 *     exactly how every CPU frame at an odd height came back as an error.
 * Both sides must compute this the same way; the Dart side mirrors it. */
static int mfenc_nv12_size(int width, int height) {
  int stride = (width + 1) & ~1;
  return stride * height + stride * ((height + 1) / 2);
}

/* Feed one system-memory NV12 frame (size must be at least
 * mfenc_nv12_size(width, height)). */
static int mfenc_send_nv12_impl(void *session, const uint8_t *nv12,
                                int nv12_size, int64_t pts_us,
                                int force_keyframe) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !nv12) return -1;
  s->imp_err[0] = 0;
  int need = mfenc_nv12_size(s->width, s->height);
  if (nv12_size < need) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "NV12 frame is %d B, need %d for %dx%d (stride %d, %d chroma rows)",
             nv12_size, need, s->width, s->height, (s->width + 1) & ~1,
             (s->height + 1) / 2);
    return -1;
  }
  mfenc_restart_stream(s);

  IMFMediaBuffer *buf = NULL;
  HRESULT hb = MFCreateMemoryBuffer((DWORD)need, &buf);
  if (FAILED(hb)) {
    snprintf(s->imp_err, sizeof(s->imp_err), "MFCreateMemoryBuffer=0x%08lX",
             (unsigned long)hb);
    return -1;
  }
  BYTE *dst = NULL;
  HRESULT hl = IMFMediaBuffer_Lock(buf, &dst, NULL, NULL);
  if (FAILED(hl)) {
    snprintf(s->imp_err, sizeof(s->imp_err), "IMFMediaBuffer::Lock=0x%08lX",
             (unsigned long)hl);
    IMFMediaBuffer_Release(buf);
    return -1;
  }
  memcpy(dst, nv12, (size_t)need);
  IMFMediaBuffer_Unlock(buf);
  IMFMediaBuffer_SetCurrentLength(buf, (DWORD)need);

  IMFSample *smp = NULL;
  HRESULT hs = MFCreateSample(&smp);
  if (FAILED(hs)) {
    snprintf(s->imp_err, sizeof(s->imp_err), "MFCreateSample=0x%08lX",
             (unsigned long)hs);
    IMFMediaBuffer_Release(buf);
    return -1;
  }
  IMFSample_AddBuffer(smp, buf);
  IMFMediaBuffer_Release(buf);
  IMFSample_SetSampleTime(smp, (LONGLONG)pts_us * 10);
  IMFSample_SetSampleDuration(smp, s->frame_dur_100ns);
  if (force_keyframe) {
    IMFSample_SetUINT32(smp, &MFSampleExtension_CleanPoint, 1);
  }
  /* An async MFT accepts exactly one input per METransformNeedInput. Calling
   * ProcessInput without one is an error, so wait (bounded) for the credit and
   * report "not accepting" if it never arrives — the caller retries. */
  if (s->is_async) {
    while (s->need_input == 0) {
      if (mfenc_wait_event(s) != 0) break; /* output pending, or timed out */
    }
    if (s->need_input == 0) {
      snprintf(s->imp_err, sizeof(s->imp_err),
               "no METransformNeedInput within the wait budget (back-pressure)");
      IMFSample_Release(smp);
      return 1; /* caller drains via receive(), then retries this frame */
    }
    s->need_input--;
  }

  HRESULT hr = IMFTransform_ProcessInput(s->mft, 0, smp, 0);
  IMFSample_Release(smp);
  if (FAILED(hr) && hr != MF_E_NOTACCEPTING) {
    snprintf(s->imp_err, sizeof(s->imp_err), "ProcessInput(NV12)=0x%08lX",
             (unsigned long)hr);
    return -1;
  }
  if (hr == MF_E_NOTACCEPTING) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "ProcessInput(NV12)=MF_E_NOTACCEPTING (back-pressure)");
    return 1;
  }
  /* The last thing the MFT saw is now a SYSTEM-MEMORY frame, and this session
   * does not retain those. Drop the retained GPU surface so repeatLastFrame
   * declines rather than resurrecting a picture from before the fallback — the
   * Dart contract already says null means "re-encode it yourself". */
  if (s->last_sub) {
    ID3D11Texture2D_Release(s->last_sub);
    s->last_sub = NULL;
  }
  return 0;
}

/* Feed one frame as a D3D11 texture opened from a shared NT handle — the
 * zero-copy path: no readback, no memcpy, the encoder samples the texture.
 *
 * The handle is opened onto OUR device (the one the MFT is bound to). Caller
 * keeps ownership of the handle; miniav closes it in releaseBuffer, so the
 * import here must complete before the caller releases the buffer. Returns
 * 0 accepted, 1 not accepting (drain then retry), -1 error / no D3D path. */
/* Wrap an NV12 texture already living on OUR device as an IMFSample and feed it
 * through the same NeedInput credit contract the CPU path uses.
 * 0 = accepted, 1 = drain and retry, -1 = error. */
static int mfenc_submit_texture(MfVidEnc *s, ID3D11Texture2D *tex,
                                int64_t pts_us, int force_keyframe) {
  mfenc_restart_stream(s);
  IMFMediaBuffer *buf = NULL;
  HRESULT hr = MFCreateDXGISurfaceBuffer(&IID_ID3D11Texture2D, (IUnknown *)tex,
                                         0, FALSE, &buf);
  if (FAILED(hr) || !buf) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "MFCreateDXGISurfaceBuffer=0x%08lX", (unsigned long)hr);
    return -1;
  }

  /* A DXGI surface buffer starts with CURRENT LENGTH 0. An MFT reading it then
   * sees an empty buffer and encodes a blank frame — no error anywhere, real
   * packets out, constant picture. That is exactly the symptom the gradient vs
   * flat-grey differential test caught. IMF2DBuffer::GetContiguousLength is the
   * only way to learn the right size for a GPU surface. */
  IMF2DBuffer *b2 = NULL;
  if (SUCCEEDED(IMFMediaBuffer_QueryInterface(buf, &IID_IMF2DBuffer,
                                              (void **)&b2)) &&
      b2) {
    DWORD len = 0;
    if (SUCCEEDED(IMF2DBuffer_GetContiguousLength(b2, &len)) && len > 0)
      IMFMediaBuffer_SetCurrentLength(buf, len);
    IMF2DBuffer_Release(b2);
  }

  IMFSample *smp = NULL;
  HRESULT hs = MFCreateSample(&smp);
  if (FAILED(hs)) {
    snprintf(s->imp_err, sizeof(s->imp_err), "MFCreateSample=0x%08lX",
             (unsigned long)hs);
    IMFMediaBuffer_Release(buf);
    return -1;
  }
  IMFSample_AddBuffer(smp, buf);
  IMFMediaBuffer_Release(buf);
  IMFSample_SetSampleTime(smp, (LONGLONG)pts_us * 10);
  IMFSample_SetSampleDuration(smp, s->frame_dur_100ns);
  if (force_keyframe) IMFSample_SetUINT32(smp, &MFSampleExtension_CleanPoint, 1);

  if (s->is_async) {
    while (s->need_input == 0) {
      if (mfenc_wait_event(s) != 0) break;
    }
    if (s->need_input == 0) {
      snprintf(s->imp_err, sizeof(s->imp_err),
               "no METransformNeedInput within the wait budget (back-pressure)");
      IMFSample_Release(smp);
      return 1;
    }
    s->need_input--;
  }
  hr = IMFTransform_ProcessInput(s->mft, 0, smp, 0);
  IMFSample_Release(smp);
  if (FAILED(hr) && hr != MF_E_NOTACCEPTING) {
    snprintf(s->imp_err, sizeof(s->imp_err), "ProcessInput(texture)=0x%08lX",
             (unsigned long)hr);
    return -1;
  }
  if (hr == MF_E_NOTACCEPTING) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "ProcessInput(texture)=MF_E_NOTACCEPTING (back-pressure)");
    return 1;
  }
  /* Retain the surface ONLY once the MFT has actually taken it. Recording it
   * up front meant a refused sample still became the repeat source, so an
   * idle-CFR duplicate reproduced a picture the encoder never encoded. */
  if (tex != s->last_sub) {
    if (s->last_sub) ID3D11Texture2D_Release(s->last_sub);
    s->last_sub = tex;
    ID3D11Texture2D_AddRef(s->last_sub);
  }
  return 0;
}

/* Lazily build the VideoProcessor, its staging ring and everything else the
 * per-frame path needs. 0 on success. Only called on the texture path.
 *
 * Every step is guarded on its own output, so a partial build can be resumed by
 * the next call instead of leaking the pieces that did succeed. Readiness is
 * "the processor AND at least two staging slots" — `s->vp` alone would memoise
 * a half-built session as ready and quietly drop every frame thereafter, and
 * one slot is not enough for the reason spelled out at the ring loop below. */
static int mfenc_ensure_vp(MfVidEnc *s) {
  if (s->vp && s->nv12_tex[0] && s->nv12_tex[1]) return 0;
  if (!s->device) return -1;

  if (!s->ctx) ID3D11Device_GetImmediateContext(s->device, &s->ctx);
  if (!s->ctx) return -1;

  if (!s->vdev &&
      (FAILED(ID3D11Device_QueryInterface(s->device, &IID_ID3D11VideoDevice,
                                          (void **)&s->vdev)) ||
       !s->vdev))
    return -1; /* device lacks D3D11_CREATE_DEVICE_VIDEO_SUPPORT */
  if (!s->vctx &&
      (FAILED(ID3D11DeviceContext_QueryInterface(
           s->ctx, &IID_ID3D11VideoContext, (void **)&s->vctx)) ||
       !s->vctx))
    return -1;

  D3D11_VIDEO_PROCESSOR_CONTENT_DESC cd;
  ZeroMemory(&cd, sizeof(cd));
  cd.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
  cd.InputFrameRate.Numerator = 60;
  cd.InputFrameRate.Denominator = 1;
  cd.InputWidth = (UINT)s->width;
  cd.InputHeight = (UINT)s->height;
  cd.OutputFrameRate.Numerator = 60;
  cd.OutputFrameRate.Denominator = 1;
  cd.OutputWidth = (UINT)s->width;
  cd.OutputHeight = (UINT)s->height;
  cd.Usage = D3D11_VIDEO_USAGE_OPTIMAL_SPEED;
  if (!s->vp_enum &&
      (FAILED(ID3D11VideoDevice_CreateVideoProcessorEnumerator(
           s->vdev, &cd, &s->vp_enum)) ||
       !s->vp_enum))
    return -1;
  if (!s->vp && (FAILED(ID3D11VideoDevice_CreateVideoProcessor(
                     s->vdev, s->vp_enum, 0, &s->vp)) ||
                 !s->vp))
    return -1;

  /* The NV12 destination ring. RENDER_TARGET is required for a VP output view.
   * Each slot's output view is built here, once: the destination never changes,
   * so rebuilding the view per frame was pure per-frame driver allocation. */
  /* NV12 subsamples chroma 2x2, so a DXGI NV12 surface MUST have even width
   * and height -- CreateTexture2D returns E_INVALIDARG for anything else, and
   * capture sizes are arbitrary (a window at 2576x1119 has an odd height). Pad
   * up to even; the blt below writes only the real w x h region via the stream
   * rects, and the MFT reads the frame size from its media type, so the spare
   * row/column is simply never looked at. */
  D3D11_TEXTURE2D_DESC td;
  ZeroMemory(&td, sizeof(td));
  td.Width = (UINT)((s->width + 1) & ~1);
  td.Height = (UINT)((s->height + 1) & ~1);
  td.MipLevels = 1;
  td.ArraySize = 1;
  td.Format = DXGI_FORMAT_NV12;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET;

  D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC ovd;
  ZeroMemory(&ovd, sizeof(ovd));
  ovd.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
  ovd.Texture2D.MipSlice = 0;

  /* A short ring still works — it just leaves less slack for frames in flight —
   * so a failure part-way through stops allocating rather than failing the
   * session. Fewer than TWO slots is fatal, though: the most recently submitted
   * surface is retained for repeatLastFrame, so with a single slot that slot
   * permanently carries the extra reference, [mfenc_pick_nv12] never sees it
   * idle, and every frame goes down the 3-strike force-take path — dropping
   * roughly every other frame with no diagnostic anywhere. Failing here is
   * honest: the texture path is unavailable and the caller falls back. */
  int built = 0;
  for (int i = 0; i < MFENC_NV12_RING; i++) {
    if (s->nv12_tex[i]) {
      built++;
      continue;
    }
    HRESULT ht =
        ID3D11Device_CreateTexture2D(s->device, &td, NULL, &s->nv12_tex[i]);
    if (FAILED(ht) || !s->nv12_tex[i]) {
      s->nv12_tex[i] = NULL;
      if (i == 0) {
        UINT sup = 0;
        ID3D11Device_CheckFormatSupport(s->device, DXGI_FORMAT_NV12, &sup);
        snprintf(s->imp_err, sizeof(s->imp_err),
                 "NV12 staging CreateTexture2D=0x%08lX (NV12 support=0x%X) -- "
                 "the encoder device cannot allocate an NV12 render target",
                 (unsigned long)ht, (unsigned)sup);
      }
      break;
    }
    if (FAILED(ID3D11VideoDevice_CreateVideoProcessorOutputView(
            s->vdev, (ID3D11Resource *)s->nv12_tex[i], s->vp_enum, &ovd,
            &s->nv12_ov[i])) ||
        !s->nv12_ov[i]) {
      ID3D11Texture2D_Release(s->nv12_tex[i]);
      s->nv12_tex[i] = NULL;
      s->nv12_ov[i] = NULL;
      break;
    }
    /* Calibrate the idle reference count now that every long-lived holder
     * exists. See the field comment: this is a measurement, not a constant. */
    ID3D11Texture2D_AddRef(s->nv12_tex[i]);
    s->nv12_base_rc[i] = ID3D11Texture2D_Release(s->nv12_tex[i]);
    built++;
  }
  if (built < 2) {
    if (s->imp_err[0] == 0)
      snprintf(s->imp_err, sizeof(s->imp_err),
               "only %d NV12 staging slot(s) could be allocated; the texture "
               "path needs at least 2",
               built);
    return -1;
  }

  /* One reusable fence. Only one blt is ever outstanding — the send path waits
   * for it before returning — so a single query covers the whole ring. */
  {
    D3D11_QUERY_DESC qd;
    qd.Query = D3D11_QUERY_EVENT;
    qd.MiscFlags = 0;
    if (!s->blt_fence)
      ID3D11Device_CreateQuery(s->device, &qd, &s->blt_fence); /* optional */
  }

  /* Full-range RGB in, limited-range BT.709 YCbCr out — what H.264/HEVC
   * encoders expect. Set once; the VP keeps the state. */
  D3D11_VIDEO_PROCESSOR_COLOR_SPACE cs;
  ZeroMemory(&cs, sizeof(cs));
  cs.RGB_Range = 0; /* full 0-255 */
  cs.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_0_255;
  ID3D11VideoContext_VideoProcessorSetStreamColorSpace(s->vctx, s->vp, 0, &cs);
  ZeroMemory(&cs, sizeof(cs));
  cs.Usage = 1;        /* video/encoder output */
  cs.YCbCr_Matrix = 1; /* BT.709 */
  cs.Nominal_Range = D3D11_VIDEO_PROCESSOR_NOMINAL_RANGE_16_235;
  ID3D11VideoContext_VideoProcessorSetOutputColorSpace(s->vctx, s->vp, &cs);

  /* Rects are sticky VP state, so they belong here rather than in the blt.
   * They must be set EXPLICITLY: a VideoProcessor built from a CONTENT_DESC
   * still defaults its source/destination rectangles to EMPTY on some drivers,
   * and an empty rect blits nothing while returning S_OK. */
  {
    RECT r;
    r.left = 0;
    r.top = 0;
    r.right = s->width;
    r.bottom = s->height;
    ID3D11VideoContext_VideoProcessorSetStreamSourceRect(s->vctx, s->vp, 0, TRUE,
                                                         &r);
    ID3D11VideoContext_VideoProcessorSetStreamDestRect(s->vctx, s->vp, 0, TRUE,
                                                       &r);
    ID3D11VideoContext_VideoProcessorSetOutputTargetRect(s->vctx, s->vp, TRUE,
                                                         &r);
  }
  return 0;
}

/* Measurement escapes, read once. Both exist so the cost of a design decision
 * can be measured on the SAME binary rather than argued about: an A/B against
 * an older build measures the older build, not the change.
 *   MINIAV_MFENC_NO_CACHE — reopen and re-view the source texture every frame
 *   MINIAV_MFENC_NO_FENCE — return from the blt without waiting for it */
static int mfenc_no_cache = -1, mfenc_no_fence = -1;
static void mfenc_read_env(void) {
  if (mfenc_no_cache < 0) {
    mfenc_no_cache = getenv("MINIAV_MFENC_NO_CACHE") ? 1 : 0;
    mfenc_no_fence = getenv("MINIAV_MFENC_NO_FENCE") ? 1 : 0;
  }
}

/* Release one import-cache entry, including the reference that pins the
 * producer's texture at its address. */
static void mfenc_drop_import(MfVidEnc *s, int i) {
  if (s->imp[i].km) IDXGIKeyedMutex_Release(s->imp[i].km);
  if (s->imp[i].iv) ID3D11VideoProcessorInputView_Release(s->imp[i].iv);
  if (s->imp[i].tex) ID3D11Texture2D_Release(s->imp[i].tex);
  if (s->imp[i].key) ID3D11Texture2D_Release(s->imp[i].key);
  memset(&s->imp[i], 0, sizeof(s->imp[i]));
}

/* Open the caller's texture on our device and build its VP input view, or
 * return a cached one. Result is an index into `s->imp`, or -1.
 *
 * The cache is keyed on the producer's texture pointer, and the entry holds a
 * REFERENCE to it — see the field comment. A pointer alone is not an identity:
 * a freed texture's address can be handed back for a different texture, and a
 * stale hit silently encodes the previous picture forever. The reference makes
 * that impossible rather than unlikely; the expensive half of an import,
 * OpenSharedResource, is what the cache removes. */
static int mfenc_import_slot(MfVidEnc *s, ID3D11Texture2D *foreign) {
  mfenc_read_env();
  s->imp_err[0] = 0;
  if (!mfenc_no_cache)
    for (int i = 0; i < MFENC_IMPORT_CACHE; i++)
      if (s->imp[i].iv && s->imp[i].key == foreign) return i;

  /* Resolve the caller's texture onto OUR device. Three shapes, in order of
   * cost -- and the order matters for correctness as much as speed, because
   * asking the wrong way returns a plain failure rather than a hint.
   *
   *   0. SAME DEVICE. The producer may have built its texture on the very
   *      device we are encoding with, in which case there is nothing to import
   *      and nothing that can fail.
   *   1. NT HANDLE (IDXGIResource1::CreateSharedHandle + OpenSharedResource1).
   *      This is what a modern D3D12/Dawn-backed producer publishes, and it is
   *      what minigpu's shared output texture documents.
   *   2. LEGACY handle (GetSharedHandle + OpenSharedResource), for producers
   *      created with the old D3D11_RESOURCE_MISC_SHARED flag.
   *
   * Only trying (2) is what made this path fail against a real GPU processor
   * while passing a test whose source texture was deliberately created legacy
   * -- the test agreed with the code instead of with the producer. */
  ID3D11Texture2D *src = NULL;

  {
    ID3D11Device *owner = NULL;
    ID3D11Texture2D_GetDevice(foreign, &owner);
    if (owner) {
      int same = (owner == s->device);
      ID3D11Device_Release(owner);
      if (same) {
        src = foreign;
        ID3D11Texture2D_AddRef(src); /* cache owns a reference either way */
      } else {
        snprintf(s->imp_err, sizeof(s->imp_err),
                    "texture device=%p encoder device=%p (different)",
                    (void *)owner, (void *)s->device);
      }
    }
  }

  if (!src) {
    IDXGIResource1 *res1 = NULL;
    if (SUCCEEDED(ID3D11Texture2D_QueryInterface(foreign, &IID_IDXGIResource1,
                                                 (void **)&res1)) &&
        res1) {
      HANDLE nt = NULL;
      HRESULT hr = IDXGIResource1_CreateSharedHandle(
          res1, NULL, DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE,
          NULL, &nt);
      IDXGIResource1_Release(res1);
      if (FAILED(hr))
        snprintf(s->imp_err + strlen(s->imp_err),
                    sizeof(s->imp_err) - strlen(s->imp_err),
                    "; CreateSharedHandle=0x%08lX", (unsigned long)hr);
      if (SUCCEEDED(hr) && nt) {
        ID3D11Device1 *dev1 = NULL;
        if (SUCCEEDED(ID3D11Device_QueryInterface(s->device, &IID_ID3D11Device1,
                                                  (void **)&dev1)) &&
            dev1) {
          HRESULT ho = ID3D11Device1_OpenSharedResource1(
              dev1, nt, &IID_ID3D11Texture2D, (void **)&src);
          if (FAILED(ho))
            snprintf(s->imp_err + strlen(s->imp_err),
                        sizeof(s->imp_err) - strlen(s->imp_err),
                        "; OpenSharedResource1=0x%08lX", (unsigned long)ho);
          ID3D11Device1_Release(dev1);
        }
        /* CreateSharedHandle mints a NEW handle per call; the opened texture
         * holds its own reference, so ours is closed immediately rather than
         * leaked once per cached import. */
        CloseHandle(nt);
      }
    }
  }

  if (!src) {
    IDXGIResource *res = NULL;
    if (SUCCEEDED(ID3D11Texture2D_QueryInterface(foreign, &IID_IDXGIResource,
                                                 (void **)&res)) &&
        res) {
      HANDLE shared = NULL;
      HRESULT hr = IDXGIResource_GetSharedHandle(res, &shared);
      IDXGIResource_Release(res);
      if (FAILED(hr))
        snprintf(s->imp_err + strlen(s->imp_err),
                    sizeof(s->imp_err) - strlen(s->imp_err),
                    "; GetSharedHandle=0x%08lX", (unsigned long)hr);
      if (SUCCEEDED(hr) && shared) {
        HRESULT ho = ID3D11Device_OpenSharedResource(
            s->device, shared, &IID_ID3D11Texture2D, (void **)&src);
        if (FAILED(ho))
          snprintf(s->imp_err + strlen(s->imp_err),
                      sizeof(s->imp_err) - strlen(s->imp_err),
                      "; OpenSharedResource=0x%08lX", (unsigned long)ho);
      }
    }
  }

  if (!src) return -1;

  D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC ivd;
  ZeroMemory(&ivd, sizeof(ivd));
  ivd.FourCC = 0;
  ivd.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
  ivd.Texture2D.MipSlice = 0;
  ID3D11VideoProcessorInputView *iv = NULL;
  {
    HRESULT hv = ID3D11VideoDevice_CreateVideoProcessorInputView(
        s->vdev, (ID3D11Resource *)src, s->vp_enum, &ivd, &iv);
    if (FAILED(hv) || !iv) {
      D3D11_TEXTURE2D_DESC td;
      ID3D11Texture2D_GetDesc(src, &td);
      snprintf(s->imp_err, sizeof(s->imp_err),
                  "imported OK, but CreateVideoProcessorInputView=0x%08lX "
                  "(fmt=%u %ux%u misc=0x%X bind=0x%X)",
                  (unsigned long)hv, (unsigned)td.Format, (unsigned)td.Width,
                  (unsigned)td.Height, (unsigned)td.MiscFlags,
                  (unsigned)td.BindFlags);
      ID3D11Texture2D_Release(src);
      return -1;
    }
  }

  IDXGIKeyedMutex *km = NULL;
  if (FAILED(ID3D11Texture2D_QueryInterface(src, &IID_IDXGIKeyedMutex,
                                            (void **)&km)))
    km = NULL;

  int i = s->imp_next;
  s->imp_next = (s->imp_next + 1) % MFENC_IMPORT_CACHE;
  mfenc_drop_import(s, i); /* LRU eviction, releasing the pinned source */
  s->imp[i].key = foreign;
  ID3D11Texture2D_AddRef(foreign); /* pin the address for as long as we key on it */
  s->imp[i].tex = src;
  s->imp[i].iv = iv;
  s->imp[i].km = km;
  return i;
}

/* Forget every imported source texture.
 *
 * The cache pins the producer's textures so their addresses cannot be reused,
 * which is what makes a pointer key safe — but it also holds VRAM the producer
 * has finished with. On a resolution change or a texture-ring rebuild the
 * caller knows the old surfaces are dead, and this is how it says so. Returns
 * the number of entries released. */
static int mfenc_invalidate_imports_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return -1;
  int n = 0;
  for (int i = 0; i < MFENC_IMPORT_CACHE; i++) {
    if (s->imp[i].key || s->imp[i].tex) n++;
    mfenc_drop_import(s, i);
  }
  s->imp_next = 0;
  /* The retained repeat source is from before the change too, so a duplicate
   * would reproduce a stale picture. Drop it; repeatLastFrame then returns null
   * and the caller re-encodes, which is the documented contract. */
  if (s->last_sub) {
    ID3D11Texture2D_Release(s->last_sub);
    s->last_sub = NULL;
  }
  return n;
}

/* Choose a staging slot the encoder is no longer reading from.
 *
 * MFCreateDXGISurfaceBuffer keeps a reference on the texture for as long as the
 * MFT holds the sample, so a slot back at its calibrated idle count is one the
 * encoder has finished with. Returns -1 when every slot is still in flight,
 * which the caller turns into "drain and retry" — draining output is exactly
 * what makes the MFT release its input samples, so the condition is
 * self-clearing.
 *
 * The refcount test is a heuristic about someone else's object, so it gets a
 * backstop: after two consecutive refusals we take the next slot anyway. If the
 * calibration were ever wrong, that degrades to the old behaviour (a possible
 * tear) instead of dropping every frame forever. */
static int mfenc_pick_nv12(MfVidEnc *s) {
  for (int n = 0; n < MFENC_NV12_RING; n++) {
    int i = (s->nv12_next + n) % MFENC_NV12_RING;
    if (!s->nv12_tex[i]) continue;
    ID3D11Texture2D_AddRef(s->nv12_tex[i]);
    if (ID3D11Texture2D_Release(s->nv12_tex[i]) != s->nv12_base_rc[i]) continue;
    s->nv12_next = (i + 1) % MFENC_NV12_RING;
    s->nv12_busy_streak = 0;
    return i;
  }
  if (++s->nv12_busy_streak < 3) return -1;
  s->nv12_busy_streak = 0;
  /* Force-take, but never the slot holding the repeat source: overwriting it
   * mid-hold makes repeatLastFrame emit a picture that is neither the last
   * frame nor the current one. Two passes so the repeat source is only taken
   * when it is genuinely the last option. */
  for (int pass = 0; pass < 2; pass++) {
    for (int n = 0; n < MFENC_NV12_RING; n++) {
      int i = (s->nv12_next + n) % MFENC_NV12_RING;
      if (!s->nv12_tex[i]) continue;
      if (pass == 0 && s->nv12_tex[i] == s->last_sub) continue;
      s->nv12_next = (i + 1) % MFENC_NV12_RING;
      return i;
    }
  }
  return -1;
}

/* Encode from a raw ID3D11Texture2D* that lives on ANOTHER device (the GPU
 * processor's / Dawn's), RGBA or BGRA.
 *
 * This is the recorder's scale/effects path. The source is imported here rather
 * than read back: minigpu creates its output textures with
 * D3D11_RESOURCE_MISC_SHARED, so GetSharedHandle + OpenSharedResource brings it
 * onto our device, and a VideoProcessor blt converts it to NV12 in VRAM. The
 * same technique already ships in the FFmpeg shim's d3d11_vp_bgra_to_nv12.
 *
 * 0 = accepted, 1 = drain and retry, -1 = error. */
/* Import a foreign-device RGBA/BGRA texture and VideoProcessor-blt it into the
 * session's NV12 staging texture. 0 on success. Split out of the send path so
 * the diagnostic below measures exactly this code. */
static int mfenc_blt_texture_to_nv12(MfVidEnc *s, ID3D11Texture2D *foreign) {
  int im = mfenc_import_slot(s, foreign);
  if (im < 0) return -1;
  int slot = mfenc_pick_nv12(s);
  if (slot < 0) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "all %d NV12 staging surfaces are still held by the MFT "
             "(back-pressure, drain and retry)",
             MFENC_NV12_RING);
    return -2; /* every staging surface still in flight */
  }

  IDXGIKeyedMutex *km = s->imp[im].km;
  if (km) {
    /* Bounded, never INFINITE. This runs on the encoder's worker thread with
     * the calling isolate blocked behind it, so a producer that never releases
     * would hang the recording rather than drop a frame. */
    HRESULT a = IDXGIKeyedMutex_AcquireSync(km, 0, 8);
    if (a != S_OK) km = NULL; /* includes WAIT_TIMEOUT: skip the lock, not the frame */
  }

  D3D11_VIDEO_PROCESSOR_STREAM st;
  ZeroMemory(&st, sizeof(st));
  st.Enable = TRUE;
  st.OutputIndex = 0;
  st.InputFrameOrField = 0;
  st.pInputSurface = s->imp[im].iv;
  HRESULT hr = ID3D11VideoContext_VideoProcessorBlt(s->vctx, s->vp,
                                                    s->nv12_ov[slot], 0, 1, &st);

  /* Wait for the blt to COMPLETE before returning, not merely to be submitted.
   * The reason is the SOURCE, not the destination: the caller's texture belongs
   * to a shallow ring the GPU processor recycles, and it is free to draw over
   * it as soon as this call returns. Reading a surface while its owner redraws
   * it is a tear.
   *
   * Steady-state cost is one blt's worth of GPU time (a fraction of a
   * millisecond), so spin rather than sleep — a Sleep(1) costs a ~15.6 ms timer
   * quantum, the trap that once made this encoder 3 s/frame. Past a short spin
   * the GPU is genuinely backed up and burning a core no longer helps anyone,
   * so yield to whatever else is ready; SwitchToThread returns immediately when
   * nothing is, which degrades cleanly back to a spin. */
  if (SUCCEEDED(hr) && s->blt_fence && !mfenc_no_fence) {
    ID3D11DeviceContext_End(s->ctx, (ID3D11Asynchronous *)s->blt_fence);
    ID3D11DeviceContext_Flush(s->ctx);
    LARGE_INTEGER freq, t0, now;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t0);
    for (;;) {
      if (ID3D11DeviceContext_GetData(s->ctx, (ID3D11Asynchronous *)s->blt_fence,
                                      NULL, 0, 0) != S_FALSE)
        break;
      QueryPerformanceCounter(&now);
      double el = (double)(now.QuadPart - t0.QuadPart) / (double)freq.QuadPart;
      if (el > 0.033) break; /* two frames at 60 Hz; something else is wrong */
      if (el > 0.001)
        SwitchToThread();
      else
        YieldProcessor();
    }
  } else if (SUCCEEDED(hr)) {
    ID3D11DeviceContext_Flush(s->ctx);
  }

  if (km) IDXGIKeyedMutex_ReleaseSync(km, 0);
  if (FAILED(hr)) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "imported OK, but VideoProcessorBlt=0x%08lX", (unsigned long)hr);
    return -1;
  }
  s->nv12_last = slot;
  return slot;
}

/* Encode from a raw ID3D11Texture2D* on ANOTHER device (the GPU processor's /
 * Dawn's), RGBA or BGRA. Imported + converted in VRAM — no readback.
 * 0 = accepted, 1 = drain and retry, -1 = error. */
static int mfenc_send_d3d11_texture_impl(void *session, void *texture_ptr,
                                         int64_t pts_us, int force_keyframe) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !texture_ptr || !s->device) return -1;
  if (mfenc_ensure_vp(s) != 0) {
    /* Distinguish "the VideoProcessor could not be built" from "the texture
     * could not be imported" -- otherwise an empty reason is ambiguous and the
     * reader assumes the import, which is the wrong half to investigate.
     * Whatever ensure_vp itself recorded is the more specific half, so it goes
     * first rather than being overwritten. */
    char why[128];
    snprintf(why, sizeof(why), "%s", s->imp_err);
    snprintf(s->imp_err, sizeof(s->imp_err),
             "mfenc_ensure_vp failed: %s (device=%p vdev=%p vp=%p nv12[0]=%p)",
             why[0] ? why : "no reason recorded", (void *)s->device,
             (void *)s->vdev, (void *)s->vp, (void *)s->nv12_tex[0]);
    return -1;
  }
  int slot = mfenc_blt_texture_to_nv12(s, (ID3D11Texture2D *)texture_ptr);
  /* -2 is "all staging surfaces are still in the encoder": the same condition
   * ProcessInput reports as MF_E_NOTACCEPTING, and it wants the same cure. */
  if (slot == -2) return 1;
  if (slot < 0) return -1;
  return mfenc_submit_texture(s, s->nv12_tex[slot], pts_us, force_keyframe);
}

/* Re-send the most recently submitted surface under a new timestamp.
 * 0 = accepted, 1 = drain and retry, -1 = nothing to repeat. */
static int mfenc_repeat_last_impl(void *session, int64_t pts_us,
                                  int force_keyframe) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !s->last_sub) return -1;
  return mfenc_submit_texture(s, s->last_sub, pts_us, force_keyframe);
}

static int mfenc_send_d3d11_impl(void *session, void *shared_handle,
                                 int64_t pts_us, int force_keyframe) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !shared_handle || !s->device) return -1;

  s->imp_err[0] = 0;
  ID3D11Texture2D *tex = NULL;
  ID3D11Device1 *dev1 = NULL;
  HRESULT hq = ID3D11Device_QueryInterface(s->device, &IID_ID3D11Device1,
                                           (void **)&dev1);
  if (FAILED(hq) || !dev1) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "encoder device QueryInterface(ID3D11Device1)=0x%08lX",
             (unsigned long)hq);
    return -1;
  }
  HRESULT hr = ID3D11Device1_OpenSharedResource1(dev1, (HANDLE)shared_handle,
                                                 &IID_ID3D11Texture2D,
                                                 (void **)&tex);
  ID3D11Device1_Release(dev1);
  if (FAILED(hr) || !tex) {
    snprintf(s->imp_err, sizeof(s->imp_err),
             "OpenSharedResource1(capture handle)=0x%08lX -- most likely the "
             "handle is on a different adapter than the encoder device",
             (unsigned long)hr);
    return -1;
  }

  int r = mfenc_submit_texture(s, tex, pts_us, force_keyframe);
  ID3D11Texture2D_Release(tex);
  return r;
}

/* The ID3D11Device the MFT is bound to, for diagnostics. Whether this equals
 * the producer's device decides whether frames need importing at all, and that
 * question was previously unanswerable from a log. */
static void *mfenc_get_device_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  return (s) ? (void *)s->device : NULL;
}

/* 1 when the session has a D3D11 device bound (zero-copy input available). */
static int mfenc_has_d3d11_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  return (s && s->device && s->dxgi_mgr) ? 1 : 0;
}

/* Pull one encoded frame. 1 = frame, 0 = need more input, 2 = stream change. */
static int mfenc_receive_impl(void *session, MiniAVMfEncFrame *out) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !out) return -1;
  memset(out, 0, sizeof(*out));

  /* Injected fault: an MFT that swallows everything it is given. "Need more
   * input" is exactly what a real one answers while it holds frames, so the
   * caller cannot tell this apart from a slow encoder — which is the point. */
  if (s->fault == MFENC_FAULT_NO_OUTPUT) return 0;

  /* Async: ProcessOutput is only legal after METransformHaveOutput. Without
   * this gate the call returns E_UNEXPECTED on every hardware MFT. */
  if (s->is_async) {
    mfenc_pump(s);
    if (s->have_output == 0) return 0;
    s->have_output--;
  }

  MFT_OUTPUT_STREAM_INFO si;
  memset(&si, 0, sizeof(si));
  IMFTransform_GetOutputStreamInfo(s->mft, 0, &si);
  int providesOwn = (si.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES |
                                   MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;

  MFT_OUTPUT_DATA_BUFFER odb;
  memset(&odb, 0, sizeof(odb));
  IMFSample *pre = NULL;
  IMFMediaBuffer *preBuf = NULL;
  if (!providesOwn) {
    DWORD cb = si.cbSize > 0 ? si.cbSize
                             : (DWORD)(s->width * s->height * 3 / 2 + 4096);
    if (FAILED(MFCreateSample(&pre)) ||
        FAILED(MFCreateMemoryBuffer(cb, &preBuf))) {
      if (pre) IMFSample_Release(pre);
      if (preBuf) IMFMediaBuffer_Release(preBuf);
      return -1;
    }
    IMFSample_AddBuffer(pre, preBuf);
    odb.pSample = pre;
  }
  DWORD status = 0;
  HRESULT hr = IMFTransform_ProcessOutput(s->mft, 0, 1, &odb, &status);
  if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
    if (preBuf) IMFMediaBuffer_Release(preBuf);
    if (pre) IMFSample_Release(pre);
    if (odb.pEvents) IMFCollection_Release(odb.pEvents);
    return 0;
  }
  if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
    if (preBuf) IMFMediaBuffer_Release(preBuf);
    if (pre) IMFSample_Release(pre);
    if (odb.pEvents) IMFCollection_Release(odb.pEvents);
    /* The MFT wants a new output type and will keep answering STREAM_CHANGE
     * until it gets one. Returning 2 without renegotiating just handed the
     * caller a loop that never terminates and an MFT that never produces
     * another frame. Take the first available output type it will accept. */
    if (s->stream_change_retries >= 4) {
      snprintf(s->imp_err, sizeof(s->imp_err),
               "MFT keeps signalling MF_E_TRANSFORM_STREAM_CHANGE after %d "
               "output-type renegotiations",
               s->stream_change_retries);
      return 0; /* give up rather than spin; the caller stops asking */
    }
    s->stream_change_retries++;
    int ok = 0;
    for (DWORD ti = 0;; ti++) {
      IMFMediaType *cand = NULL;
      if (FAILED(IMFTransform_GetOutputAvailableType(s->mft, 0, ti, &cand)) ||
          !cand)
        break;
      if (SUCCEEDED(IMFTransform_SetOutputType(s->mft, 0, cand, 0))) {
        /* The parameter sets travel with the output type, so refresh them —
         * a muxer handed the pre-change SPS/PPS writes an undecodable track. */
        UINT32 n = 0;
        IMFMediaType_GetBlobSize(cand, &MF_MT_MPEG_SEQUENCE_HEADER, &n);
        if (n > 0 && n <= sizeof(s->extradata) &&
            SUCCEEDED(IMFMediaType_GetBlob(cand, &MF_MT_MPEG_SEQUENCE_HEADER,
                                           s->extradata, n, NULL)))
          s->extradata_len = (int)n;
        ok = 1;
      }
      IMFMediaType_Release(cand);
      if (ok) break;
    }
    if (!ok)
      snprintf(s->imp_err, sizeof(s->imp_err),
               "MF_E_TRANSFORM_STREAM_CHANGE and the MFT accepted none of its "
               "own available output types");
    return 2;
  }
  if (FAILED(hr) || !odb.pSample) {
    if (preBuf) IMFMediaBuffer_Release(preBuf);
    if (odb.pSample) IMFSample_Release(odb.pSample);
    if (odb.pEvents) IMFCollection_Release(odb.pEvents);
    return 0;
  }

  IMFMediaBuffer *mb = NULL;
  if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(odb.pSample, &mb)) && mb) {
    BYTE *p = NULL;
    DWORD len = 0;
    if (SUCCEEDED(IMFMediaBuffer_Lock(mb, &p, NULL, &len)) && len > 0) {
      out->data = (uint8_t *)malloc(len);
      if (out->data) {
        memcpy(out->data, p, len);
        out->size = (int)len;
        /* Output is flowing again: the renegotiation budget is per stall. */
        s->stream_change_retries = 0;
        UINT32 clean = 0;
        IMFSample_GetUINT32(odb.pSample, &MFSampleExtension_CleanPoint, &clean);
        out->is_keyframe = clean ? 1 : 0;
        LONGLONG t = 0;
        if (SUCCEEDED(IMFSample_GetSampleTime(odb.pSample, &t)))
          out->pts_us = (int64_t)(t / 10);
      }
      IMFMediaBuffer_Unlock(mb);
    }
    IMFMediaBuffer_Release(mb);
  }
  if (preBuf) IMFMediaBuffer_Release(preBuf);
  IMFSample_Release(odb.pSample);
  if (odb.pEvents) IMFCollection_Release(odb.pEvents);
  return out->data ? 1 : 0;
}

static int mfenc_drain_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return -1;
  /* Already drained, or a drain is still outstanding: COMMAND_DRAIN is not
   * re-issuable, and a caller calling flush() twice is normal. The state
   * machine below carries on from wherever it is. */
  if (s->stream_ended || s->draining) return 0;
  s->draining = 1;
  s->drain_done = 0;
  IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_COMMAND_DRAIN, 0);
  /* Async MFTs keep raising METransformHaveOutput after the drain command and
   * finish with METransformDrainComplete; pump so those land in have_output and
   * the caller's receive() loop can flush them. Bounded so a wedged MFT cannot
   * hang the caller — and it is only a HEAD START: the caller must keep polling
   * mfenc_drain_state_impl until the drain actually completes, or it loses
   * whatever the MFT still had in flight. */
  if (s->is_async) {
    /* ONE bounded wait, not a loop. mfenc_wait_drain really does wait (up to
     * ~8 ms) instead of returning instantly on leftover input credit, so the
     * head start no longer needs a deadline loop around it — and must not have
     * one: this runs on the single shared MTA worker with mfenc_w_gate held,
     * where a 1 s cap is 1 s of every other session (and destroy) blocked. The
     * caller polls mfenc_drain_state_impl for the rest. */
    mfenc_wait_drain(s);
  } else {
    /* A sync MFT finishes its drain inside ProcessOutput — the caller's
     * receive() loop running dry IS the completion signal. Mark the stream
     * ended so the next submit restarts it. */
    s->draining = 0;
    s->drain_done = 1;
    s->stream_ended = 1;
  }
  return 0;
}

/* Poll an outstanding drain.
 *  1 = the drain is finished AND every output it raised has been taken
 *  0 = more output is still coming — keep calling receive()
 *
 * flush() cannot stop when receive() returns 0: for an ASYNC MFT that only
 * means "nothing ready at this instant", while a hardware encoder routinely
 * holds two to four frames in flight. Stopping there drops the end of the
 * recording with success reported everywhere, which is the worst shape a bug
 * can take. Each call waits a bounded ~8 ms (spin/yield, never Sleep, never a
 * blocking GetEvent) so a wedged MFT costs latency rather than a hang. */
static int mfenc_drain_state_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return -1;
  /* Injected faults. NEVER_DRAIN reports "still coming" forever so the caller's
   * bounded poll loop has to exit through its timeout; NO_OUTPUT reports the
   * drain COMPLETE, which is what separates "the MFT is wedged" from "the MFT
   * finished and produced nothing" — two different bugs with two different
   * messages, and a fault that got this wrong would test the wrong one. */
  if (s->fault == MFENC_FAULT_NEVER_DRAIN) {
    mfenc_fault_pause(); /* the real call costs ~8 ms; do not spin hot */
    return 0;
  }
  if (s->fault == MFENC_FAULT_NO_OUTPUT) return 1;
  if (!s->is_async) return 1;
  if (!s->draining) return 1; /* nothing outstanding */
  if (s->drain_done)
    mfenc_pump(s);
  else
    mfenc_wait_drain(s); /* NOT wait_event — see mfenc_wait_drain */
  return (s->drain_done && s->have_output == 0) ? 1 : 0;
}

/* Make THIS session misbehave, so the caller's "the encoder lied" error paths
 * can be reached without one. Returns 0, or -1 for an unknown mode.
 *
 * The two faults exist because the two failures they simulate used to be
 * silent: a drain that never completes returned a TRUNCATED tail as a complete
 * stream, and an MFT that accepted every frame and emitted none returned an
 * empty list that is indistinguishable from an ordinary empty flush. Both are
 * unreachable on working hardware, so the alternative to injecting them is not
 * testing them. */
static int mfenc_set_fault_impl(void *session, int mode) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return -1;
  if (mode != MFENC_FAULT_NONE && mode != MFENC_FAULT_NEVER_DRAIN &&
      mode != MFENC_FAULT_NO_OUTPUT)
    return -1;
  s->fault = mode;
  return 0;
}

/* 1 when the session is running a hardware MFT. "It produced a bitstream" is
 * not evidence of hardware — this is. */
static int mfenc_is_hardware_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  return s ? s->is_hardware : 0;
}

/* MFT friendly name (e.g. "NVIDIA H.264 Encoder MFT"). Returns bytes written. */
static int mfenc_get_mft_name_impl(void *session, char *out, int cap) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !out || cap <= 0) return 0;
  int n = (int)strlen(s->mft_name);
  if (n >= cap) n = cap - 1;
  memcpy(out, s->mft_name, (size_t)n);
  out[n] = 0;
  return n;
}

static void mfenc_destroy_impl(void *session) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s) return;
  /* Release the generator before the MFT: it is obtained from the MFT and
   * holds a reference back to it. */
  if (s->event_gen) IMFMediaEventGenerator_Release(s->event_gen);
  /* VideoProcessor chain before the device that produced it. Views first: they
   * hold references to the resources they were built on. */
  for (int i = 0; i < MFENC_IMPORT_CACHE; i++) mfenc_drop_import(s, i);
  if (s->last_sub) ID3D11Texture2D_Release(s->last_sub);
  if (s->blt_fence) ID3D11Query_Release(s->blt_fence);
  for (int i = 0; i < MFENC_NV12_RING; i++) {
    if (s->nv12_ov[i]) ID3D11VideoProcessorOutputView_Release(s->nv12_ov[i]);
    if (s->nv12_tex[i]) ID3D11Texture2D_Release(s->nv12_tex[i]);
  }
  if (s->vp) ID3D11VideoProcessor_Release(s->vp);
  if (s->vp_enum) ID3D11VideoProcessorEnumerator_Release(s->vp_enum);
  if (s->vctx) ID3D11VideoContext_Release(s->vctx);
  if (s->vdev) ID3D11VideoDevice_Release(s->vdev);
  if (s->ctx) ID3D11DeviceContext_Release(s->ctx);
  if (s->dxgi_mgr) IMFDXGIDeviceManager_Release(s->dxgi_mgr);
  if (s->device) ID3D11Device_Release(s->device);
  if (s->mft) {
    IMFTransform_ProcessMessage(s->mft, MFT_MESSAGE_NOTIFY_END_STREAMING, 0);
    IMFTransform_Release(s->mft);
  }
  free(s);
  mf_down();
}

/* ===================== public API — all marshalled to the MTA worker =====
 *
 * Each entry packs its arguments into a struct, runs the *_impl body on the
 * worker, and returns its result. `mfenc_free` is deliberately NOT marshalled:
 * it is a plain free() of a buffer we malloc'd and touches no MF/COM state.
 */

typedef struct { int codec; } ArgCodec;
static int job_has_mft(void *vp) {
  ArgCodec *a = (ArgCodec *)vp;
  return mfenc_has_mft_impl(a->codec);
}
MFENC_API int miniav_shim_mfenc_has_mft(int codec) {
  ArgCodec a = {codec};
  return mfenc_on_worker(job_has_mft, &a, 0);
}

typedef struct { int codec; char *out; int cap; } ArgListHw;
static int job_list_hw(void *vp) {
  ArgListHw *a = (ArgListHw *)vp;
  return mfenc_list_hw_impl(a->codec, a->out, a->cap);
}
MFENC_API int miniav_shim_mfenc_list_hw(int codec, char *out, int cap) {
  ArgListHw a = {codec, out, cap};
  return mfenc_on_worker(job_list_hw, &a, -1);
}

/* create returns a pointer, so the result travels in the arg struct. */
typedef struct {
  int codec, width, height, bitrate_bps, fps_num, fps_den, gop;
  void *existing_device;
  void *result;
} ArgCreate;
static int job_create(void *vp) {
  ArgCreate *a = (ArgCreate *)vp;
  a->result = mfenc_create_pub_impl(a->codec, a->width, a->height,
                                    a->bitrate_bps, a->fps_num, a->fps_den,
                                    a->gop, a->existing_device);
  return 0;
}
MFENC_API void *miniav_shim_mfenc_create(int codec, int width, int height,
                                         int bitrate_bps, int fps_num,
                                         int fps_den, int gop,
                                         void *existing_device) {
  ArgCreate a = {codec,   width, height,          bitrate_bps, fps_num,
                 fps_den, gop,   existing_device, NULL};
  if (mfenc_on_worker(job_create, &a, -1) != 0) return NULL;
  return a.result;
}

typedef struct { void *s; uint8_t *out; int cap; } ArgExtra;
static int job_extradata(void *vp) {
  ArgExtra *a = (ArgExtra *)vp;
  return mfenc_get_extradata_impl(a->s, a->out, a->cap);
}
MFENC_API int miniav_shim_mfenc_get_extradata(void *session, uint8_t *out,
                                              int cap) {
  ArgExtra a = {session, out, cap};
  return mfenc_on_worker(job_extradata, &a, -1);
}

typedef struct {
  void *s; const uint8_t *nv12; int size; int64_t pts; int force;
} ArgSendNv12;
static int job_send_nv12(void *vp) {
  ArgSendNv12 *a = (ArgSendNv12 *)vp;
  return mfenc_send_nv12_impl(a->s, a->nv12, a->size, a->pts, a->force);
}
MFENC_API int miniav_shim_mfenc_send_nv12(void *session, const uint8_t *nv12,
                                          int nv12_size, int64_t pts_us,
                                          int force_keyframe) {
  ArgSendNv12 a = {session, nv12, nv12_size, pts_us, force_keyframe};
  return mfenc_on_worker(job_send_nv12, &a, -1);
}

typedef struct { void *s; void *handle; int64_t pts; int force; } ArgSendTex;
static int job_send_d3d11(void *vp) {
  ArgSendTex *a = (ArgSendTex *)vp;
  return mfenc_send_d3d11_impl(a->s, a->handle, a->pts, a->force);
}
MFENC_API int miniav_shim_mfenc_send_d3d11(void *session, void *shared_handle,
                                           int64_t pts_us, int force_key) {
  ArgSendTex a = {session, shared_handle, pts_us, force_key};
  return mfenc_on_worker(job_send_d3d11, &a, -1);
}

static int job_send_d3d11_texture(void *vp) {
  ArgSendTex *a = (ArgSendTex *)vp;
  return mfenc_send_d3d11_texture_impl(a->s, a->handle, a->pts, a->force);
}
typedef struct {
  void *s;
  int64_t pts;
  int force;
} MfencRepeatArgs;
static int job_repeat_last(void *vp) {
  MfencRepeatArgs *a = (MfencRepeatArgs *)vp;
  return mfenc_repeat_last_impl(a->s, a->pts, a->force);
}
/* Last import failure reason. Not marshalled: it only reads memory the worker
 * has already finished writing, ordered by the job's own completion. */
MFENC_API int miniav_shim_mfenc_last_import_error(void *session, char *out,
                                                  int cap) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !out || cap <= 0) return 0;
  int n = (int)strlen(s->imp_err);
  if (n > cap) n = cap;
  memcpy(out, s->imp_err, (size_t)n);
  return n;
}

typedef struct { void *s; void *result; } ArgGetDev;
static int job_get_device(void *vp) {
  ArgGetDev *a = (ArgGetDev *)vp;
  a->result = mfenc_get_device_impl(a->s);
  return 0;
}
MFENC_API void *miniav_shim_mfenc_get_device(void *session) {
  ArgGetDev a = {session, NULL};
  if (mfenc_on_worker(job_get_device, &a, -1) != 0) return NULL;
  return a.result;
}

MFENC_API int miniav_shim_mfenc_repeat_last(void *session, int64_t pts_us,
                                            int force_keyframe) {
  MfencRepeatArgs a = {session, pts_us, force_keyframe};
  return mfenc_on_worker(job_repeat_last, &a, -1);
}

MFENC_API int miniav_shim_mfenc_send_d3d11_texture(void *session,
                                                   void *texture_ptr,
                                                   int64_t pts_us,
                                                   int force_key) {
  ArgSendTex a = {session, texture_ptr, pts_us, force_key};
  return mfenc_on_worker(job_send_d3d11_texture, &a, -1);
}

typedef struct { void *s; } ArgSession;
static int job_has_d3d11(void *vp) {
  return mfenc_has_d3d11_impl(((ArgSession *)vp)->s);
}
MFENC_API int miniav_shim_mfenc_has_d3d11(void *session) {
  ArgSession a = {session};
  return mfenc_on_worker(job_has_d3d11, &a, 0);
}

typedef struct { void *s; MiniAVMfEncFrame *out; } ArgReceive;
static int job_receive(void *vp) {
  ArgReceive *a = (ArgReceive *)vp;
  return mfenc_receive_impl(a->s, a->out);
}
MFENC_API int miniav_shim_mfenc_receive(void *session, MiniAVMfEncFrame *out) {
  ArgReceive a = {session, out};
  return mfenc_on_worker(job_receive, &a, -1);
}

static int job_drain(void *vp) {
  return mfenc_drain_impl(((ArgSession *)vp)->s);
}
MFENC_API int miniav_shim_mfenc_drain(void *session) {
  ArgSession a = {session};
  return mfenc_on_worker(job_drain, &a, -1);
}

static int job_drain_state(void *vp) {
  return mfenc_drain_state_impl(((ArgSession *)vp)->s);
}
/* 1 = drain finished and every output taken, 0 = keep calling receive(). */
MFENC_API int miniav_shim_mfenc_drain_state(void *session) {
  ArgSession a = {session};
  return mfenc_on_worker(job_drain_state, &a, -1);
}

typedef struct { void *s; int mode; } ArgFault;
static int job_set_fault(void *vp) {
  ArgFault *a = (ArgFault *)vp;
  return mfenc_set_fault_impl(a->s, a->mode);
}
/* TEST-ONLY. 0 = none, 1 = never complete the drain, 2 = accept input and
 * produce nothing (with the drain reporting complete). Scoped to ONE session:
 * every test file shares this process, so a global switch would be a fault
 * injected into whatever else happened to be encoding at the time. Marshalled
 * like every other session entry point so the flag is ordered against the jobs
 * already queued on the worker rather than raced against them. */
MFENC_API int miniav_shim_mfenc_set_fault(void *session, int mode) {
  ArgFault a = {session, mode};
  return mfenc_on_worker(job_set_fault, &a, -1);
}

static int job_invalidate_imports(void *vp) {
  return mfenc_invalidate_imports_impl(((ArgSession *)vp)->s);
}
/* Drop every cached producer texture (and the retained repeat source). Call on
 * a resolution change or when the producer rebuilds its texture ring: the cache
 * pins those surfaces, so this is both the VRAM release and the guarantee that
 * a recycled address can never resolve to the previous picture. Returns the
 * number of entries released. */
MFENC_API int miniav_shim_mfenc_invalidate_imports(void *session) {
  ArgSession a = {session};
  return mfenc_on_worker(job_invalidate_imports, &a, -1);
}

static int job_is_hardware(void *vp) {
  return mfenc_is_hardware_impl(((ArgSession *)vp)->s);
}
MFENC_API int miniav_shim_mfenc_is_hardware(void *session) {
  ArgSession a = {session};
  return mfenc_on_worker(job_is_hardware, &a, 0);
}

typedef struct { void *s; char *out; int cap; } ArgName;
static int job_mft_name(void *vp) {
  ArgName *a = (ArgName *)vp;
  return mfenc_get_mft_name_impl(a->s, a->out, a->cap);
}
MFENC_API int miniav_shim_mfenc_get_mft_name(void *session, char *out,
                                             int cap) {
  ArgName a = {session, out, cap};
  return mfenc_on_worker(job_mft_name, &a, 0);
}

static int job_destroy(void *vp) {
  mfenc_destroy_impl(((ArgSession *)vp)->s);
  return 0;
}
MFENC_API void miniav_shim_mfenc_destroy(void *session) {
  ArgSession a = {session};
  mfenc_on_worker(job_destroy, &a, 0);
}

MFENC_API void miniav_shim_mfenc_free(void *p) { free(p); }

/* ---- test-only: a shared BGRA texture on its OWN device ------------------
 *
 * Exists so `mfenc_send_d3d11_texture` can be exercised for real: it needs a
 * source that lives on a DIFFERENT device and carries
 * D3D11_RESOURCE_MISC_SHARED, which is exactly the shape minigpu's GPU
 * processor output has. Without this the cross-device import + VideoProcessor
 * conversion could only be verified by running the whole recorder.
 *
 * Returns an ID3D11Texture2D* (device kept alive by the texture's reference).
 * Free with miniav_shim_mfenc_test_texture_release. */
/* `nt`: 0 = legacy D3D11_RESOURCE_MISC_SHARED (GetSharedHandle), 1 = NT-handle
 * sharing (IDXGIResource1::CreateSharedHandle), which D3D11 only permits
 * together with a keyed mutex.
 *
 * Both exist because the encoder must accept both, and a test that only ever
 * builds the legacy shape agrees with the importer instead of with real
 * producers -- which is exactly how the NT-handle path shipped broken while
 * this test passed. */
MFENC_API void *miniav_shim_mfenc_test_shared_fmt(int width, int height,
                                                  int pattern, int nt, int fmt);

MFENC_API void *miniav_shim_mfenc_test_shared_bgra_ex(int width, int height,
                                                      int pattern, int nt) {
  return miniav_shim_mfenc_test_shared_fmt(width, height, pattern, nt, 0);
}

/* fmt: 0 = B8G8R8A8_UNORM, 1 = R8G8B8A8_UNORM. The recorder's GPU processor
 * hands over RGBA; a VideoProcessor input view does not necessarily accept it,
 * and testing only BGRA cannot tell you that. */
MFENC_API void *miniav_shim_mfenc_test_shared_fmt(int width, int height,
                                                  int pattern, int nt,
                                                  int fmt) {
  ID3D11Device *dev = NULL;
  ID3D11DeviceContext *ctx = NULL;
  D3D_FEATURE_LEVEL fl;
  if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
                               D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0,
                               D3D11_SDK_VERSION, &dev, &fl, &ctx)) ||
      !dev)
    return NULL;

  D3D11_TEXTURE2D_DESC td;
  ZeroMemory(&td, sizeof(td));
  td.Width = (UINT)width;
  td.Height = (UINT)height;
  td.MipLevels = 1;
  td.ArraySize = 1;
  td.Format = fmt ? DXGI_FORMAT_R8G8B8A8_UNORM
                  : DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  td.MiscFlags = nt ? (D3D11_RESOURCE_MISC_SHARED_NTHANDLE |
                       D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX)
                    : D3D11_RESOURCE_MISC_SHARED;

  /* Fill with a non-uniform pattern so the encoder has real work and a broken
   * colour conversion is at least visible in the output size. */
  UINT32 *pix = (UINT32 *)malloc((size_t)width * height * 4);
  if (!pix) {
    if (ctx) ID3D11DeviceContext_Release(ctx);
    ID3D11Device_Release(dev);
    return NULL;
  }
  for (int y = 0; y < height; y++)
    for (int x = 0; x < width; x++)
      pix[y * width + x] =
          pattern ? (0xFF000000u | ((UINT32)(x & 0xFF) << 16) |
                     ((UINT32)(y & 0xFF) << 8) | (UINT32)((x + y) & 0xFF))
                  : 0xFF808080u; /* flat grey — encodes to almost nothing */
  D3D11_SUBRESOURCE_DATA srd;
  ZeroMemory(&srd, sizeof(srd));
  srd.pSysMem = pix;
  srd.SysMemPitch = (UINT)width * 4;

  ID3D11Texture2D *tex = NULL;
  HRESULT hr = ID3D11Device_CreateTexture2D(dev, &td, &srd, &tex);
  free(pix);
  /* FLUSH before the importing device opens this. A shared resource's contents
   * are only guaranteed visible to another device after the producing context
   * has been flushed — without it the consumer legitimately sees an empty
   * surface, which is indistinguishable from "the blt did not run". */
  if (ctx) {
    ID3D11DeviceContext_Flush(ctx);
    ID3D11DeviceContext_Release(ctx);
  }
  ID3D11Device_Release(dev); /* texture holds its own ref to the device */
  if (FAILED(hr)) return NULL;
  return tex;
}

MFENC_API void *miniav_shim_mfenc_test_shared_bgra(int width, int height,
                                                   int pattern) {
  return miniav_shim_mfenc_test_shared_bgra_ex(width, height, pattern, 0);
}

/* A D3D11 device created WITHOUT video support -- the shape of a rendering
 * device such as Dawn's, used to prove the encoder declines one it cannot
 * convert on. */
MFENC_API void *miniav_shim_mfenc_test_plain_device(void) {
  ID3D11Device *dev = NULL;
  if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
                               D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0,
                               D3D11_SDK_VERSION, &dev, NULL, NULL)))
    return NULL;
  return dev;
}

MFENC_API void miniav_shim_mfenc_test_device_release(void *dev) {
  if (dev) ID3D11Device_Release((ID3D11Device *)dev);
}

MFENC_API void miniav_shim_mfenc_test_texture_release(void *tex) {
  if (tex) ID3D11Texture2D_Release((ID3D11Texture2D *)tex);
}

/* ---- diagnostic: did the VideoProcessor blt actually write? --------------
 *
 * Runs the SAME import + blt as mfenc_send_d3d11_texture_impl, then reads the
 * NV12 staging texture back to the CPU and returns the sum of its luma bytes.
 * This isolates the two suspects: if the sum varies with the source picture the
 * blt works and the fault is downstream in mfenc_submit_texture / the MFT; if
 * it does not, the blt itself is the problem.
 *
 * Test-only — it stalls the GPU on a Map, which is exactly what the real path
 * exists to avoid. Returns -1 on failure. */
static int64_t mfenc_test_blt_luma_sum_impl(void *session, void *texture_ptr) {
  MfVidEnc *s = (MfVidEnc *)session;
  if (!s || !texture_ptr || !s->device) return -1;
  if (mfenc_ensure_vp(s) != 0) return -1;

  /* Reuse the production path so we measure the real blt, then read back. */
  int slot = mfenc_blt_texture_to_nv12(s, (ID3D11Texture2D *)texture_ptr);
  if (slot < 0) return -1;
  ID3D11Texture2D *nv12 = s->nv12_tex[slot];

  D3D11_TEXTURE2D_DESC td;
  ID3D11Texture2D_GetDesc(nv12, &td);
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  td.MiscFlags = 0;
  ID3D11Texture2D *stage = NULL;
  if (FAILED(ID3D11Device_CreateTexture2D(s->device, &td, NULL, &stage)) ||
      !stage)
    return -1;

  ID3D11DeviceContext_CopyResource(s->ctx, (ID3D11Resource *)stage,
                                   (ID3D11Resource *)nv12);
  D3D11_MAPPED_SUBRESOURCE map;
  int64_t sum = -1;
  if (SUCCEEDED(ID3D11DeviceContext_Map(s->ctx, (ID3D11Resource *)stage, 0,
                                        D3D11_MAP_READ, 0, &map))) {
    sum = 0;
    const uint8_t *p = (const uint8_t *)map.pData;
    for (int y = 0; y < s->height; y++) {
      const uint8_t *row = p + (size_t)y * map.RowPitch;
      for (int x = 0; x < s->width; x++) sum += row[x]; /* luma plane only */
    }
    ID3D11DeviceContext_Unmap(s->ctx, (ID3D11Resource *)stage, 0);
  }
  ID3D11Texture2D_Release(stage);
  return sum;
}

/* Marshalled like every other session entry point: it touches the MFT session's
 * D3D11 objects, and thread affinity is not optional for those. */
typedef struct {
  void *s;
  void *tex;
  int64_t result;
} ArgLumaSum;
static int job_blt_luma_sum(void *vp) {
  ArgLumaSum *a = (ArgLumaSum *)vp;
  a->result = mfenc_test_blt_luma_sum_impl(a->s, a->tex);
  return 0;
}
MFENC_API int64_t miniav_shim_mfenc_test_blt_luma_sum(void *session,
                                                      void *texture_ptr) {
  ArgLumaSum a = {session, texture_ptr, -1};
  if (mfenc_on_worker(job_blt_luma_sum, &a, -1) != 0) return -1;
  return a.result;
}

#endif /* _WIN32 */
