// IMPORTANT: This file should be compiled as C++

#include "screen_context_win_wgc.h"
#include "screen_context_win_wgc_strict.h"
#include "wgc_frame_texture.h"
#include "wgc_platform_context.h"
#include "../../../include/miniav.h" // For MiniAV types, MiniAV_GetErrorString
#include "../../common/miniav_com_win.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h"
#include "../../common/miniav_utils.h" // For miniav_calloc, miniav_free, strncpy_s_miniav
#include "../../loopback/loopback_context.h" // For MiniAVLoopbackContextHandle and related API

#include <DispatcherQueue.h>
#include <d3d11_4.h>
#include <dwmapi.h>  // For DwmGetWindowAttribute, DWMWA_CLOAKED
#include <dxgi1_6.h> // For DXGI_SHARED_RESOURCE_READ
#include <inspectable.h>
#include <roapi.h>
#include <windows.h>

#include <winrt/Windows.Foundation.Metadata.h> // ApiInformation (cursor toggle presence check)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.System.h>

// Interop header for creating GraphicsCaptureItem from HWND/HMONITOR
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <atomic>
#include <mutex> // For critical sections if not using Windows API
#include <string>
#include <vector>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "dwmapi.lib")

// Windows.Graphics.Capture.IGraphicsCaptureSession5, which carries
// GraphicsCaptureSession.MinUpdateInterval (Windows 11 24H2, 10.0.26100). The
// SDK this builds against predates it, so it is declared here, with the IID
// and slots of the OS's own metadata; querying the session for it is the
// runtime check. The interval is a TimeSpan: 100 ns units.
struct __declspec(uuid("67C0EA62-1F85-5061-925A-239BE0AC09CB"))
    __declspec(novtable) IWgcCaptureSession5 : ::IInspectable {
  virtual HRESULT __stdcall get_MinUpdateInterval(INT64 *value) = 0;
  virtual HRESULT __stdcall put_MinUpdateInterval(INT64 value) = 0;
};

// --- WinRT and Dispatcher Queue Management ---
static std::atomic<int> g_wgc_init_count = 0;
static winrt::Windows::System::DispatcherQueueController
    g_dispatcher_queue_controller{nullptr};
static std::mutex g_wgc_init_mutex;
// NEW: track whether we actually initialized the apartment
static bool g_wgc_initialized_apartment = false;

MiniAVResultCode init_winrt_for_wgc() {
  std::lock_guard<std::mutex> lock(g_wgc_init_mutex);
  if (g_wgc_init_count == 0) {
    if (!miniav_com_legacy_percall()) {
      // Apartment membership is process-lifetime and library-owned.
      // winrt::init_apartment()/uninit_apartment() are CoInitializeEx/
      // CoUninitialize on the CALLING thread, and the thread that constructs a
      // WGC context is rarely the thread that destroys it.
      miniav_com_ensure_mta();
      miniav_com_trace("init_winrt_for_wgc", 0);
      g_wgc_initialized_apartment = false;
    } else {
      try {
        // Attempt MTA init. If apartment already initialized differently, handle gracefully.
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        g_wgc_initialized_apartment = true;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC: WinRT apartment initialized (MTA).");
      } catch (winrt::hresult_error const &ex) {
        if (ex.code() == RPC_E_CHANGED_MODE) {
          // Already initialized with different model; continue without re-initializing.
          g_wgc_initialized_apartment = false;
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WGC: WinRT apartment already initialized with different threading model (0x%08X). Continuing.",
                     ex.code().value);
        } else {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WGC: WinRT initialization failed: %ls (0x%08X)",
                     ex.message().c_str(), ex.code().value);
          return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
      }
    }
    try {
      if (!g_dispatcher_queue_controller)
        g_dispatcher_queue_controller = winrt::Windows::System::DispatcherQueueController::CreateOnDedicatedThread();
      if (!g_dispatcher_queue_controller) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WGC: Failed to create DispatcherQueueController.");
        if (g_wgc_initialized_apartment) {
          winrt::uninit_apartment();
          g_wgc_initialized_apartment = false;
        }
        return MINIAV_ERROR_SYSTEM_CALL_FAILED;
      }
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC: DispatcherQueue initialized.");
    } catch (winrt::hresult_error const &ex) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: DispatcherQueue creation failed: %ls (0x%08X)",
                 ex.message().c_str(), ex.code().value);
      if (g_wgc_initialized_apartment) {
        winrt::uninit_apartment();
        g_wgc_initialized_apartment = false;
      }
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }
  g_wgc_init_count++;
  return MINIAV_SUCCESS;
}

void shutdown_winrt_for_wgc(bool retain_dispatcher = false) {
  std::lock_guard<std::mutex> lock(g_wgc_init_mutex);
  g_wgc_init_count--;
  if (g_wgc_init_count == 0 && !retain_dispatcher) {
    if (g_dispatcher_queue_controller) {
      try {
        auto async_shutdown = g_dispatcher_queue_controller.ShutdownQueueAsync();
        async_shutdown.get();
        g_dispatcher_queue_controller = nullptr;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC: DispatcherQueueController shut down.");
      } catch (winrt::hresult_error const &ex) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: Error shutting down DispatcherQueueController: %ls",
                   ex.message().c_str());
      }
    }
    if (g_wgc_initialized_apartment) {
      winrt::uninit_apartment();
      g_wgc_initialized_apartment = false;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: WinRT apartment uninitialized.");
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC: Skipped uninit_apartment (not initialized here).");
    }
  }
}

// --- Structs ---


// Payload for releasing WGC frame resources
typedef struct WGCFrameReleasePayload {
  MiniAVOutputPreference original_output_preference;
  MiniAVOutputPreference actual_output_preference;
  ID3D11Texture2D
      *gpu_texture_to_release; // AddRef'd texture (original or shared copy)
  // Shared NT HANDLE handed to the app as planes[0].data_ptr on the GPU path.
  // OWNERSHIP: miniav owns it and CloseHandle()s it in wgc_release_buffer —
  // the app must NOT close it (double-close) and must finish importing it
  // (OpenSharedResource1 / equivalent) BEFORE calling MiniAV_ReleaseBuffer.
  HANDLE gpu_shared_handle_to_close;

  ID3D11Texture2D *cpu_staging_texture_to_unmap_release; // AddRef'd
  ID3D11DeviceContext *d3d_context_for_unmap;            // AddRef'd if non-null
  UINT subresource_for_unmap;

} WGCFrameReleasePayload;

// Live count of shared NT handles handed to the app and not yet closed by
// wgc_release_buffer. Guards against the close silently disappearing again:
// wgc_destroy_platform logs loudly if this is not back to zero. Also bounds
// the damage of an app that never releases buffers (rate-limited warning).
static std::atomic<long> g_wgc_outstanding_shared_handles{0};

// Close a shared NT handle that was counted by the +1 next to CreateSharedHandle.
// Every exit path for a handed-out handle MUST go through here.
static void wgc_close_shared_handle(HANDLE h) {
  if (!h)
    return;
  CloseHandle(h);
  g_wgc_outstanding_shared_handles.fetch_sub(1, std::memory_order_relaxed);
}

// Available since Windows 10 1803; guard for older SDK headers.
#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

// Liveness canary. Set to _LIVE by wgc_init_platform and overwritten with
// _DEAD immediately before miniav_free() in wgc_destroy_platform, so a
// threadpool callback that survived teardown reads poison instead of silently
// operating on recycled heap. See wgc_ctx_alive().
#define WGC_CTX_MAGIC_LIVE 0x57474331u /* 'WGC1' */
#define WGC_CTX_MAGIC_DEAD 0xDEADDEADu



static MiniAVResultCode wgc_take_strict_device(
    void *raw, void **device, void **immediate, void **rt_device) {
  auto value = static_cast<WGCScreenPlatformContext *>(raw);
  if (!value->d3d_device || !value->d3d_context || !value->d3d_device_winrt)
    return MINIAV_ERROR_NOT_INITIALIZED;
  // Called only after the strict claim, with an operation protecting transfer
  // or on its sole cleanup worker. Generic use can never coexist with it.
  *device = value->d3d_device.detach();
  *immediate = value->d3d_context.detach();
  *rt_device = winrt::detach_abi(value->d3d_device_winrt);
  return MINIAV_SUCCESS;
}

void *miniav_wgc_strict_holder(MiniAVScreenContext *ctx) {
  if (!ctx || ctx->ops != &g_screen_ops_win_wgc || !ctx->platform_ctx)
    return nullptr;
  return static_cast<WGCScreenPlatformContext *>(ctx->platform_ctx)->strict_holder;
}

bool miniav_wgc_context_is_strict(MiniAVScreenContext *ctx) {
  auto holder = miniav_wgc_strict_holder(ctx);
  return holder && miniav_wgc_strict_claimed(holder);
}

MiniAVResultCode miniav_wgc_generic_configuration(MiniAVScreenContext *ctx) {
  auto holder = miniav_wgc_strict_holder(ctx);
  return holder ? miniav_wgc_strict_claim_generic(holder)
                : MINIAV_ERROR_NOT_INITIALIZED;
}

MiniAVResultCode miniav_wgc_route_start(MiniAVScreenContext *ctx,
    MiniAVBufferCallback callback, void *user_data, bool *handled) {
  return miniav_wgc_strict_start(miniav_wgc_strict_holder(ctx), callback,
                                user_data, handled);
}

MiniAVResultCode miniav_wgc_route_stop(MiniAVScreenContext *ctx, bool *handled) {
  return miniav_wgc_strict_stop(miniav_wgc_strict_holder(ctx), handled);
}

MiniAVResultCode miniav_wgc_set_lost(MiniAVScreenContext *ctx,
    MiniAVContextLostCallback callback, void *user_data) {
  return miniav_wgc_strict_set_lost(miniav_wgc_strict_holder(ctx), callback,
                                   user_data);
}

MiniAVResultCode miniav_wgc_set_cursor(MiniAVScreenContext *ctx, bool enabled) {
  return miniav_wgc_strict_set_cursor(miniav_wgc_strict_holder(ctx), enabled);
}

MiniAVResultCode miniav_wgc_configured_formats(MiniAVScreenContext *ctx,
    MiniAVVideoInfo *video, MiniAVAudioInfo *audio) {
  const auto result = miniav_wgc_strict_formats(miniav_wgc_strict_holder(ctx),
                                               video, audio);
  // Preserve the generic backend's actual loopback format. It lives in the
  // platform context, not in the parent's configured_audio_format field.
  if (result == MINIAV_SUCCESS && audio && !miniav_wgc_context_is_strict(ctx)) {
    auto platform = static_cast<WGCScreenPlatformContext *>(ctx->platform_ctx);
    if (platform->audio_loopback_enabled_and_configured)
      *audio = platform->configured_audio_format;
  }
  return result;
}

// ===========================================================================
// Threadpool-callback lifetime protocol
// ===========================================================================
// WinRT dispatches FrameArrived and GraphicsCaptureItem.Closed on threadpool
// threads, and the pacing timer (see wgc_pump) fires on one too. Revoking an
// event token does NOT wait for a handler that is already running, so the
// owner thread could previously DeleteCriticalSection() and miniav_free() the
// context while a callback thread was still reading it (a window that a
// pacing wait outside the critical section once made a frame interval wide).
//
// Three pieces close that:
//
//  1. g_wgc_live — a registry of contexts a callback is allowed to latch onto.
//     Entries are "sealed" (accepting = false) at the very start of teardown,
//     so a handler that begins executing after token revocation finds nothing
//     and returns WITHOUT dereferencing the pointer.
//  2. callbacks_in_flight — incremented under g_wgc_live_mutex (so an
//     increment can never race past the seal unobserved) and decremented on
//     every exit path by the WGCCallbackRef RAII guard.
//  3. wgc_drain_callbacks() — teardown waits for the counter to reach zero
//     BEFORE closing handles / deleting the critical section / freeing.
//
// DEADLOCK-FREEDOM (the reason for the exact ordering in wgc_stop_capture and
// wgc_destroy_platform):
//   * An in-flight callback can block on (a) the context's critical section,
//     (b) g_wgc_live_mutex, (c) the copy fence (bounded, and under (a)).
//   * The drain is therefore always performed with the critical section NOT
//     held. Draining under it would block the very handler we are waiting for
//     in EnterCriticalSection — a guaranteed hang.
//   * g_wgc_live_mutex is a leaf: it is never held while acquiring the
//     critical section, while calling into WinRT/D3D, or while draining. The
//     acquire/release helpers take it only around a vector scan and one atomic.
//   * Nothing waits outside the critical section: teardown sets
//     is_streaming = FALSE under it *before* draining, and a callback that
//     gets the lock after that only hands its frames back. The pacing timer
//     is disarmed under the lock and closed after the drain.
//   * Re-entrancy: the app may call StopCapture/DestroyContext from inside its
//     own lost_cb, which runs on a threadpool thread that already holds a
//     reference. The drain discounts references held by the *calling* thread
//     for the *same* context (t_wgc_callback_ctx / _depth), so it never waits
//     on itself.
//   * The wait is bounded (WGC_DRAIN_TIMEOUT_MS) and logs loudly on expiry, so
//     an unforeseen blocking callback degrades to the old (racy) behaviour with
//     a diagnostic instead of hanging the app forever.

#define WGC_DRAIN_TIMEOUT_MS 2000u

struct WGCLiveEntry {
  WGCScreenPlatformContext *ctx;
  bool accepting; // false once teardown started: no NEW callback may latch on
};

static std::mutex g_wgc_live_mutex;
static std::vector<WGCLiveEntry> g_wgc_live;

// Which context (if any) this thread is currently executing a WGC threadpool
// callback for, and how deep. Used only to let a drain reached from inside a
// callback discount its own reference.
static thread_local WGCScreenPlatformContext *t_wgc_callback_ctx = nullptr;
static thread_local int t_wgc_callback_depth = 0;

// Count of times a callback thread observed a torn-down context. Must stay 0;
// non-zero means the drain protocol was defeated. Exported for the teardown
// stress harness (see src/screen/test/test_wgc_teardown_stress.c).
static std::atomic<long> g_wgc_ctx_uaf_hits{0};

extern "C" __declspec(dllexport) long miniav_wgc_debug_ctx_uaf_hits(void) {
  return g_wgc_ctx_uaf_hits.load(std::memory_order_relaxed);
}

// Count of delivered frames whose advertised data_size_bytes exceeded the
// bytes actually backing them (mapped staging extent on the CPU path, texture
// extent on the GPU path). Must stay 0. The oracle is D3D's own report of what
// was mapped/allocated, NOT the frame-pool bookkeeping being fixed, so it stays
// a valid check independent of that fix. Exported for
// src/screen/test/test_wgc_resize_stress.c.
static std::atomic<long> g_wgc_oversize_reports{0};

extern "C" __declspec(dllexport) long miniav_wgc_debug_oversize_reports(void) {
  return g_wgc_oversize_reports.load(std::memory_order_relaxed);
}

// Count of frame-pool recreations performed in response to a content-size
// change. Exported so the resize harness can prove the fix actually engaged
// rather than the window never having resized.
static std::atomic<long> g_wgc_pool_recreates{0};

extern "C" __declspec(dllexport) long miniav_wgc_debug_pool_recreates(void) {
  return g_wgc_pool_recreates.load(std::memory_order_relaxed);
}

// Poison check. Callers must already hold a WGCCallbackRef; this only catches
// a protocol violation (or the deliberate MINIAV_WGC_STRESS_NO_DRAIN mode).
static bool wgc_ctx_alive(WGCScreenPlatformContext *c, const char *where) {
  if (c && c->ctx_magic == WGC_CTX_MAGIC_LIVE)
    return true;
  const long n = g_wgc_ctx_uaf_hits.fetch_add(1, std::memory_order_relaxed) + 1;
  miniav_log(MINIAV_LOG_LEVEL_ERROR,
             "WGC-UAF-CANARY: %s touched a destroyed capture context "
             "(magic=0x%08lX, hit #%ld).",
             where, c ? (unsigned long)c->ctx_magic : 0UL, n);
  return false;
}

static bool wgc_stress_env_flag(const char *name) {
  char buf[8] = {0};
  const DWORD n = GetEnvironmentVariableA(name, buf, (DWORD)sizeof(buf));
  return n > 0 && buf[0] == '1';
}

// Test-only escape hatches for src/screen/test/test_wgc_teardown_stress.c.
// Never set these in production.
//
//  MINIAV_WGC_STRESS_NO_DRAIN=1   restore the PRE-FIX teardown semantics: no
//                                 callback drain in stop/destroy.
//  MINIAV_WGC_STRESS_PACE_SLEEP=1 park every frame callback for a frame
//                                 interval outside the lock, blind to
//                                 teardown, the way the old pacing wait did.
//                                 Together the two reproduce the original
//                                 wide use-after-free window.
static bool wgc_stress_legacy_teardown() {
  static std::atomic<int> cached{-1};
  int v = cached.load(std::memory_order_relaxed);
  if (v < 0) {
    v = wgc_stress_env_flag("MINIAV_WGC_STRESS_NO_DRAIN") ? 1 : 0;
    cached.store(v, std::memory_order_relaxed);
    if (v) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: MINIAV_WGC_STRESS_NO_DRAIN=1 — teardown callback drain "
                 "DISABLED (test-only; reintroduces the use-after-free).");
    }
  }
  return v != 0;
}

// MINIAV_WGC_STRESS_NO_POOL_RECREATE=1 restores the PRE-FIX frame-pool
// behaviour: the pool is never recreated when the captured content is resized,
// AND the delivered buffer is described with the raw frame.ContentSize()
// instead of the extent that was actually mapped. Test-only positive control
// for src/screen/test/test_wgc_resize_stress.c.
static bool wgc_stress_no_pool_recreate() {
  static std::atomic<int> cached{-1};
  int v = cached.load(std::memory_order_relaxed);
  if (v < 0) {
    v = wgc_stress_env_flag("MINIAV_WGC_STRESS_NO_POOL_RECREATE") ? 1 : 0;
    cached.store(v, std::memory_order_relaxed);
    if (v) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: MINIAV_WGC_STRESS_NO_POOL_RECREATE=1 — frame pool will "
                 "not track content resizes and buffer sizes are reported "
                 "unclamped (test-only; reintroduces the over-long "
                 "data_size_bytes).");
    }
  }
  return v != 0;
}

// MINIAV_WGC_STRESS_UPPERCASE_PID=1 makes the per-process audio target ID be
// emitted as "PID:<id>" again (the pre-fix producer). On its own this is now
// harmless because the consumer matches case-insensitively; combined with
// MINIAV_LOOPBACK_STRESS_CASE_SENSITIVE_ID=1 it reproduces the original
// silent per-window-audio failure end to end. Test-only.
static bool wgc_stress_uppercase_pid() {
  static std::atomic<int> cached{-1};
  int v = cached.load(std::memory_order_relaxed);
  if (v < 0) {
    v = wgc_stress_env_flag("MINIAV_WGC_STRESS_UPPERCASE_PID") ? 1 : 0;
    cached.store(v, std::memory_order_relaxed);
    if (v) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: MINIAV_WGC_STRESS_UPPERCASE_PID=1 — emitting the "
                 "pre-fix \"PID:\" audio target ID (test-only).");
    }
  }
  return v != 0;
}

// MINIAV_SCREEN_STRESS_AUDIO_OPTIONAL=1 restores the PRE-FIX return policy:
// "audio was requested but could not be configured" degrades silently to a
// video-only capture that still reports MINIAV_SUCCESS. Test-only; exists so
// the resize harness can show the original silent failure rather than merely
// asserting that the fixed code declines.
static bool wgc_stress_audio_optional() {
  static std::atomic<int> cached{-1};
  int v = cached.load(std::memory_order_relaxed);
  if (v < 0) {
    v = wgc_stress_env_flag("MINIAV_SCREEN_STRESS_AUDIO_OPTIONAL") ? 1 : 0;
    cached.store(v, std::memory_order_relaxed);
    if (v) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: MINIAV_SCREEN_STRESS_AUDIO_OPTIONAL=1 — unavailable "
                 "audio degrades silently to video-only (test-only).");
    }
  }
  return v != 0;
}

static bool wgc_stress_force_pace_sleep() {
  static std::atomic<int> cached{-1};
  int v = cached.load(std::memory_order_relaxed);
  if (v < 0) {
    v = wgc_stress_env_flag("MINIAV_WGC_STRESS_PACE_SLEEP") ? 1 : 0;
    cached.store(v, std::memory_order_relaxed);
    if (v) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: MINIAV_WGC_STRESS_PACE_SLEEP=1 — frame callbacks park "
                 "for a frame interval outside the lock (test-only).");
    }
  }
  return v != 0;
}

static void wgc_register_live(WGCScreenPlatformContext *c) {
  std::lock_guard<std::mutex> lock(g_wgc_live_mutex);
  WGCLiveEntry e = {c, true};
  g_wgc_live.push_back(e);
}

// Stop accepting NEW callbacks. Must run before wgc_drain_callbacks().
static void wgc_seal_live(WGCScreenPlatformContext *c) {
  std::lock_guard<std::mutex> lock(g_wgc_live_mutex);
  for (size_t i = 0; i < g_wgc_live.size(); ++i) {
    if (g_wgc_live[i].ctx == c) {
      g_wgc_live[i].accepting = false;
      return;
    }
  }
}

// Drop the entry entirely. Called immediately before miniav_free(): after this
// a late reference-release finds no entry and does not write to freed memory.
static void wgc_retire_live(WGCScreenPlatformContext *c) {
  std::lock_guard<std::mutex> lock(g_wgc_live_mutex);
  for (auto it = g_wgc_live.begin(); it != g_wgc_live.end(); ++it) {
    if (it->ctx == c) {
      g_wgc_live.erase(it);
      return;
    }
  }
}

// RAII reference held for the whole body of every threadpool entry point.
// While held, the context cannot be freed by wgc_destroy_platform.
struct WGCCallbackRef {
  WGCScreenPlatformContext *ctx;
  WGCScreenPlatformContext *prev_ctx;
  int prev_depth;
  bool held;

  explicit WGCCallbackRef(WGCScreenPlatformContext *c)
      : ctx(c), prev_ctx(nullptr), prev_depth(0), held(false) {
    if (!c)
      return;
    {
      std::lock_guard<std::mutex> lock(g_wgc_live_mutex);
      for (size_t i = 0; i < g_wgc_live.size(); ++i) {
        if (g_wgc_live[i].ctx == c && g_wgc_live[i].accepting) {
          c->callbacks_in_flight.fetch_add(1, std::memory_order_acq_rel);
          held = true;
          break;
        }
      }
    }
    if (!held)
      return;
    prev_ctx = t_wgc_callback_ctx;
    prev_depth = t_wgc_callback_depth;
    t_wgc_callback_depth = (prev_ctx == c) ? prev_depth + 1 : 1;
    t_wgc_callback_ctx = c;
  }

  ~WGCCallbackRef() {
    if (!held)
      return;
    t_wgc_callback_ctx = prev_ctx;
    t_wgc_callback_depth = prev_depth;
    // If the entry is gone the context was already freed by a destroy that ran
    // on THIS thread (app destroyed from inside its lost_cb) — the drain
    // discounted this reference, so there is nothing to decrement and nothing
    // to write to.
    std::lock_guard<std::mutex> lock(g_wgc_live_mutex);
    for (size_t i = 0; i < g_wgc_live.size(); ++i) {
      if (g_wgc_live[i].ctx == ctx) {
        ctx->callbacks_in_flight.fetch_sub(1, std::memory_order_acq_rel);
        return;
      }
    }
  }

  explicit operator bool() const { return held; }

  WGCCallbackRef(const WGCCallbackRef &) = delete;
  WGCCallbackRef &operator=(const WGCCallbackRef &) = delete;
};

// Wait until no threadpool callback is running against wgc_ctx (excluding a
// reference held by the calling thread itself). MUST be called with
// wgc_ctx->critical_section NOT held — see the deadlock note above.
static void wgc_drain_callbacks(WGCScreenPlatformContext *wgc_ctx,
                                const char *who) {
  if (!wgc_ctx)
    return;
  const long self =
      (t_wgc_callback_ctx == wgc_ctx) ? (long)t_wgc_callback_depth : 0;
  if (wgc_stress_legacy_teardown()) {
    const long n = wgc_ctx->callbacks_in_flight.load(std::memory_order_acquire);
    if (n > self) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC-UAF-CANARY: %s proceeding with %ld in-flight capture "
                 "callback(s) (drain disabled).",
                 who, n - self);
    }
    return;
  }
  const ULONGLONG start = GetTickCount64();
  for (;;) {
    const long n = wgc_ctx->callbacks_in_flight.load(std::memory_order_acquire);
    if (n <= self)
      return;
    if (GetTickCount64() - start > WGC_DRAIN_TIMEOUT_MS) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: %s timed out after %u ms draining %ld in-flight capture "
                 "callback(s) — proceeding anyway (teardown may race a "
                 "callback).",
                 who, WGC_DRAIN_TIMEOUT_MS, n - self);
      return;
    }
    Sleep(1);
  }
}

// --- Forward declarations for static functions ---
static MiniAVResultCode wgc_init_d3d_device(WGCScreenPlatformContext *wgc_ctx);
static void wgc_cleanup_d3d_device(WGCScreenPlatformContext *wgc_ctx);
static void wgc_cleanup_capture_resources(WGCScreenPlatformContext *wgc_ctx);
static void wgc_notify_capture_lost(WGCScreenPlatformContext *wgc_ctx,
                                    const char *why);
static void wgc_on_frame_arrived(
    WGCScreenPlatformContext *wgc_ctx,
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool const &sender,
    winrt::Windows::Foundation::IInspectable const &args);
static VOID CALLBACK wgc_on_pace_wake(PTP_CALLBACK_INSTANCE instance,
                                      PVOID param, PTP_WAIT wait,
                                      TP_WAIT_RESULT result);
static VOID CALLBACK wgc_on_window_watch(PTP_CALLBACK_INSTANCE instance,
                                         PVOID param, PTP_TIMER timer);

// Frame-pool depth: WGC keeps capturing into the third surface while one frame
// is held for its output slot and the next has just been taken.
#define WGC_POOL_BUFFERS 3

using WGCFrame = winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame;

// Hands a frame's surface back to the pool. Safe on a null frame.
static void wgc_close_frame(WGCFrame &frame) {
  if (!frame)
    return;
  try {
    frame.Close();
  } catch (...) {
  }
  frame = nullptr;
}

// Now, on the clock SystemRelativeTime reports: QPC, in 100 ns units.
static LONGLONG wgc_now_100ns(WGCScreenPlatformContext *wgc_ctx) {
  LARGE_INTEGER freq = wgc_ctx->qpc_frequency;
  if (freq.QuadPart <= 0)
    QueryPerformanceFrequency(&freq);
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return now.QuadPart / freq.QuadPart * 10000000LL +
         now.QuadPart % freq.QuadPart * 10000000LL / freq.QuadPart;
}

// Adds one timing to a WGCFrameStats count, sum and maximum.
static void wgc_stats_time(UINT32 &count, LONGLONG &sum, LONGLONG &max,
                           LONGLONG t) {
  count++;
  sum += t;
  if (t > max)
    max = t;
}

// Output slots (see wgc_pump). Slot k is the instant
// grid_origin_100ns + k * pace_den / pace_num seconds. 1e7 * pace_den ticks
// hold exactly pace_num slots, so splitting a time into whole such periods and
// a remainder keeps the arithmetic exact, with no drift, and every product in
// range for rates whose terms are at most 100000.
static LONGLONG wgc_floor_div(LONGLONG a, LONGLONG b) {
  const LONGLONG q = a / b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

// The slot nearest time t.
static LONGLONG wgc_slot_of(WGCScreenPlatformContext *wgc_ctx, LONGLONG t) {
  const LONGLONG num = wgc_ctx->pace_num;
  const LONGLONG period = 10000000LL * wgc_ctx->pace_den;
  const LONGLONG d = t - wgc_ctx->grid_origin_100ns;
  const LONGLONG whole = wgc_floor_div(d, period);
  const LONGLONG rest = d - whole * period;
  return whole * num + (2 * rest * num + period) / (2 * period);
}

static LONGLONG wgc_slot_time(WGCScreenPlatformContext *wgc_ctx,
                              LONGLONG slot) {
  const LONGLONG num = wgc_ctx->pace_num;
  const LONGLONG period = 10000000LL * wgc_ctx->pace_den;
  const LONGLONG whole = wgc_floor_div(slot, num);
  return wgc_ctx->grid_origin_100ns + whole * period +
         (slot - whole * num) * period / num;
}

// When a slot's window closes: half an interval after its time, from where a
// newer frame belongs to the next slot. Brought forward by a sixteenth of that
// half to absorb the pacing timer's wake-up latency.
static LONGLONG wgc_slot_due(WGCScreenPlatformContext *wgc_ctx,
                             LONGLONG slot) {
  const LONGLONG half =
      10000000LL * wgc_ctx->pace_den / (2 * wgc_ctx->pace_num);
  return wgc_slot_time(wgc_ctx, slot) + half - half / 16;
}

// Arms the pacing wake to fire once, delay_100ns from now. A threadpool timer
// fires on the system clock tick, up to 15.6 ms late, which is most of a 60 fps
// interval; a high-resolution waitable timer is good to about a millisecond.
// False if it cannot be armed. Under critical_section.
static bool wgc_arm_pace_wake_locked(WGCScreenPlatformContext *wgc_ctx,
                                     LONGLONG delay_100ns) {
  if (!wgc_ctx->pace_tp_wait || !wgc_ctx->pace_wake_timer)
    return false;
  LARGE_INTEGER due;
  due.QuadPart = -delay_100ns; // negative: relative to now
  if (!SetWaitableTimer(wgc_ctx->pace_wake_timer, &due, 0, NULL, NULL, FALSE))
    return false;
  SetThreadpoolWait(wgc_ctx->pace_tp_wait, wgc_ctx->pace_wake_timer, NULL);
  return true;
}

// Disarms and closes the pacing wait, first waiting out a callback of it that
// is already running, unless the caller is a capture callback itself (a stop
// from inside the app's callback), which would wait for itself. Called after
// the drain, so such a callback only finds the run stopped; the caller must
// not hold critical_section otherwise, since the callback takes it. The next
// start creates a new wait; the waitable timer is kept for it.
static void wgc_close_pace_wake(WGCScreenPlatformContext *wgc_ctx) {
  EnterCriticalSection(&wgc_ctx->critical_section);
  PTP_WAIT wait = wgc_ctx->pace_tp_wait;
  wgc_ctx->pace_tp_wait = nullptr;
  if (wgc_ctx->pace_wake_timer)
    CancelWaitableTimer(wgc_ctx->pace_wake_timer);
  LeaveCriticalSection(&wgc_ctx->critical_section);
  if (!wait)
    return;
  SetThreadpoolWait(wait, nullptr, nullptr);
  if (t_wgc_callback_ctx != wgc_ctx)
    WaitForThreadpoolWaitCallbacks(wait, TRUE);
  CloseThreadpoolWait(wait);
}

// How often a window capture checks that its window still exists.
#define WGC_WINDOW_WATCH_MS 100

// Starts checking that the captured window still exists and belongs to the
// thread that owned it now. Windows does not raise Closed for every window
// that goes away (a closed popup whose process lived on never raised it), and
// the check also catches a handle reused by another window. Without a timer
// the capture still learns of a close when Closed is raised. Under
// critical_section.
static void wgc_arm_window_watch_locked(WGCScreenPlatformContext *wgc_ctx) {
  wgc_ctx->watched_pid = 0;
  wgc_ctx->watched_tid =
      GetWindowThreadProcessId(wgc_ctx->selected_hwnd, &wgc_ctx->watched_pid);
  if (!wgc_ctx->window_watch)
    wgc_ctx->window_watch =
        CreateThreadpoolTimer(wgc_on_window_watch, wgc_ctx, nullptr);
  if (!wgc_ctx->window_watch) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: could not create the window check (%lu); a closed "
               "window is noticed only if Windows reports it.",
               GetLastError());
    return;
  }
  ULARGE_INTEGER due;
  due.QuadPart = (ULONGLONG)(-(LONGLONG)WGC_WINDOW_WATCH_MS * 10000);
  FILETIME first;
  first.dwLowDateTime = due.LowPart;
  first.dwHighDateTime = due.HighPart;
  SetThreadpoolTimer(wgc_ctx->window_watch, &first, WGC_WINDOW_WATCH_MS,
                     WGC_WINDOW_WATCH_MS / 4);
}

// Disarms and closes the window check, the way wgc_close_pace_wake closes the
// pacing wait. The next window capture's start creates a new one.
static void wgc_close_window_watch(WGCScreenPlatformContext *wgc_ctx) {
  EnterCriticalSection(&wgc_ctx->critical_section);
  PTP_TIMER timer = wgc_ctx->window_watch;
  wgc_ctx->window_watch = nullptr;
  LeaveCriticalSection(&wgc_ctx->critical_section);
  if (!timer)
    return;
  SetThreadpoolTimer(timer, nullptr, 0, 0);
  if (t_wgc_callback_ctx != wgc_ctx)
    WaitForThreadpoolTimerCallbacks(timer, TRUE);
  CloseThreadpoolTimer(timer);
}

// Releases the copy fence (see wgc_wait_copy_locked). The next GPU frame
// creates one on whatever device the context has by then. Under
// critical_section, or once no callback can run.
static void wgc_release_copy_fence(WGCScreenPlatformContext *wgc_ctx) {
  wgc_ctx->copy_fence = nullptr;
  wgc_ctx->copy_fence_ctx = nullptr;
  if (wgc_ctx->copy_fence_event) {
    CloseHandle(wgc_ctx->copy_fence_event);
    wgc_ctx->copy_fence_event = NULL;
  }
  wgc_ctx->copy_fence_value = 0;
  wgc_ctx->copy_fence_unavailable = false;
}

// --- Helper to get ID3D11Texture2D from IDirect3DSurface ---
static winrt::com_ptr<ID3D11Texture2D> GetTextureFromDirect3DSurface(
    winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface const
        &surface) {
  try {
    // Attempt to get the IDirect3DDxgiInterfaceAccess interface from the
    // surface. This uses the raw COM interface type.
    // The windows.graphics.directx.direct3d11.interop.h header should provide
    // the definition for IDirect3DDxgiInterfaceAccess.
    auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::
                                 IDirect3DDxgiInterfaceAccess>();

    winrt::com_ptr<ID3D11Texture2D> texture;
    // Attempt to get the underlying ID3D11Texture2D.
    HRESULT hr = access->GetInterface(IID_PPV_ARGS(texture.put()));
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: GetInterface for ID3D11Texture2D failed: 0x%08X", hr);
      return nullptr;
    }
    return texture;
  } catch (winrt::hresult_error const &ex) {
    // This catch block will handle errors from surface.as<>() or other WinRT
    // exceptions.
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Error obtaining IDirect3DDxgiInterfaceAccess or "
               "ID3D11Texture2D from surface (WinRT error): %ls (0x%08X)",
               ex.message().c_str(), ex.code().value);
    return nullptr;
  } catch (...) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Unknown exception in GetTextureFromDirect3DSurface.");
    return nullptr;
  }
}

// --- Platform Ops Implementation ---

static MiniAVResultCode
wgc_get_default_formats(const char *device_id_utf8,
                        MiniAVVideoInfo *video_format_out,
                        MiniAVAudioInfo *audio_format_out) {
  if (!device_id_utf8 || !video_format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  memset(video_format_out, 0, sizeof(MiniAVVideoInfo));
  if (audio_format_out) {
    memset(audio_format_out, 0, sizeof(MiniAVAudioInfo));
  }

  HMONITOR hmonitor = NULL;
  HWND hwnd = NULL;
  WGCCaptureTargetType target_type = WGC_TARGET_NONE;

  if (strncmp(device_id_utf8, "HMONITOR:0x", 11) == 0) {
    if (sscanf_s(device_id_utf8, "HMONITOR:0x%p", (void **)&hmonitor) != 1 ||
        !hmonitor) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC GetDefaultFormats: Invalid display ID format: %s",
                 device_id_utf8);
      return MINIAV_ERROR_INVALID_ARG;
    }
    target_type = WGC_TARGET_DISPLAY;
  } else if (strncmp(device_id_utf8, "HWND:0x", 7) == 0) {
    if (sscanf_s(device_id_utf8, "HWND:0x%p", (void **)&hwnd) != 1 || !hwnd ||
        !IsWindow(hwnd)) {
      miniav_log(
          MINIAV_LOG_LEVEL_ERROR,
          "WGC GetDefaultFormats: Invalid window ID format or invalid HWND: %s",
          device_id_utf8);
      return MINIAV_ERROR_INVALID_ARG;
    }
    target_type = WGC_TARGET_WINDOW;
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC GetDefaultFormats: Unknown device ID format: %s",
               device_id_utf8);
    return MINIAV_ERROR_INVALID_ARG;
  }

  // --- Video Format ---
  video_format_out->pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // WGC default
  video_format_out->frame_rate_numerator = 60;
  video_format_out->frame_rate_denominator = 1;
  video_format_out->output_preference =
      MINIAV_OUTPUT_PREFERENCE_GPU; // Default preference

  if (target_type == WGC_TARGET_DISPLAY) {
    MONITORINFOEXW mi = {0};
    mi.cbSize = sizeof(MONITORINFOEXW);

    if (GetMonitorInfoW(hmonitor, (LPMONITORINFO)&mi)) {
      // Get the device name
      char device_name_utf8[256];
      WideCharToMultiByte(CP_UTF8, 0, mi.szDevice, -1, device_name_utf8,
                          sizeof(device_name_utf8), NULL, NULL);

      // Use EnumDisplaySettings to get the ACTUAL resolution
      DEVMODEW dev_mode = {0};
      dev_mode.dmSize = sizeof(DEVMODEW);

      if (EnumDisplaySettingsW(mi.szDevice, ENUM_CURRENT_SETTINGS, &dev_mode)) {
        // Use the actual display resolution, not the virtual desktop
        // coordinates
        video_format_out->width = dev_mode.dmPelsWidth;
        video_format_out->height = dev_mode.dmPelsHeight;

        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC GetDefaultFormats: Device %s - Virtual coords: "
                   "(%ld,%ld,%ld,%ld) = %ldx%ld",
                   device_name_utf8, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right, mi.rcMonitor.bottom,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top);
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "WGC GetDefaultFormats: Device %s - Actual resolution: %lux%lu",
            device_name_utf8, dev_mode.dmPelsWidth, dev_mode.dmPelsHeight);
      }
    }
  } else { // WGC_TARGET_WINDOW
    RECT rc;
    if (GetWindowRect(hwnd, &rc)) {
      video_format_out->width = rc.right - rc.left;
      video_format_out->height = rc.bottom - rc.top;
    } else {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC GetDefaultFormats: GetWindowRect failed for %s",
                 device_id_utf8);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }
  if (video_format_out->width == 0 || video_format_out->height == 0) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC GetDefaultFormats: Target %s has zero width or height.",
               device_id_utf8);
    // Allow proceeding, but this is unusual. WGC might fail later if item size
    // is 0.
  }

  // --- Audio Format (Optional) ---
  if (audio_format_out) {
    const char *loopback_target_id_str = NULL;
    char process_id_string_buffer[64];

    if (target_type == WGC_TARGET_WINDOW && hwnd) {
      DWORD process_id = 0;
      GetWindowThreadProcessId(hwnd, &process_id);
      if (process_id != 0) {
        // Lowercase "pid:" is the canonical scheme MiniAV_Loopback_* parses
        // (matching "hwnd:"). This used to emit "PID:" and the consumer
        // matched case-sensitively, so the ID fell through to the
        // MMDevice-ID branch and the lookup failed.
        snprintf(process_id_string_buffer, sizeof(process_id_string_buffer),
                 "pid:%lu", process_id);
        loopback_target_id_str = process_id_string_buffer;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC GetDefaultFormats: Querying default audio for PID: %lu",
                   process_id);
      } else {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC GetDefaultFormats: Could not get PID for HWND %p. "
                   "Querying system default audio.",
                   hwnd);
        // loopback_target_id_str remains NULL for system default
      }
    } else {
      miniav_log(
          MINIAV_LOG_LEVEL_DEBUG,
          "WGC GetDefaultFormats: Querying system default audio format.");
      // loopback_target_id_str remains NULL for system default
    }

    MiniAVResultCode audio_res = MiniAV_Loopback_GetDefaultFormat(
        loopback_target_id_str, audio_format_out);
    if (audio_res != MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WGC GetDefaultFormats: Failed to get default audio format "
                 "for target %s (loopback ID %s): %s. Audio format not set.",
                 device_id_utf8,
                 loopback_target_id_str ? loopback_target_id_str
                                        : "(system default)",
                 MiniAV_GetErrorString(audio_res));
      // audio_format_out is already zeroed, so no need to do anything else.
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC GetDefaultFormats: Default audio format for target %s "
                 "(loopback ID %s): Format=%d, Ch=%u, Rate=%u",
                 device_id_utf8,
                 loopback_target_id_str ? loopback_target_id_str
                                        : "(system default)",
                 audio_format_out->format, audio_format_out->channels,
                 audio_format_out->sample_rate);
    }
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "WGC GetDefaultFormats: Video: %ux%u @ %u/%u FPS, PixelFormat: "
             "%d. Audio queried: %s",
             video_format_out->width, video_format_out->height,
             video_format_out->frame_rate_numerator,
             video_format_out->frame_rate_denominator,
             video_format_out->pixel_format, audio_format_out ? "Yes" : "No");

  return MINIAV_SUCCESS;
}

static MiniAVResultCode
wgc_get_configured_video_formats(MiniAVScreenContext *ctx,
                                 MiniAVVideoInfo *video_format_out,
                                 MiniAVAudioInfo *audio_format_out) {
  if (!ctx || !ctx->platform_ctx || !video_format_out) {
    return MINIAV_ERROR_INVALID_ARG;
  }
  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;

  memset(video_format_out, 0, sizeof(MiniAVVideoInfo));
  if (audio_format_out) {
    memset(audio_format_out, 0, sizeof(MiniAVAudioInfo));
  }

  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC GetConfiguredFormats: Context not configured.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  // Video format is stored in the parent context's configured_video_format
  // which is updated by wgc_configure_capture_item
  *video_format_out = ctx->configured_video_format;

  // Audio format
  if (audio_format_out) {
    if (wgc_ctx->audio_loopback_enabled_and_configured) {
      *audio_format_out = wgc_ctx->configured_audio_format;
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC GetConfiguredFormats: Audio: Format=%d, Ch=%u, Rate=%u",
                 audio_format_out->format, audio_format_out->channels,
                 audio_format_out->sample_rate);
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC GetConfiguredFormats: Audio loopback not enabled or not "
                 "configured. Audio format not set.");
      // audio_format_out remains zeroed
    }
  }
  miniav_log(
      MINIAV_LOG_LEVEL_INFO,
      "WGC GetConfiguredFormats: Video: %ux%u @ %u/%u FPS, PixelFormat: %d. "
      "Audio configured: %s",
      video_format_out->width, video_format_out->height,
      video_format_out->frame_rate_numerator,
      video_format_out->frame_rate_denominator, video_format_out->pixel_format,
      (wgc_ctx->audio_loopback_enabled_and_configured && audio_format_out)
          ? "Yes"
          : "No/Not Requested");

  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_init_platform(MiniAVScreenContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Initializing platform context.");
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;

  auto *wgc_ctx = miniav::wgc_platform_storage::allocate();
  if (!wgc_ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Failed to construct WGCScreenPlatformContext.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->platform_ctx = wgc_ctx;
  // The complete C++ object and atomics exist before native activation.
  wgc_ctx->ctx_magic = WGC_CTX_MAGIC_LIVE;
  wgc_ctx->callbacks_in_flight = 0;
  wgc_ctx->parent_ctx = ctx;
  wgc_ctx->pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // WGC default
  wgc_ctx->is_streaming = FALSE;
  wgc_ctx->qpc_frequency = miniav_get_qpc_frequency();
  wgc_ctx->loopback_audio_ctx = NULL; // Initialize audio loopback members
  wgc_ctx->audio_loopback_enabled_and_configured = FALSE;

  // Complete cold control allocation before WinRT/dispatcher/D3D entry. This
  // is the legacy unscoped factory, so its unpublished owner has no funding
  // callbacks and checked disposal cannot refuse. A funded C bootstrap needs
  // its own original admission and retained-owned failure result, no fallback.
  wgc_ctx->strict_holder = miniav_wgc_strict_create(ctx, wgc_ctx, wgc_take_strict_device);
  if (!wgc_ctx->strict_holder) {
    miniav::wgc_platform_storage::destroy(wgc_ctx);
    ctx->platform_ctx = nullptr;
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }
  auto discard_unpublished = [&] {
    (void)miniav_wgc_strict_delete(wgc_ctx->strict_holder);
    wgc_ctx->strict_holder = nullptr;
    miniav::wgc_platform_storage::destroy(wgc_ctx);
    ctx->platform_ctx = nullptr;
  };
  MiniAVResultCode res = init_winrt_for_wgc();
  if (res != MINIAV_SUCCESS) {
    discard_unpublished();
    return res;
  }

  wgc_ctx->stop_event_handle =
      CreateEvent(NULL, TRUE, FALSE, NULL); // Manual-reset, non-signaled
  if (wgc_ctx->stop_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: Failed to create stop event.");
    discard_unpublished();
    shutdown_winrt_for_wgc();
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!InitializeCriticalSectionAndSpinCount(&wgc_ctx->critical_section,
                                             0x00000400)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Failed to initialize critical section.");
    CloseHandle(wgc_ctx->stop_event_handle);
    discard_unpublished();
    shutdown_winrt_for_wgc();
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  res = wgc_init_d3d_device(wgc_ctx);
  if (res != MINIAV_SUCCESS) {
    wgc_cleanup_d3d_device(wgc_ctx);
    DeleteCriticalSection(&wgc_ctx->critical_section);
    CloseHandle(wgc_ctx->stop_event_handle);
    discard_unpublished();
    shutdown_winrt_for_wgc();
    return res;
  }


  // Last: only a fully constructed context may be latched onto by a
  // threadpool callback. Every failure path above frees before this point.
  wgc_register_live(wgc_ctx);

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "WGC: Platform context initialized successfully.");
  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_destroy_platform(MiniAVScreenContext *ctx) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Destroying platform context.");
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;

  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;

  if (miniav_wgc_strict_claimed(wgc_ctx->strict_holder)) {
    const auto result = miniav_wgc_strict_prepare_destroy(wgc_ctx->strict_holder);
    if (result != MINIAV_SUCCESS) return result;
    // Real strict retirement already closed the per-source producer/device.
    // Never run the generic callback drain or global dispatcher shutdown here.
    if (wgc_ctx->stop_event_handle && !CloseHandle(wgc_ctx->stop_event_handle)) {
      miniav_wgc_strict_cleanup_failed(wgc_ctx->strict_holder,
                                        MINIAV_ERROR_SYSTEM_CALL_FAILED);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    wgc_ctx->stop_event_handle = nullptr;
    const auto disposed = miniav_wgc_strict_delete(wgc_ctx->strict_holder);
    if (disposed != MINIAV_SUCCESS) return disposed;
    wgc_ctx->strict_holder = nullptr;
    DeleteCriticalSection(&wgc_ctx->critical_section);
    wgc_retire_live(wgc_ctx);
    wgc_ctx->ctx_magic = WGC_CTX_MAGIC_DEAD;
    miniav::wgc_platform_storage::destroy(wgc_ctx);
    ctx->platform_ctx = nullptr;
    shutdown_winrt_for_wgc(true);
    return MINIAV_SUCCESS;
  }

  if (wgc_ctx->is_streaming) {
    miniav_log(
        MINIAV_LOG_LEVEL_WARN,
        "WGC: Platform being destroyed while streaming. Attempting to stop.");
    // Ensure audio is stopped first if it was running
    if (wgc_ctx->loopback_audio_ctx &&
        wgc_ctx->audio_loopback_enabled_and_configured) {
      MiniAV_Loopback_StopCapture(wgc_ctx->loopback_audio_ctx);
    }
  }

  // --- Teardown ordering (see "Threadpool-callback lifetime protocol") ---
  // 1. Under the lock: kill the streaming flag, drop the held frame, disarm
  //    the pacing timer, revoke the FrameArrived / Closed tokens and close the
  //    session + frame pool.
  EnterCriticalSection(&wgc_ctx->critical_section);
  wgc_ctx->is_streaming = FALSE;
  if (wgc_ctx->stop_event_handle)
    SetEvent(wgc_ctx->stop_event_handle);
  wgc_cleanup_capture_resources(wgc_ctx); // Cleans session, frame_pool, item
  LeaveCriticalSection(&wgc_ctx->critical_section);

  // 2. Refuse new callbacks. Token revocation alone does not do this: a
  //    handler dispatched just before the revoke can still start afterwards.
  wgc_seal_live(wgc_ctx);

  // 3. Wait out callbacks already executing — WITHOUT the critical section
  //    held, because wgc_on_frame_arrived acquires it (holding it here would
  //    turn a rare UAF into a reliable hang).
  wgc_drain_callbacks(wgc_ctx, "destroy_platform");
  wgc_close_pace_wake(wgc_ctx);
  wgc_close_window_watch(wgc_ctx);
  if (wgc_ctx->pace_wake_timer) {
    CloseHandle(wgc_ctx->pace_wake_timer);
    wgc_ctx->pace_wake_timer = NULL;
  }

  // 4. From here nothing can be running against wgc_ctx, so its handles,
  //    critical section and memory can be released.
  wgc_cleanup_d3d_device(wgc_ctx);

  // Destroy loopback audio context if it exists
  if (wgc_ctx->loopback_audio_ctx) {
    MiniAV_Loopback_DestroyContext(wgc_ctx->loopback_audio_ctx);
    wgc_ctx->loopback_audio_ctx = NULL;
    wgc_ctx->audio_loopback_enabled_and_configured = FALSE;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WGC: Loopback audio context destroyed.");
  }

  if (wgc_ctx->stop_event_handle) {
    CloseHandle(wgc_ctx->stop_event_handle);
    wgc_ctx->stop_event_handle = NULL;
  }
  DeleteCriticalSection(&wgc_ctx->critical_section);

  // Loud, non-silent guard for the handle-ownership contract (see
  // wgc_close_shared_handle). If this is non-zero the app dropped buffers
  // without MiniAV_ReleaseBuffer, or a future edit removed the close.
  // The counter is process-global, so only assert on the LAST live WGC
  // context (g_wgc_init_count is one-per-context and is decremented by
  // shutdown_winrt_for_wgc() below).
  if (g_wgc_init_count.load() <= 1) {
    const long outstanding =
        g_wgc_outstanding_shared_handles.load(std::memory_order_relaxed);
    if (outstanding != 0) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: %ld GPU shared NT handle(s) still open at context "
                 "destroy — leaked. Every captured GPU buffer must be passed "
                 "to MiniAV_ReleaseBuffer.",
                 outstanding);
    }
  }

  // Drop the registry entry BEFORE the free, so a reference-release that
  // happens after this point (only possible for a destroy re-entered from
  // inside a callback on this same thread) finds nothing and does not write to
  // freed memory. Then poison the canary so any surviving reader is caught by
  // wgc_ctx_alive() instead of silently working on recycled heap.
  wgc_retire_live(wgc_ctx);
  const auto disposed = miniav_wgc_strict_delete(wgc_ctx->strict_holder);
  if (disposed != MINIAV_SUCCESS) return disposed;
  wgc_ctx->strict_holder = nullptr;
  wgc_ctx->ctx_magic = WGC_CTX_MAGIC_DEAD;
  miniav::wgc_platform_storage::destroy(wgc_ctx);
  ctx->platform_ctx = NULL;

  shutdown_winrt_for_wgc();
  miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Platform context destroyed.");
  return MINIAV_SUCCESS;
}

struct EnumDisplayData {
  std::vector<MiniAVDeviceInfo> *devices;
  uint32_t monitor_idx;
};

BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC hdcMonitor,
                              LPRECT lprcMonitor, LPARAM dwData) {
  MINIAV_UNUSED(hdcMonitor);
  MINIAV_UNUSED(lprcMonitor);
  EnumDisplayData *data = reinterpret_cast<EnumDisplayData *>(dwData);
  MONITORINFOEXW mi;
  mi.cbSize = sizeof(mi);
  if (GetMonitorInfoW(hMonitor, &mi)) {
    MiniAVDeviceInfo dev_info = {0};
    // ID: "HMONITOR:0xADDRESS"
    snprintf(dev_info.device_id, MINIAV_DEVICE_ID_MAX_LEN, "HMONITOR:0x%p",
             (void *)hMonitor);
    WideCharToMultiByte(CP_UTF8, 0, mi.szDevice, -1, dev_info.name,
                        MINIAV_DEVICE_NAME_MAX_LEN, NULL, NULL);
    dev_info.is_default = (mi.dwFlags & MONITORINFOF_PRIMARY) ? TRUE : FALSE;
    data->devices->push_back(dev_info);
    data->monitor_idx++;
  }
  return TRUE;
}

static MiniAVResultCode wgc_enumerate_displays(MiniAVDeviceInfo **displays_out,
                                               uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Enumerating displays.");
  if (!displays_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *displays_out = NULL;
  *count_out = 0;

  std::vector<MiniAVDeviceInfo> devices;
  EnumDisplayData data = {&devices, 0};

  if (!EnumDisplayMonitors(NULL, NULL, MonitorEnumProc,
                           reinterpret_cast<LPARAM>(&data))) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: EnumDisplayMonitors failed: %lu",
               GetLastError());
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!devices.empty()) {
    *displays_out = (MiniAVDeviceInfo *)miniav_calloc(devices.size(),
                                                      sizeof(MiniAVDeviceInfo));
    if (!*displays_out) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to allocate memory for display list.");
      return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*displays_out, devices.data(),
           devices.size() * sizeof(MiniAVDeviceInfo));
    *count_out = static_cast<uint32_t>(devices.size());
  }
  miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Enumerated %u displays.", *count_out);
  return MINIAV_SUCCESS;
}

struct EnumWindowData {
  std::vector<MiniAVDeviceInfo> *devices;
  DWORD current_pid;
};

BOOL CALLBACK WindowEnumProc(HWND hWnd, LPARAM lParam) {
  EnumWindowData *data = reinterpret_cast<EnumWindowData *>(lParam);

  // Skip non-visible, non-capturable, or own process windows
  if (!IsWindowVisible(hWnd) || GetAncestor(hWnd, GA_ROOTOWNER) != hWnd) {
    return TRUE;
  }

  // Skip tool windows, etc.
  LONG style = GetWindowLong(hWnd, GWL_STYLE);
  if (!(style & WS_VISIBLE) ||
      (style & WS_CHILD)) { // Must be visible, not child
    return TRUE;
  }
  LONG ex_style = GetWindowLong(hWnd, GWL_EXSTYLE);
  if (ex_style & WS_EX_TOOLWINDOW) { // Skip tool windows
    return TRUE;
  }

  // Check if the window is cloaked (e.g., UWP apps minimized)
  // WGC cannot capture cloaked windows.
  DWORD cloaked = 0;
  HRESULT hr_dwm =
      DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, &cloaked, sizeof(cloaked));
  if (SUCCEEDED(hr_dwm) && cloaked != 0) {
    return TRUE;
  }

  wchar_t title_w[MINIAV_DEVICE_NAME_MAX_LEN];
  int len = GetWindowTextW(hWnd, title_w, MINIAV_DEVICE_NAME_MAX_LEN);
  if (len == 0 &&
      GetLastError() != 0) { // GetWindowTextW sets last error on failure
    // Could log error, or just skip if title is empty / error
    return TRUE;
  }
  if (len == 0) { // Skip windows with no title
    return TRUE;
  }

  // Skip current process's windows to avoid potential issues
  DWORD window_pid;
  GetWindowThreadProcessId(hWnd, &window_pid);
  if (window_pid == data->current_pid) {
    return TRUE;
  }

  MiniAVDeviceInfo dev_info = {0};
  snprintf(dev_info.device_id, MINIAV_DEVICE_ID_MAX_LEN, "HWND:0x%p",
           (void *)hWnd);
  WideCharToMultiByte(CP_UTF8, 0, title_w, -1, dev_info.name,
                      MINIAV_DEVICE_NAME_MAX_LEN, NULL, NULL);
  dev_info.is_default = FALSE; // No concept of "default" window for capture
  data->devices->push_back(dev_info);

  return TRUE;
}

static MiniAVResultCode wgc_enumerate_windows(MiniAVDeviceInfo **windows_out,
                                              uint32_t *count_out) {
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Enumerating windows.");
  if (!windows_out || !count_out)
    return MINIAV_ERROR_INVALID_ARG;
  *windows_out = NULL;
  *count_out = 0;

  std::vector<MiniAVDeviceInfo> devices;
  EnumWindowData data = {&devices, GetCurrentProcessId()};

  if (!EnumWindows(WindowEnumProc, reinterpret_cast<LPARAM>(&data))) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: EnumWindows failed: %lu",
               GetLastError());
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!devices.empty()) {
    *windows_out = (MiniAVDeviceInfo *)miniav_calloc(devices.size(),
                                                     sizeof(MiniAVDeviceInfo));
    if (!*windows_out) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to allocate memory for window list.");
      return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    memcpy(*windows_out, devices.data(),
           devices.size() * sizeof(MiniAVDeviceInfo));
    *count_out = static_cast<uint32_t>(devices.size());
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Enumerated %u windows.", *count_out);
  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_configure_capture_item(
    WGCScreenPlatformContext *wgc_ctx, const char *item_id_utf8,
    WGCCaptureTargetType target_type, const MiniAVVideoInfo *format) {
  if (wgc_ctx->is_streaming) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Cannot configure while streaming.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }

  wgc_cleanup_capture_resources(
      wgc_ctx); // Clean up previous item, session, pool

  // Clean up previous audio context if any, before configuring new video item
  if (wgc_ctx->loopback_audio_ctx) {
    MiniAV_Loopback_DestroyContext(wgc_ctx->loopback_audio_ctx);
    wgc_ctx->loopback_audio_ctx = NULL;
    wgc_ctx->audio_loopback_enabled_and_configured = FALSE;
  }

  HMONITOR hmonitor = NULL;
  HWND hwnd = NULL;

  if (target_type == WGC_TARGET_DISPLAY) {
    if (sscanf_s(item_id_utf8, "HMONITOR:0x%p", (void **)&hmonitor) != 1 ||
        !hmonitor) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: Invalid display ID format: %s",
                 item_id_utf8);
      return MINIAV_ERROR_INVALID_ARG;
    }
    wgc_ctx->parent_ctx->is_configured = TRUE;
    wgc_ctx->selected_hmonitor = hmonitor;
    wgc_ctx->selected_hwnd = NULL;
  } else if (target_type == WGC_TARGET_WINDOW) {
    if (sscanf_s(item_id_utf8, "HWND:0x%p", (void **)&hwnd) != 1 || !hwnd ||
        !IsWindow(hwnd)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Invalid window ID format or invalid HWND: %s",
                 item_id_utf8);
      return MINIAV_ERROR_INVALID_ARG;
    }
    wgc_ctx->parent_ctx->is_configured = TRUE;
    wgc_ctx->selected_hwnd = hwnd;
    wgc_ctx->selected_hmonitor = NULL;
  } else {
    return MINIAV_ERROR_INVALID_ARG;
  }

  try {
    auto factory = winrt::get_activation_factory<
        winrt::Windows::Graphics::Capture::GraphicsCaptureItem,
        IGraphicsCaptureItemInterop>();

    if (target_type == WGC_TARGET_DISPLAY) {
      factory->CreateForMonitor(
          hmonitor,
          winrt::guid_of<
              winrt::Windows::Graphics::Capture::GraphicsCaptureItem>(),
          reinterpret_cast<void **>(winrt::put_abi(wgc_ctx->capture_item)));
    } else { // WGC_TARGET_WINDOW
      factory->CreateForWindow(
          hwnd,
          winrt::guid_of<
              winrt::Windows::Graphics::Capture::GraphicsCaptureItem>(),
          reinterpret_cast<void **>(winrt::put_abi(wgc_ctx->capture_item)));
    }

    if (!wgc_ctx->capture_item) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to create GraphicsCaptureItem for %s.",
                 item_id_utf8);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }

    // Store configuration
    wgc_ctx->configured_video_format = *format;
    if (format->frame_rate_denominator > 0 &&
        format->frame_rate_numerator > 0) {
      wgc_ctx->target_fps =
          format->frame_rate_numerator / format->frame_rate_denominator;
    } else {
      wgc_ctx->target_fps = 60;
    }
    if (wgc_ctx->target_fps == 0)
      wgc_ctx->target_fps = 1;

    auto item_size = wgc_ctx->capture_item.Size();
    wgc_ctx->frame_width = static_cast<UINT>(item_size.Width);
    wgc_ctx->frame_height = static_cast<UINT>(item_size.Height);

    // Update parent context's configured format
    wgc_ctx->parent_ctx->configured_video_format.width = wgc_ctx->frame_width;
    wgc_ctx->parent_ctx->configured_video_format.height = wgc_ctx->frame_height;
    wgc_ctx->parent_ctx->configured_video_format.pixel_format =
        wgc_ctx->pixel_format;
    wgc_ctx->parent_ctx->configured_video_format.frame_rate_numerator =
        wgc_ctx->target_fps;
    wgc_ctx->parent_ctx->configured_video_format.frame_rate_denominator = 1;
    wgc_ctx->parent_ctx->configured_video_format.output_preference =
        format->output_preference;

    wgc_ctx->current_target_type = target_type;
    miniav_strlcpy(wgc_ctx->selected_item_id, item_id_utf8,
                   MINIAV_DEVICE_ID_MAX_LEN);

    // --- Configure Audio Loopback (after video item is successfully created)
    // ---
    wgc_ctx->audio_loopback_enabled_and_configured = FALSE; // Default
    if (wgc_ctx->parent_ctx->capture_audio_requested) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC: Audio capture requested. Attempting to configure audio "
                 "loopback.");
      MiniAVResultCode audio_res =
          MiniAV_Loopback_CreateContext(&wgc_ctx->loopback_audio_ctx);
      if (audio_res == MINIAV_SUCCESS) {
        MiniAVAudioInfo desired_audio_format; // Define your desired format
        memset(&desired_audio_format, 0, sizeof(MiniAVAudioInfo));
        desired_audio_format.format = MINIAV_AUDIO_FORMAT_F32;
        desired_audio_format.channels = 2;
        desired_audio_format.sample_rate = 48000;

        const char *audio_target_device_id_str = NULL;
        char process_id_string_buffer[64]; // Buffer for "pid:XXXXX"

        if (target_type == WGC_TARGET_WINDOW && wgc_ctx->selected_hwnd) {
          DWORD process_id = 0;
          GetWindowThreadProcessId(wgc_ctx->selected_hwnd, &process_id);
          if (process_id != 0) {
            miniav_log(
                MINIAV_LOG_LEVEL_DEBUG,
                "WGC: Targeting audio from process PID: %lu for HWND: %p",
                process_id, wgc_ctx->selected_hwnd);
            // Canonical scheme parsed by MiniAV_Loopback_Configure is
            // lowercase "pid:<id>" (same shape as "hwnd:<ptr>"). Emitting
            // "PID:" here against a case-sensitive consumer is what made
            // window-capture-with-audio silently deliver video only.
            snprintf(process_id_string_buffer, sizeof(process_id_string_buffer),
                     wgc_stress_uppercase_pid() ? "PID:%lu" : "pid:%lu",
                     process_id);
            audio_target_device_id_str = process_id_string_buffer;
          } else {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "WGC: Could not get PID for HWND %p. Falling back to "
                       "default system audio loopback.",
                       wgc_ctx->selected_hwnd);
            // audio_target_device_id_str remains NULL for default
          }
        }
        // If not window target, or PID failed, audio_target_device_id_str
        // remains NULL for default system audio

        audio_res = MiniAV_Loopback_Configure(
            wgc_ctx->loopback_audio_ctx,
            audio_target_device_id_str, // Pass NULL for default system audio,
                                        // or "pid:XXXX" for process
            &desired_audio_format);

        if (audio_res == MINIAV_SUCCESS) {
          audio_res = MiniAV_Loopback_GetConfiguredFormat(
              wgc_ctx->loopback_audio_ctx, &wgc_ctx->configured_audio_format);
          if (audio_res == MINIAV_SUCCESS) {
            wgc_ctx->audio_loopback_enabled_and_configured = TRUE;
            miniav_log(
                MINIAV_LOG_LEVEL_INFO,
                "WGC: Audio loopback configured. Format: %d, Ch: %u, Rate: %u",
                wgc_ctx->configured_audio_format.format,
                wgc_ctx->configured_audio_format.channels,
                wgc_ctx->configured_audio_format.sample_rate);
          } else {
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "WGC: Failed to get configured audio format: %s. Audio "
                       "disabled.",
                       MiniAV_GetErrorString(audio_res));
            MiniAV_Loopback_DestroyContext(wgc_ctx->loopback_audio_ctx);
            wgc_ctx->loopback_audio_ctx = NULL;
          }
        } else {
          miniav_log(
              MINIAV_LOG_LEVEL_WARN,
              "WGC: Failed to configure audio loopback: %s. Audio disabled.",
              MiniAV_GetErrorString(audio_res));
          MiniAV_Loopback_DestroyContext(wgc_ctx->loopback_audio_ctx);
          wgc_ctx->loopback_audio_ctx = NULL;
        }
      } else {
        miniav_log(
            MINIAV_LOG_LEVEL_WARN,
            "WGC: Failed to create audio loopback context: %s. Audio disabled.",
            MiniAV_GetErrorString(audio_res));
      }
    } else {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Audio capture not requested.");
    }

    // HONESTY GATE (behaviour change, 0.7.1): audio was EXPLICITLY requested
    // and could not be provided. Returning MINIAV_SUCCESS here is what made
    // "window capture with audio" hand back a video-only capture with nothing
    // but a WARN in the log — the caller had no way to tell a working A/V
    // capture from a silent one. A caller that wants video regardless can
    // simply re-configure with capture_audio = false.
    if (wgc_ctx->parent_ctx->capture_audio_requested &&
        !wgc_ctx->audio_loopback_enabled_and_configured &&
        !wgc_stress_audio_optional()) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: audio capture was requested for %s but no audio "
                 "loopback could be configured — failing the configure "
                 "instead of silently returning a video-only capture.",
                 item_id_utf8);
      if (wgc_ctx->loopback_audio_ctx) {
        MiniAV_Loopback_DestroyContext(wgc_ctx->loopback_audio_ctx);
        wgc_ctx->loopback_audio_ctx = NULL;
      }
      wgc_cleanup_capture_resources(wgc_ctx);
      wgc_ctx->parent_ctx->is_configured = FALSE;
      return MINIAV_ERROR_NOT_SUPPORTED;
    }
    // --- End Audio Loopback Configuration ---

    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "WGC: Configured for item %s. Actual res: %ux%u, Target FPS: "
               "%u, OutputPref: %d, Audio: %s",
               item_id_utf8, wgc_ctx->frame_width, wgc_ctx->frame_height,
               wgc_ctx->target_fps, format->output_preference,
               wgc_ctx->audio_loopback_enabled_and_configured ? "Enabled"
                                                              : "Disabled");

  } catch (winrt::hresult_error const &ex) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Configuration failed for %s: %ls (0x%08X)", item_id_utf8,
               ex.message().c_str(), ex.code().value);
    wgc_cleanup_capture_resources(wgc_ctx);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_configure_display(MiniAVScreenContext *ctx,
                                              const char *display_id_utf8,
                                              const MiniAVVideoInfo *format) {
  if (!ctx || !ctx->platform_ctx || !display_id_utf8 || !format)
    return MINIAV_ERROR_INVALID_ARG;
  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Configuring display ID: %s",
             display_id_utf8);
  return wgc_configure_capture_item(wgc_ctx, display_id_utf8,
                                    WGC_TARGET_DISPLAY, format);
}

static MiniAVResultCode wgc_configure_window(MiniAVScreenContext *ctx,
                                             const char *window_id_utf8,
                                             const MiniAVVideoInfo *format) {
  if (!ctx || !ctx->platform_ctx || !window_id_utf8 || !format)
    return MINIAV_ERROR_INVALID_ARG;
  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Configuring window ID: %s",
             window_id_utf8);
  return wgc_configure_capture_item(wgc_ctx, window_id_utf8, WGC_TARGET_WINDOW,
                                    format);
}

static MiniAVResultCode wgc_configure_region(MiniAVScreenContext *ctx,
                                             const char *display_id_utf8, int x,
                                             int y, int width, int height,
                                             const MiniAVVideoInfo *format) {
  MINIAV_UNUSED(ctx);
  MINIAV_UNUSED(display_id_utf8);
  MINIAV_UNUSED(x);
  MINIAV_UNUSED(y);
  MINIAV_UNUSED(width);
  MINIAV_UNUSED(height);
  MINIAV_UNUSED(format);
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "WGC: ConfigureRegion is not supported. WGC captures full items.");
  return MINIAV_ERROR_NOT_SUPPORTED;
}

static MiniAVResultCode wgc_start_capture(MiniAVScreenContext *ctx,
                                          MiniAVBufferCallback callback,
                                          void *user_data) {
  if (!ctx || !ctx->platform_ctx || !callback)
    return MINIAV_ERROR_INVALID_ARG;
  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;
  MiniAVResultCode res = MINIAV_SUCCESS;

  EnterCriticalSection(&wgc_ctx->critical_section);
  if (wgc_ctx->is_streaming) {
    LeaveCriticalSection(&wgc_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_WARN, "WGC: Capture already started.");
    return MINIAV_ERROR_ALREADY_RUNNING;
  }
  if (!wgc_ctx->capture_item || !wgc_ctx->d3d_device_winrt) {
    LeaveCriticalSection(&wgc_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Not configured or D3D device not ready. Call "
               "ConfigureDisplay/Window first.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  wgc_ctx->app_callback_internal = callback;
  wgc_ctx->app_callback_user_data_internal = user_data;

  // Reset output pacing for this run (see wgc_pump): a grid of slots at the
  // requested rational frame rate, falling back to the integral target_fps.
  {
    LONGLONG num = wgc_ctx->configured_video_format.frame_rate_numerator;
    LONGLONG den = wgc_ctx->configured_video_format.frame_rate_denominator;
    if (num <= 0 || den <= 0) {
      num = wgc_ctx->target_fps ? wgc_ctx->target_fps : 30;
      den = 1;
    }
    LONGLONG a = num, b = den;
    while (b) {
      const LONGLONG r = a % b;
      a = b;
      b = r;
    }
    num /= a;
    den /= a;
    if (num > 100000 || den > 100000) { // keeps the slot arithmetic in range
      num = wgc_ctx->target_fps ? wgc_ctx->target_fps : 30;
      if (num > 100000)
        num = 100000;
      den = 1;
    }
    wgc_ctx->pace_num = num;
    wgc_ctx->pace_den = den;
    wgc_ctx->grid_origin_100ns = -1;
    wgc_ctx->last_slot = -1;
    wgc_ctx->held_slot = -1;
    wgc_ctx->stats = WGCFrameStats{};
    wgc_ctx->pending_pool_w = 0;
    wgc_ctx->pending_pool_h = 0;
    wgc_close_frame(wgc_ctx->held_frame);
    if (!wgc_ctx->pace_wake_timer) {
      wgc_ctx->pace_wake_timer = CreateWaitableTimerExW(
          NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
      if (!wgc_ctx->pace_wake_timer) {
        // Before Windows 10 1803: held frames go out up to a system tick late.
        wgc_ctx->pace_wake_timer = CreateWaitableTimerW(NULL, FALSE, NULL);
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: high-resolution pacing timer unavailable; held "
                   "frames may be delivered up to a system tick late.");
      }
    }
    if (!wgc_ctx->pace_tp_wait && wgc_ctx->pace_wake_timer)
      wgc_ctx->pace_tp_wait =
          CreateThreadpoolWait(wgc_on_pace_wake, wgc_ctx, nullptr);
    if (!wgc_ctx->pace_tp_wait) {
      const DWORD err = GetLastError();
      LeaveCriticalSection(&wgc_ctx->critical_section);
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: could not create the pacing timer (%lu).", err);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }
  // Also update parent context's callback info
  wgc_ctx->parent_ctx->app_callback = callback;
  wgc_ctx->parent_ctx->app_callback_user_data = user_data;

  // --- Start Audio Loopback Capture ---
  if (wgc_ctx->loopback_audio_ctx &&
      wgc_ctx->audio_loopback_enabled_and_configured) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Starting audio loopback capture.");
    res = MiniAV_Loopback_StartCapture(
        wgc_ctx->loopback_audio_ctx,
        wgc_ctx->app_callback_internal, // Use the same callback
        wgc_ctx->app_callback_user_data_internal);
    if (res != MINIAV_SUCCESS) {
      // HONESTY GATE (behaviour change, 0.7.1): audio was configured at the
      // caller's explicit request, so a video-only start is not the capture
      // that was asked for. Video has not been started yet at this point, so
      // bailing out here leaves nothing running.
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to start audio loopback capture: %s. Failing "
                 "StartCapture rather than starting video only.",
                 MiniAV_GetErrorString(res));
      LeaveCriticalSection(&wgc_ctx->critical_section);
      return res;
    } else {
      miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Audio loopback capture started.");
    }
  }
  // --- End Audio Loopback Capture ---

  try {
    // Pixel format for frame pool is typically B8G8R8A8_UNORM
    auto pixel_format_dxgi = winrt::Windows::Graphics::DirectX::
        DirectXPixelFormat::B8G8R8A8UIntNormalized;
    auto item_size = wgc_ctx->capture_item.Size();

    // Create frame pool
    wgc_ctx->frame_pool =
        winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool::
            CreateFreeThreaded(wgc_ctx->d3d_device_winrt, pixel_format_dxgi,
                               WGC_POOL_BUFFERS,
                               item_size);

    if (!wgc_ctx->frame_pool) {
      LeaveCriticalSection(&wgc_ctx->critical_section);
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to create Direct3D11CaptureFramePool.");
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    wgc_ctx->pool_width = static_cast<UINT>(item_size.Width);
    wgc_ctx->pool_height = static_cast<UINT>(item_size.Height);

    // Create session
    wgc_ctx->session =
        wgc_ctx->frame_pool.CreateCaptureSession(wgc_ctx->capture_item);
    if (!wgc_ctx->session) {
      wgc_ctx->frame_pool = nullptr; // Release frame pool
      LeaveCriticalSection(&wgc_ctx->critical_section);
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to create GraphicsCaptureSession.");
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }

    // Cursor capture toggle. GraphicsCaptureSession.IsCursorCaptureEnabled is
    // Win10 2004+ (10.0.19041); on older builds the property is absent, so gate
    // on ApiInformation and wrap in try/catch (belt-and-braces — some SKUs
    // report present but throw). Default parent_ctx->capture_cursor is false, so
    // an unavailable property leaves behavior unchanged (cursor-less).
    {
      bool want_cursor =
          wgc_ctx->parent_ctx && wgc_ctx->parent_ctx->capture_cursor;
      try {
        if (winrt::Windows::Foundation::Metadata::ApiInformation::
                IsPropertyPresent(
                    L"Windows.Graphics.Capture.GraphicsCaptureSession",
                    L"IsCursorCaptureEnabled")) {
          wgc_ctx->session.IsCursorCaptureEnabled(want_cursor);
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "WGC: IsCursorCaptureEnabled set to %s.",
                     want_cursor ? "true" : "false");
        } else if (want_cursor) {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WGC: IsCursorCaptureEnabled unavailable on this Windows "
                     "build (needs 10.0.19041+); capturing cursor-less.");
        }
      } catch (winrt::hresult_error const &ex) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: setting IsCursorCaptureEnabled failed: %ls (0x%08X); "
                   "continuing without the cursor toggle.",
                   ex.message().c_str(), ex.code().value);
      }
    }

    // Have WGC capture at most three frames per output interval
    // (MinUpdateInterval). The pacer keeps one frame per slot, and the
    // compositor copies every frame it captures into the pool: eight copies
    // per frame kept on a 240 Hz display captured at 30 fps. Three keep the
    // frame delivered for a slot within a third of an interval of it. A whole
    // interval would leave slots empty wherever display refreshes and slots
    // drift apart.
    {
      const LONGLONG interval_100ns =
          10000000LL * wgc_ctx->pace_den / wgc_ctx->pace_num;
      winrt::com_ptr<IWgcCaptureSession5> session5 =
          wgc_ctx->session.try_as<IWgcCaptureSession5>();
      if (!session5) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC: MinUpdateInterval unavailable on this Windows build "
                   "(needs 10.0.26100+); capturing at the display's rate.");
      } else {
        const HRESULT hr_interval =
            session5->put_MinUpdateInterval(interval_100ns / 3);
        if (SUCCEEDED(hr_interval))
          miniav_log(MINIAV_LOG_LEVEL_INFO,
                     "WGC: MinUpdateInterval %.2f ms, a third of the %.2f ms "
                     "frame interval.",
                     interval_100ns / 30000.0, interval_100ns / 10000.0);
        else
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WGC: setting MinUpdateInterval failed (0x%08X); "
                     "capturing at the display's rate.",
                     (unsigned)hr_interval);
      }
    }

    wgc_ctx->frame_arrived_token = wgc_ctx->frame_pool.FrameArrived(
        [wgc_ctx_capture = wgc_ctx](auto &&sender, auto &&args) {
          wgc_on_frame_arrived(wgc_ctx_capture, sender, args);
        });

    // Fresh loss-notification guard BEFORE the Closed handler goes live so a
    // closure racing session start cannot be swallowed by a stale flag.
    ResetEvent(wgc_ctx->stop_event_handle);
    wgc_ctx->lost_cb_fired = FALSE;

    // Item closure (captured window closed, display disconnected) is WGC's
    // native capture-lost signal — surface it to the app via lost_cb.
    // Revoke any registration left from a previous start on the same item
    // (stop_capture revokes too; this is belt-and-braces).
    if (wgc_ctx->item_closed_token.value != 0) {
      try {
        wgc_ctx->capture_item.Closed(wgc_ctx->item_closed_token);
      } catch (...) {
      }
      wgc_ctx->item_closed_token.value = 0;
    }
    wgc_ctx->item_closed_token = wgc_ctx->capture_item.Closed(
        [wgc_ctx_capture = wgc_ctx](auto && /*item*/, auto && /*args*/) {
          // Threadpool entry point: hold a callback reference for the whole
          // body so teardown cannot free the context underneath it.
          WGCCallbackRef cb_ref(wgc_ctx_capture);
          if (!cb_ref)
            return; // context already torn down — must not dereference it
          wgc_notify_capture_lost(wgc_ctx_capture, "capture item closed");
        });

    wgc_ctx->is_streaming =
        TRUE; // Set after potential audio start, before WGC session start
    wgc_ctx->session.StartCapture();

  } catch (winrt::hresult_error const &ex) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: StartCapture failed: %ls (0x%08X)",
               ex.message().c_str(), ex.code().value);
    wgc_cleanup_capture_resources(wgc_ctx); // Clean up session, pool, item
    wgc_ctx->is_streaming = FALSE;
    // If audio started successfully but video failed, stop audio
    if (wgc_ctx->loopback_audio_ctx &&
        wgc_ctx->audio_loopback_enabled_and_configured &&
        res == MINIAV_SUCCESS) { // res checks if audio start was ok
      MiniAV_Loopback_StopCapture(wgc_ctx->loopback_audio_ctx);
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "WGC: Stopped audio loopback due to video start failure.");
    }
    LeaveCriticalSection(&wgc_ctx->critical_section);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (wgc_ctx->current_target_type == WGC_TARGET_WINDOW)
    wgc_arm_window_watch_locked(wgc_ctx);
  LeaveCriticalSection(&wgc_ctx->critical_section);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Capture started for item %s.",
             wgc_ctx->selected_item_id);
  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_stop_capture(MiniAVScreenContext *ctx) {
  if (!ctx || !ctx->platform_ctx)
    return MINIAV_ERROR_NOT_INITIALIZED;
  WGCScreenPlatformContext *wgc_ctx =
      (WGCScreenPlatformContext *)ctx->platform_ctx;
  BOOL was_streaming_video = FALSE;

  EnterCriticalSection(&wgc_ctx->critical_section);
  if (!wgc_ctx->is_streaming) { // This flag covers video streaming primarily
    LeaveCriticalSection(&wgc_ctx->critical_section);
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: Video capture not started or already stopped.");
    // Audio might still be running if video failed to start but audio
    // succeeded. However, the public API stop should ideally handle this. For
    // now, if video wasn't streaming, we assume audio also isn't (or shouldn't
    // be).
    return MINIAV_SUCCESS;
  }
  was_streaming_video = wgc_ctx->is_streaming;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Stopping capture for item %s.",
             wgc_ctx->selected_item_id);
  SetEvent(
      wgc_ctx
          ->stop_event_handle);  // Signal any waiting in frame handler to stop
  wgc_ctx->is_streaming = FALSE; // Set video streaming flag early
  wgc_close_frame(wgc_ctx->held_frame); // dropped: the run is over
  wgc_release_copy_fence(wgc_ctx);

  // Unregister event handler and close session/pool for video
  // This needs to happen before releasing wgc_ctx if the lambda captures it.
  try {
    if (wgc_ctx->frame_pool && wgc_ctx->frame_arrived_token.value != 0) {
      wgc_ctx->frame_pool.FrameArrived(wgc_ctx->frame_arrived_token);
      wgc_ctx->frame_arrived_token.value = 0; // Mark as unregistered
    }
    if (wgc_ctx->capture_item && wgc_ctx->item_closed_token.value != 0) {
      // Revoke the Closed handler registered by start_capture; without this a
      // stop/start cycle on the same item stacks registrations.
      try {
        wgc_ctx->capture_item.Closed(wgc_ctx->item_closed_token);
      } catch (...) {
      }
      wgc_ctx->item_closed_token.value = 0;
    }
    if (wgc_ctx->session) {
      wgc_ctx->session.Close(); // This should stop FrameArrived events
      wgc_ctx->session = nullptr;
    }
    if (wgc_ctx->frame_pool) {
      wgc_ctx->frame_pool.Close();
      wgc_ctx->frame_pool = nullptr;
    }
    // capture_item is cleaned up in configure or destroy_platform
  } catch (winrt::hresult_error const &ex) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: Exception during stop_capture resource cleanup: %ls",
               ex.message().c_str());
  }

  LeaveCriticalSection(&wgc_ctx->critical_section);

  // Wait out any FrameArrived/Closed/pacing-timer callback still executing.
  // is_streaming = FALSE is already set above, so one that gets the lock now
  // only hands its frames back. The drain is deliberately AFTER
  // LeaveCriticalSection: an in-flight callback takes the same critical
  // section, so draining under it would deadlock. The pacing wait is closed
  // after it for the same reason; the next start creates a new one.
  wgc_drain_callbacks(wgc_ctx, "stop_capture");
  wgc_close_pace_wake(wgc_ctx);
  wgc_close_window_watch(wgc_ctx);

  // --- Stop Audio Loopback Capture ---
  // Check if audio was successfully configured and we *think* it might have
  // started
  if (wgc_ctx->loopback_audio_ctx &&
      wgc_ctx->audio_loopback_enabled_and_configured && was_streaming_video) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Stopping audio loopback capture.");
    MiniAVResultCode audio_stop_res =
        MiniAV_Loopback_StopCapture(wgc_ctx->loopback_audio_ctx);
    if (audio_stop_res == MINIAV_SUCCESS) {
      miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Audio loopback capture stopped.");
    } else {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WGC: Failed to stop audio loopback capture cleanly: %s",
                 MiniAV_GetErrorString(audio_stop_res));
    }
  }
  // --- End Audio Loopback Capture ---

  miniav_log(MINIAV_LOG_LEVEL_INFO, "WGC: Capture stopped for item %s.",
             wgc_ctx->selected_item_id);
  return MINIAV_SUCCESS;
}

static MiniAVResultCode wgc_release_buffer(MiniAVScreenContext *ctx,
                                           void *internal_handle_ptr) {
  if (ctx && internal_handle_ptr && miniav_wgc_context_is_strict(ctx)) {
    return miniav_wgc_strict_release(miniav_wgc_strict_holder(ctx),
        static_cast<MiniAVNativeBufferInternalPayload *>(internal_handle_ptr));
  }
  MINIAV_UNUSED(
      ctx); // ctx might be useful for logging or D3D context if not in payload

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WGC: release_buffer called with internal_handle_ptr=%p",
             internal_handle_ptr);

  if (!internal_handle_ptr) {
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "WGC: release_buffer called with NULL internal_handle_ptr.");
    return MINIAV_SUCCESS;
  }

  MiniAVNativeBufferInternalPayload *payload =
      (MiniAVNativeBufferInternalPayload *)internal_handle_ptr;

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WGC: payload ptr=%p, handle_type=%d, "
             "native_singular_resource_ptr=%p, num_planar_resources=%u",
             payload, payload->handle_type,
             payload->native_singular_resource_ptr,
             payload->num_planar_resources_to_release);

  if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN) {

    // Handle multi-plane resources (rarely used for WGC, but supported)
    if (payload->num_planar_resources_to_release > 0) {
      for (uint32_t i = 0; i < payload->num_planar_resources_to_release; ++i) {
        if (payload->native_planar_resource_ptrs[i]) {
          // For WGC, this would typically be additional D3D11 textures
          ID3D11Texture2D *texture =
              (ID3D11Texture2D *)payload->native_planar_resource_ptrs[i];
          ULONG ref_count = texture->Release();
          miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                     "WGC: Released planar texture %u. Ref count: %lu", i,
                     ref_count);
          payload->native_planar_resource_ptrs[i] = NULL;
        }
      }
    }

    // Handle single resource (typical case)
    if (payload->native_singular_resource_ptr) {
      WGCFrameReleasePayload *frame_payload =
          (WGCFrameReleasePayload *)payload->native_singular_resource_ptr;

      if (frame_payload) {
        if (frame_payload->original_output_preference ==
                MINIAV_OUTPUT_PREFERENCE_CPU ||
            (frame_payload->cpu_staging_texture_to_unmap_release)) {
          if (frame_payload->d3d_context_for_unmap &&
              frame_payload->cpu_staging_texture_to_unmap_release) {
            frame_payload->d3d_context_for_unmap->Unmap(
                frame_payload->cpu_staging_texture_to_unmap_release,
                frame_payload->subresource_for_unmap);
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "WGC: Unmapped CPU staging texture.");
          }
          if (frame_payload->cpu_staging_texture_to_unmap_release) {
            ULONG ref_count =
                frame_payload->cpu_staging_texture_to_unmap_release->Release();
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "WGC: Released CPU staging texture. Ref count: %lu",
                       ref_count);
          }
          if (frame_payload->d3d_context_for_unmap) {
            frame_payload->d3d_context_for_unmap->Release();
            frame_payload->d3d_context_for_unmap = nullptr;
          }
        } else if (frame_payload->actual_output_preference ==
                   MINIAV_OUTPUT_PREFERENCE_GPU) {
          if (frame_payload->gpu_texture_to_release) {
            ULONG ref_count = frame_payload->gpu_texture_to_release->Release();
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "WGC: Released GPU texture for payload. Ref count: %lu",
                       ref_count);
          }
          // OWNERSHIP: miniav closes the shared NT handle here. The app must
          // have completed its import before calling MiniAV_ReleaseBuffer.
          // Tagged immutable snapshots can remain alive through the consumer's
          // own COM reference; closing the handle does not revoke that import.
          // Leaving this to
          // the app leaked one kernel handle per captured frame — every known
          // caller silently never closed it.
          if (frame_payload->gpu_shared_handle_to_close) {
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "WGC: Closing GPU shared handle %p.",
                       frame_payload->gpu_shared_handle_to_close);
            wgc_close_shared_handle(frame_payload->gpu_shared_handle_to_close);
            frame_payload->gpu_shared_handle_to_close = NULL;
          }
        } else {
          miniav_log(MINIAV_LOG_LEVEL_WARN,
                     "WGC: Unexpected preference (orig=%d actual=%d)",
                     frame_payload->original_output_preference,
                     frame_payload->actual_output_preference);
        }

        miniav_free(frame_payload);
        payload->native_singular_resource_ptr = NULL;
      }
    }

    // Clean up parent buffer
    if (payload->parent_miniav_buffer_ptr) {
      miniav_free(payload->parent_miniav_buffer_ptr);
      payload->parent_miniav_buffer_ptr = NULL;
    }

    miniav_free(payload);
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: Released buffer payload.");
    return MINIAV_SUCCESS;
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: release_buffer called for unknown handle_type %d.",
               payload->handle_type);
    if (payload->parent_miniav_buffer_ptr) {
      miniav_free(payload->parent_miniav_buffer_ptr);
      payload->parent_miniav_buffer_ptr = NULL;
    }
    miniav_free(payload);
    return MINIAV_SUCCESS;
  }
}

// --- D3D and WGC Resource Management ---
static MiniAVResultCode wgc_init_d3d_device(WGCScreenPlatformContext *wgc_ctx) {
  HRESULT hr = S_OK;
  UINT creation_flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef _DEBUG
  // creation_flags |= D3D11_CREATE_DEVICE_DEBUG; // Enable if SDK Layers are
  // installed
#endif
  D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0};
  D3D_FEATURE_LEVEL feature_level;

  winrt::com_ptr<ID3D11Device> device_com;
  winrt::com_ptr<ID3D11DeviceContext> context_com;

  hr = D3D11CreateDevice(
      nullptr, // Specify null to use the default adapter.
      D3D_DRIVER_TYPE_HARDWARE,
      nullptr, // No software rasterizer module.
      creation_flags, feature_levels, ARRAYSIZE(feature_levels),
      D3D11_SDK_VERSION,
      device_com.put(), // Returns the Direct3D device created.
      &feature_level,   // Returns feature level of device created.
      context_com.put() // Returns the device immediate context.
  );

  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: D3D11CreateDevice failed: 0x%X",
               hr);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  wgc_ctx->d3d_device = device_com;
  wgc_ctx->d3d_context = context_com;

  // The immediate context is used from two sides: frames are copied out on the
  // capture callbacks, and CPU frames are unmapped on whichever thread the app
  // releases them from. Have the runtime serialise the two.
  if (auto multithread = context_com.try_as<ID3D11Multithread>()) {
    multithread->SetMultithreadProtected(TRUE);
  } else {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: ID3D11Multithread unavailable; a CPU frame released off "
               "the capture thread is not serialised with capture.");
  }

  // Get the IDirect3DDevice (WinRT type) from the ID3D11Device (COM type)
  try {
    // First, get the IDXGIDevice interface from the ID3D11Device.
    // ID3D11Device inherits from IDXGIDevice.
    winrt::com_ptr<IDXGIDevice> dxgi_device = device_com.as<IDXGIDevice>();
    // If device_com doesn't support IDXGIDevice (which it should), .as<>() will
    // throw.

    // Now, use the interop function to create the WinRT IDirect3DDevice.
    // CreateDirect3DDevice is a free function from
    // <windows.graphics.directx.direct3d11.interop.h>. It expects a raw
    // IInspectable** for the output, which winrt::put_abi provides.
    hr = CreateDirect3D11DeviceFromDXGIDevice(
        dxgi_device.get(), reinterpret_cast<IInspectable **>(
                               winrt::put_abi(wgc_ctx->d3d_device_winrt)));
    if (FAILED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: CreateDirect3DDevice failed: 0x%X", hr);
      // Throw an hresult_error to be caught by the catch block below, ensuring
      // cleanup.
      throw winrt::hresult_error(
          hr, L"CreateDirect3DDevice interop function failed");
    }

    if (!wgc_ctx->d3d_device_winrt) {
      // This case should ideally not be reached if CreateDirect3DDevice
      // succeeded (returned S_OK) and didn't set the output parameter, but it's
      // a safeguard.
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: CreateDirect3DDevice succeeded but resulted in a null "
                 "IDirect3DDevice (WinRT).");
      throw winrt::hresult_error(
          E_FAIL, L"CreateDirect3DDevice resulted in null WinRT device");
    }
  } catch (winrt::hresult_error const &ex) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "WGC: Failed to get IDirect3DDevice from ID3D11Device: %ls (0x%08X)",
        ex.message().c_str(), ex.code().value);
    wgc_cleanup_d3d_device(
        wgc_ctx); // Ensure D3D resources are cleaned up on failure
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WGC: D3D11 device and context initialized.");
  return MINIAV_SUCCESS;
}

static void wgc_cleanup_d3d_device(WGCScreenPlatformContext *wgc_ctx) {
  wgc_release_copy_fence(wgc_ctx);
  if (wgc_ctx->d3d_device_winrt) {
    wgc_ctx->d3d_device_winrt = nullptr;
  }
  if (wgc_ctx->d3d_context) {
    wgc_ctx->d3d_context->ClearState();
    wgc_ctx->d3d_context->Flush();
    wgc_ctx->d3d_context = nullptr; // Releases COM ptr
  }
  if (wgc_ctx->d3d_device) {
    wgc_ctx->d3d_device = nullptr; // Releases COM ptr
  }
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WGC: D3D11 device and context cleaned up.");
}

// Marks the capture as lost and notifies the app exactly once. Fired from the
// GraphicsCaptureItem.Closed event (window closed / display disconnected),
// from the window check (a window that went away without Closed) and from
// device-removed detection in the frame-arrived path — previously WGC
// had no loss notification at all: frames just stopped while the app believed
// capture was still running (unlike DXGI's ACCESS_LOST -> lost_cb handling).
//
// LIFETIME: the caller MUST already hold a WGCCallbackRef (every call site —
// the item Closed lambda, the window check and the device-removed branch of
// wgc_pump, reached from FrameArrived and from the pacing timer — does), so
// the context cannot be freed underneath this. No call site holds the
// critical section, so taking it here is safe.
static void wgc_notify_capture_lost(WGCScreenPlatformContext *wgc_ctx,
                                    const char *why) {
  if (!wgc_ctx || !wgc_ctx_alive(wgc_ctx, "notify_capture_lost"))
    return;
  if (!wgc_ctx->is_streaming) {
    return; // app-initiated stop already in progress — not a loss
  }

  MiniAVContextLostCallback lost_cb = NULL;
  void *lost_cb_user_data = NULL;

  // Shared state (is_streaming, parent_ctx, parent->is_running) is mutated
  // under the same lock stop_capture/destroy_platform use, so a concurrent
  // teardown either wins the is_streaming re-check below or completes first.
  EnterCriticalSection(&wgc_ctx->critical_section);
  if (wgc_ctx->is_streaming && !wgc_ctx->lost_cb_fired.exchange(TRUE)) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "WGC: Capture lost (%s) — notifying app.",
               why);
    wgc_ctx->is_streaming = FALSE;
    SetEvent(wgc_ctx->stop_event_handle);
    MiniAVScreenContext *parent = wgc_ctx->parent_ctx;
    if (parent) {
      parent->is_running = false;
      lost_cb = parent->lost_cb;
      lost_cb_user_data = parent->lost_cb_user_data;
    }
  }
  LeaveCriticalSection(&wgc_ctx->critical_section);

  // Invoke OUTSIDE the critical section: apps commonly call StopCapture or
  // DestroyContext from lost_cb, and both take this lock (and drain — the
  // drain discounts this thread's own in-flight reference, so no self-wait).
  if (lost_cb) {
    lost_cb((int)MINIAV_ERROR_DEVICE_LOST, lost_cb_user_data);
  }
}

static void wgc_cleanup_capture_resources(WGCScreenPlatformContext *wgc_ctx) {
  // Critical section should be held by caller if is_streaming is modified
  // The held frame belongs to the pool closed below. The lock is recursive, so
  // callers that hold it already are fine.
  EnterCriticalSection(&wgc_ctx->critical_section);
  wgc_close_frame(wgc_ctx->held_frame);
  if (wgc_ctx->pace_tp_wait)
    SetThreadpoolWait(wgc_ctx->pace_tp_wait, nullptr, nullptr);
  if (wgc_ctx->pace_wake_timer)
    CancelWaitableTimer(wgc_ctx->pace_wake_timer);
  if (wgc_ctx->window_watch)
    SetThreadpoolTimer(wgc_ctx->window_watch, nullptr, 0, 0);
  LeaveCriticalSection(&wgc_ctx->critical_section);
  if (wgc_ctx->frame_pool && wgc_ctx->frame_arrived_token.value != 0) {
    try {
      wgc_ctx->frame_pool.FrameArrived(wgc_ctx->frame_arrived_token);
    } catch (...) { /* ignore errors during cleanup */
    }
    wgc_ctx->frame_arrived_token.value = 0;
  }
  if (wgc_ctx->capture_item && wgc_ctx->item_closed_token.value != 0) {
    try {
      wgc_ctx->capture_item.Closed(wgc_ctx->item_closed_token);
    } catch (...) { /* ignore errors during cleanup */
    }
    wgc_ctx->item_closed_token.value = 0;
  }
  if (wgc_ctx->session) {
    try {
      wgc_ctx->session.Close();
    } catch (...) {
    }
    wgc_ctx->session = nullptr;
  }
  if (wgc_ctx->frame_pool) {
    try {
      wgc_ctx->frame_pool.Close();
    } catch (...) {
    }
    wgc_ctx->frame_pool = nullptr;
  }
  if (wgc_ctx->capture_item) {
    wgc_ctx->capture_item = nullptr;
  }
  wgc_ctx->current_target_type = WGC_TARGET_NONE;
  wgc_ctx->selected_item_id[0] = '\0';
  miniav_log(
      MINIAV_LOG_LEVEL_DEBUG,
      "WGC: Capture-specific resources (item, pool, session) cleaned up.");
}

// --- Frame delivery ---

// How long the GPU path waits for the copy into a frame's private texture
// before it drops the frame rather than share it unfinished.
#define WGC_COPY_FENCE_TIMEOUT_MS 100u

// Frames dropped because their copy had not completed within
// WGC_COPY_FENCE_TIMEOUT_MS, or could not be waited on at all.
static std::atomic<long> g_wgc_copy_fence_drops{0};

// Waits for the GPU to finish the work queued on the immediate context so far
// (the copy into a frame's private texture). The consumer opens that texture
// on ANOTHER device, which does not wait for work queued on this one. Uses an
// ID3D11Fence where the runtime has one (Windows 10 1703+), an event query
// otherwise. False when the copy is not done within timeout_ms or the device
// is gone. Under critical_section.
static bool wgc_wait_copy_locked(WGCScreenPlatformContext *wgc_ctx,
                                 DWORD timeout_ms) {
  if (!wgc_ctx->copy_fence && !wgc_ctx->copy_fence_unavailable) {
    auto device5 = wgc_ctx->d3d_device.try_as<ID3D11Device5>();
    auto context4 = wgc_ctx->d3d_context.try_as<ID3D11DeviceContext4>();
    winrt::com_ptr<ID3D11Fence> fence;
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (device5 && context4 && event &&
        SUCCEEDED(device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                                       IID_PPV_ARGS(fence.put())))) {
      wgc_ctx->copy_fence = fence;
      wgc_ctx->copy_fence_ctx = context4;
      wgc_ctx->copy_fence_event = event;
      wgc_ctx->copy_fence_value = 0;
    } else {
      if (event)
        CloseHandle(event);
      wgc_ctx->copy_fence_unavailable = true;
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "WGC: ID3D11Fence unavailable; GPU frames wait on an event "
                 "query instead.");
    }
  }

  const ULONGLONG start = GetTickCount64();
  if (wgc_ctx->copy_fence) {
    const UINT64 value = ++wgc_ctx->copy_fence_value;
    if (FAILED(wgc_ctx->copy_fence_ctx->Signal(wgc_ctx->copy_fence.get(),
                                                value)))
      return false;
    wgc_ctx->d3d_context->Flush();
    for (;;) {
      const UINT64 completed = wgc_ctx->copy_fence->GetCompletedValue();
      if (completed == UINT64_MAX)
        return false; // device removed
      if (completed >= value)
        return true;
      const ULONGLONG spent = GetTickCount64() - start;
      if (spent >= timeout_ms ||
          FAILED(wgc_ctx->copy_fence->SetEventOnCompletion(
              value, wgc_ctx->copy_fence_event)))
        return false;
      // The event is auto-reset, and the copy of a frame that timed out
      // earlier can still set it late, so waking up is only a reason to look
      // at the fence again.
      WaitForSingleObject(wgc_ctx->copy_fence_event,
                          (DWORD)(timeout_ms - spent));
    }
  }

  D3D11_QUERY_DESC query_desc{};
  query_desc.Query = D3D11_QUERY_EVENT;
  winrt::com_ptr<ID3D11Query> copy_done;
  if (FAILED(wgc_ctx->d3d_device->CreateQuery(&query_desc, copy_done.put())))
    return false;
  wgc_ctx->d3d_context->End(copy_done.get());
  wgc_ctx->d3d_context->Flush();
  // A copy usually lands within a millisecond: spin that long before sleeping,
  // since one Sleep(1) can last a whole scheduler tick.
  const LONGLONG spin_until = wgc_now_100ns(wgc_ctx) + 10000;
  for (;;) {
    BOOL done = FALSE;
    const HRESULT hr = wgc_ctx->d3d_context->GetData(copy_done.get(), &done,
                                                     sizeof(done), 0);
    if (FAILED(hr))
      return false;
    if (hr == S_OK && done)
      return true;
    if (GetTickCount64() - start >= timeout_ms)
      return false;
    if (wgc_now_100ns(wgc_ctx) < spin_until)
      YieldProcessor();
    else
      Sleep(1);
  }
}

// Builds a MiniAVBuffer from one captured frame, stamped timestamp_100ns, and
// hands it to the app. The caller keeps the frame and closes it. Under
// critical_section, with is_streaming and app_callback_internal checked.
static void wgc_deliver_frame_locked(WGCScreenPlatformContext *wgc_ctx,
                                     WGCFrame const &frame,
                                     LONGLONG timestamp_100ns) {
  MiniAVBuffer *buffer = (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
  if (!buffer) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: Failed to allocate MiniAVBuffer");
    return;
  }

  WGCFrameReleasePayload *frame_payload_app = nullptr;
  MiniAVNativeBufferInternalPayload *internal_payload = nullptr;
  winrt::com_ptr<ID3D11Texture2D> acquired_texture_com = nullptr;
  winrt::com_ptr<ID3D11Texture2D> texture_for_payload_ref_com =
      nullptr; // AddRef'd for payload
  HANDLE shared_handle_for_app = NULL;
  bool processed_as_gpu = false;
  HRESULT hr = S_OK;

  try {
    auto surface = frame.Surface();
    if (!surface) {
      miniav_log(MINIAV_LOG_LEVEL_WARN, "WGC: Frame has no surface.");
      throw winrt::hresult_error(E_FAIL, L"Frame has no surface");
    }
    acquired_texture_com = GetTextureFromDirect3DSurface(surface);
    if (!acquired_texture_com) {
      throw winrt::hresult_error(E_FAIL, L"Failed to get texture from surface");
    }

    // The time of the output slot the frame was chosen for (see wgc_pump), on
    // the QPC clock SystemRelativeTime uses.
    buffer->timestamp_us = static_cast<uint64_t>(timestamp_100ns / 10);

    // The surface handed out by the frame pool is ALWAYS pool-sized;
    // frame.ContentSize() is the live size of the capture target and grows the
    // instant a captured window is resized. Describing the buffer with the raw
    // content size while the bytes come from a pool-sized (and therefore
    // smaller) surface is how data_size_bytes used to run past the end of the
    // mapping. Report what actually exists — the intersection of the two.
    // wgc_take_frame_locked has queued a pool recreate so the following
    // frames carry the full content.
    auto frame_content_size = frame.ContentSize();
    D3D11_TEXTURE2D_DESC frame_tex_desc;
    acquired_texture_com->GetDesc(&frame_tex_desc);

    const uint32_t content_w = static_cast<uint32_t>(frame_content_size.Width);
    const uint32_t content_h = static_cast<uint32_t>(frame_content_size.Height);
    uint32_t report_w = content_w;
    uint32_t report_h = content_h;
    if (!wgc_stress_no_pool_recreate()) {
      if (report_w > frame_tex_desc.Width)
        report_w = frame_tex_desc.Width;
      if (report_h > frame_tex_desc.Height)
        report_h = frame_tex_desc.Height;
    }

    buffer->data.video.info.width = report_w;
    buffer->data.video.info.height = report_h;
    buffer->data.video.info.pixel_format = wgc_ctx->pixel_format; // BGRA32
    buffer->type = MINIAV_BUFFER_TYPE_VIDEO;
    buffer->user_data = wgc_ctx->app_callback_user_data_internal;

    MiniAVOutputPreference desired_output_pref =
        wgc_ctx->configured_video_format.output_preference;

    // --- GPU Path Attempt ---
    if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_GPU &&
        wgc_ctx->d3d_device) {
      D3D11_TEXTURE2D_DESC acquired_desc;
      acquired_texture_com->GetDesc(&acquired_desc);

      // ALWAYS a private copy, even of a surface that happens to be
      // shareable: the pool surface goes back to WGC, which captures into it
      // again, the moment the frame is closed.
      //
      // And a NEW texture every frame, not a reused ring. Releasing the
      // buffer only means the consumer's CPU is done with it: reads it has
      // queued on the GPU can still be pending, and a hardware encoder can be
      // handed the texture itself and read it whenever it gets to it. A ring
      // would rewrite such a texture under the reader, so it needs a fence
      // back from the consumer first.
      D3D11_TEXTURE2D_DESC shareable_desc = acquired_desc;
      shareable_desc.Usage = D3D11_USAGE_DEFAULT;
      shareable_desc.BindFlags =
          D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
      shareable_desc.CPUAccessFlags = 0;
      shareable_desc.MiscFlags =
          D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED;

      winrt::com_ptr<ID3D11Texture2D> shareable_copy_com;
      hr = wgc_ctx->d3d_device->CreateTexture2D(&shareable_desc, nullptr,
                                                shareable_copy_com.put());
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WGC: Failed to create shareable GPU texture copy: 0x%X. "
                   "Fallback to CPU.",
                   hr);
      } else {
        const LONGLONG copy_start = wgc_now_100ns(wgc_ctx);
        wgc_ctx->d3d_context->CopyResource(shareable_copy_com.get(),
                                           acquired_texture_com.get());
        // Share the copy only once it is complete. A copy that is not done in
        // time is dropped; handing it over anyway was a torn or black frame
        // under GPU contention.
        if (!wgc_wait_copy_locked(wgc_ctx, WGC_COPY_FENCE_TIMEOUT_MS)) {
          wgc_ctx->stats.copy_drops++;
          const long drops =
              g_wgc_copy_fence_drops.fetch_add(1, std::memory_order_relaxed) +
              1;
          static ULONGLONG s_last_fence_warn_ms = 0;
          const ULONGLONG now_ms = GetTickCount64();
          if (now_ms - s_last_fence_warn_ms > 2000) {
            s_last_fence_warn_ms = now_ms;
            miniav_log(MINIAV_LOG_LEVEL_WARN,
                       "WGC: frame copy not complete within %u ms — frame "
                       "dropped instead of shared (%ld so far).",
                       WGC_COPY_FENCE_TIMEOUT_MS, drops);
          }
          miniav_free(buffer);
          return;
        }
        wgc_stats_time(wgc_ctx->stats.copies, wgc_ctx->stats.copy_sum_100ns,
                       wgc_ctx->stats.copy_max_100ns,
                       wgc_now_100ns(wgc_ctx) - copy_start);

        winrt::com_ptr<IDXGIResource1> dxgi_resource_to_share;
        hr = shareable_copy_com->QueryInterface(
            IID_PPV_ARGS(dxgi_resource_to_share.put()));
        if (SUCCEEDED(hr)) {
          hr = dxgi_resource_to_share->CreateSharedHandle(
              nullptr, DXGI_SHARED_RESOURCE_READ, nullptr,
              &shared_handle_for_app);
          if (SUCCEEDED(hr) && shared_handle_for_app) {
            texture_for_payload_ref_com =
                wgc_retain_frame_texture(shareable_copy_com);
            processed_as_gpu = true;
            // Counted now; every close below goes through
            // wgc_close_shared_handle() so the +1/-1 stay balanced.
            const long outstanding =
                g_wgc_outstanding_shared_handles.fetch_add(
                    1, std::memory_order_relaxed) +
                1;
            if (outstanding > 256) {
              static ULONGLONG s_last_leak_warn_ms = 0;
              ULONGLONG now_ms = GetTickCount64();
              if (now_ms - s_last_leak_warn_ms > 2000) {
                s_last_leak_warn_ms = now_ms;
                miniav_log(MINIAV_LOG_LEVEL_WARN,
                           "WGC: %ld GPU shared handles outstanding — the app "
                           "is not calling MiniAV_ReleaseBuffer promptly "
                           "(handles are closed on release).",
                           outstanding);
              }
            }
            miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                       "WGC: GPU shared handle %p created from texture %p.",
                       shared_handle_for_app,
                       texture_for_payload_ref_com.get());
          } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR,
                       "WGC: CreateSharedHandle failed: 0x%X. Fallback to CPU.",
                       hr);
            if (shared_handle_for_app) {
              CloseHandle(shared_handle_for_app);
              shared_handle_for_app = NULL;
            }
          }
        } else {
          miniav_log(
              MINIAV_LOG_LEVEL_ERROR,
              "WGC: QI for IDXGIResource1 failed: 0x%X. Fallback to CPU.", hr);
        }
      }
    } // End GPU Path Attempt

    // --- CPU Path (or fallback) ---
    if (!processed_as_gpu) {
      if (desired_output_pref == MINIAV_OUTPUT_PREFERENCE_GPU) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "WGC: GPU path failed or not preferred, using CPU path.");
      }

      D3D11_TEXTURE2D_DESC acquired_desc;
      acquired_texture_com->GetDesc(&acquired_desc);

      D3D11_TEXTURE2D_DESC staging_desc_cpu = acquired_desc;
      staging_desc_cpu.Usage = D3D11_USAGE_STAGING;
      staging_desc_cpu.BindFlags = 0;
      staging_desc_cpu.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
      staging_desc_cpu.MiscFlags =
          0; // Staging textures cannot have MiscFlags like SHARED

      winrt::com_ptr<ID3D11Texture2D> per_frame_staging_texture_com;
      hr = wgc_ctx->d3d_device->CreateTexture2D(
          &staging_desc_cpu, nullptr, per_frame_staging_texture_com.put());
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WGC: Failed to create per-frame CPU staging texture: 0x%X",
                   hr);
        throw winrt::hresult_error(hr, L"Failed to create CPU staging texture");
      }

      const LONGLONG readback_start = wgc_now_100ns(wgc_ctx);
      wgc_ctx->d3d_context->CopyResource(per_frame_staging_texture_com.get(),
                                         acquired_texture_com.get());

      D3D11_MAPPED_SUBRESOURCE mapped_rect_cpu;
      hr = wgc_ctx->d3d_context->Map(per_frame_staging_texture_com.get(), 0,
                                     D3D11_MAP_READ, 0, &mapped_rect_cpu);
      if (FAILED(hr)) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR,
                   "WGC: Failed to map per-frame CPU staging texture: 0x%X",
                   hr);
        throw winrt::hresult_error(hr, L"Failed to map CPU staging texture");
      }
      wgc_stats_time(wgc_ctx->stats.readbacks,
                     wgc_ctx->stats.readback_sum_100ns,
                     wgc_ctx->stats.readback_max_100ns,
                     wgc_now_100ns(wgc_ctx) - readback_start);

      buffer->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;

      // Set up single plane for BGRA32 format
      buffer->data.video.num_planes = 1;
      buffer->data.video.planes[0].data_ptr = mapped_rect_cpu.pData;
      buffer->data.video.planes[0].width = buffer->data.video.info.width;
      buffer->data.video.planes[0].height = buffer->data.video.info.height;
      buffer->data.video.planes[0].stride_bytes = mapped_rect_cpu.RowPitch;
      buffer->data.video.planes[0].offset_bytes = 0;
      buffer->data.video.planes[0].subresource_index = 0;

      buffer->data_size_bytes =
          (size_t)mapped_rect_cpu.RowPitch * buffer->data.video.info.height;

      // Oracle: D3D's own report of what it mapped. Independent of the
      // frame-pool bookkeeping above, so it stays a real check.
      {
        const size_t mapped_bytes =
            (size_t)mapped_rect_cpu.RowPitch * acquired_desc.Height;
        if (buffer->data_size_bytes > mapped_bytes) {
          const long n = g_wgc_oversize_reports.fetch_add(
                             1, std::memory_order_relaxed) +
                         1;
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WGC-OVERSIZE: CPU buffer advertised %zu bytes but only "
                     "%zu are mapped (content %ux%u, surface %ux%u, pitch %u; "
                     "hit #%ld).",
                     buffer->data_size_bytes, mapped_bytes, content_w,
                     content_h, acquired_desc.Width, acquired_desc.Height,
                     mapped_rect_cpu.RowPitch, n);
        }
      }
      texture_for_payload_ref_com = per_frame_staging_texture_com;
    } else { // GPU Path successful
      // buffer->native_fence stays zeroed: the copy into this texture had
      // COMPLETED (wgc_wait_copy_locked) before its handle was created, so
      // the consumer has nothing left to wait for. The ready tag below says
      // exactly that.
      buffer->content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE;

      // Set up single plane for GPU texture
      buffer->data.video.num_planes = 1;
      buffer->data.video.planes[0].data_ptr = (void *)shared_handle_for_app;
      buffer->data.video.planes[0].width = buffer->data.video.info.width;
      buffer->data.video.planes[0].height = buffer->data.video.info.height;
      buffer->data.video.planes[0].stride_bytes =
          0; // GPU textures don't have stride
      buffer->data.video.planes[0].offset_bytes = 0;
      buffer->data.video.planes[0].subresource_index = 0;
      buffer->data.video.planes[0].drm_format_modifier =
          wgc_frame_import_tag(true, S_OK);
      // calculate data size based on width, height, and pixel format
      buffer->data_size_bytes =
          ((size_t)buffer->data.video.info.width *
           buffer->data.video.info.height * 4); // BGRA32 = 4 bytes per pixel

      // Same oracle as the CPU path: the shared texture is a same-desc copy
      // of the pool-sized surface, so its extent bounds what the consumer can
      // legally read.
      {
        const size_t texture_bytes =
            (size_t)frame_tex_desc.Width * frame_tex_desc.Height * 4;
        if (buffer->data_size_bytes > texture_bytes) {
          const long n = g_wgc_oversize_reports.fetch_add(
                             1, std::memory_order_relaxed) +
                         1;
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WGC-OVERSIZE: GPU buffer advertised %zu bytes but the "
                     "shared texture is %ux%u (%zu bytes) (content %ux%u; hit "
                     "#%ld).",
                     buffer->data_size_bytes, frame_tex_desc.Width,
                     frame_tex_desc.Height, texture_bytes, content_w, content_h,
                     n);
        }
      }
    }

    // --- Prepare Payloads and Call App ---
    frame_payload_app = (WGCFrameReleasePayload *)miniav_calloc(
        1, sizeof(WGCFrameReleasePayload));
    internal_payload = (MiniAVNativeBufferInternalPayload *)miniav_calloc(
        1, sizeof(MiniAVNativeBufferInternalPayload));

    if (!frame_payload_app || !internal_payload) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "WGC: Failed to allocate payload structures.");
      throw winrt::hresult_error(E_OUTOFMEMORY, L"Payload allocation failed");
    }

    frame_payload_app->original_output_preference = desired_output_pref;
    if (processed_as_gpu) {
      frame_payload_app->actual_output_preference =
          MINIAV_OUTPUT_PREFERENCE_GPU;
      frame_payload_app->gpu_texture_to_release =
          texture_for_payload_ref_com.detach();
      frame_payload_app->gpu_shared_handle_to_close = shared_handle_for_app;
    } else {
      frame_payload_app->actual_output_preference =
          MINIAV_OUTPUT_PREFERENCE_CPU;
      frame_payload_app->cpu_staging_texture_to_unmap_release =
          texture_for_payload_ref_com.detach();
      frame_payload_app->d3d_context_for_unmap = wgc_ctx->d3d_context.get();
      if (frame_payload_app->d3d_context_for_unmap) {
        frame_payload_app->d3d_context_for_unmap->AddRef();
      }
      frame_payload_app->subresource_for_unmap = 0;
    }

    internal_payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
    internal_payload->context_owner = wgc_ctx->parent_ctx;
    internal_payload->native_singular_resource_ptr = frame_payload_app;
    internal_payload->num_planar_resources_to_release = 0;
    internal_payload->parent_miniav_buffer_ptr =
        buffer; // Store heap-allocated buffer
    buffer->internal_handle = internal_payload;

    // Callback is already checked and wgc_ctx is valid under critical section.
    // MINIAV_SAFE_DISPATCH acquires a shared read lock so MiniAV_Dispose() can
    // atomically quiesce in-flight callbacks before NativeCallables are closed.
    MINIAV_SAFE_DISPATCH(wgc_ctx->app_callback_internal(
        buffer, wgc_ctx->app_callback_user_data_internal));
    // App now owns buffer.internal_handle and its payload, and
    // gpu_shared_handle_for_app if provided. App must call
    // MiniAV_ReleaseBuffer.

  } catch (winrt::hresult_error const &ex) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Error delivering a frame: %ls (0x%08X)",
               ex.message().c_str(), ex.code().value);
    // Cleanup partially created resources
    if (shared_handle_for_app) // From GPU path attempt (counted at creation)
      wgc_close_shared_handle(shared_handle_for_app);

    if (frame_payload_app) {
      // Release any D3D textures held by the payload before freeing the struct
      if (frame_payload_app->cpu_staging_texture_to_unmap_release) {
        frame_payload_app->cpu_staging_texture_to_unmap_release->Release();
        frame_payload_app->cpu_staging_texture_to_unmap_release = nullptr;
      }
      if (frame_payload_app->gpu_texture_to_release) { // Should be null if CPU
                                                       // path was taken
        frame_payload_app->gpu_texture_to_release->Release();
        frame_payload_app->gpu_texture_to_release = nullptr;
      }
      miniav_free(frame_payload_app);
      frame_payload_app = nullptr; // Avoid double free if another catch happens
    }

    // If texture_for_payload_ref_com still holds a reference (i.e., not
    // detached yet)
    if (texture_for_payload_ref_com) {
      texture_for_payload_ref_com = nullptr; // com_ptr releases it
    }

    if (internal_payload) {
      miniav_free(internal_payload);
      internal_payload = nullptr;
    }

    // Clean up heap-allocated buffer
    if (buffer) {
      miniav_free(buffer);
      buffer = nullptr;
    }
  } catch (...) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Unknown error delivering a frame.");
    if (shared_handle_for_app)
      wgc_close_shared_handle(shared_handle_for_app);

    if (frame_payload_app) {
      if (frame_payload_app->cpu_staging_texture_to_unmap_release) {
        frame_payload_app->cpu_staging_texture_to_unmap_release->Release();
        frame_payload_app->cpu_staging_texture_to_unmap_release = nullptr;
      }
      if (frame_payload_app->gpu_texture_to_release) {
        frame_payload_app->gpu_texture_to_release->Release();
        frame_payload_app->gpu_texture_to_release = nullptr;
      }
      miniav_free(frame_payload_app);
      frame_payload_app = nullptr;
    }

    if (texture_for_payload_ref_com) {
      texture_for_payload_ref_com = nullptr;
    }
    if (internal_payload) {
      miniav_free(internal_payload);
      internal_payload = nullptr;
    }

    if (buffer) {
      miniav_free(buffer);
      buffer = nullptr;
    }
  }
}

// Delivers the held frame, stamped with its slot's time. Under
// critical_section.
static void wgc_deliver_held_locked(WGCScreenPlatformContext *wgc_ctx) {
  WGCFrameStats &stats = wgc_ctx->stats;
  const LONGLONG offset = wgc_ctx->held_captured_100ns -
                          wgc_slot_time(wgc_ctx, wgc_ctx->held_slot);
  if (stats.filled == 0 || offset < stats.offset_min_100ns)
    stats.offset_min_100ns = offset;
  if (stats.filled == 0 || offset > stats.offset_max_100ns)
    stats.offset_max_100ns = offset;
  stats.filled++;
  WGCFrame frame{std::move(wgc_ctx->held_frame)};
  wgc_ctx->held_frame = nullptr;
  wgc_ctx->last_slot = wgc_ctx->held_slot;
  wgc_deliver_frame_locked(wgc_ctx, frame,
                           wgc_slot_time(wgc_ctx, wgc_ctx->held_slot));
  wgc_close_frame(frame);
}

// Files one frame taken from the pool under its output slot: the slot nearest
// its capture time, and never one already delivered. A newer frame for the
// held frame's slot replaces it. A frame for a later slot was captured after
// the held one's window closed, so the held one is delivered first. Under
// critical_section.
static void wgc_take_frame_locked(WGCScreenPlatformContext *wgc_ctx,
                                  WGCFrame &frame, LONGLONG arrived) {
  wgc_ctx->stats.taken++;
  LONGLONG captured = arrived;
  try {
    captured = frame.SystemRelativeTime().count();
    const auto size = frame.ContentSize();
    if (size.Width > 0 && size.Height > 0 &&
        (static_cast<UINT>(size.Width) != wgc_ctx->pool_width ||
         static_cast<UINT>(size.Height) != wgc_ctx->pool_height)) {
      wgc_ctx->pending_pool_w = static_cast<UINT>(size.Width);
      wgc_ctx->pending_pool_h = static_cast<UINT>(size.Height);
    }
  } catch (...) {
  }
  // SystemRelativeTime is QPC time. A frame stamped in the future, or more
  // than a second before it was taken, is placed by its arrival instead.
  if (captured > arrived + 100000 || arrived - captured > 10000000)
    captured = arrived;

  if (wgc_ctx->grid_origin_100ns < 0)
    wgc_ctx->grid_origin_100ns = captured;
  LONGLONG slot = wgc_slot_of(wgc_ctx, captured);
  if (slot <= wgc_ctx->last_slot)
    slot = wgc_ctx->last_slot + 1;

  if (wgc_ctx->held_frame) {
    if (slot <= wgc_ctx->held_slot) {
      wgc_close_frame(wgc_ctx->held_frame); // superseded within its slot
      slot = wgc_ctx->held_slot;
    } else {
      wgc_deliver_held_locked(wgc_ctx);
    }
  }
  wgc_ctx->held_frame = std::move(frame);
  frame = nullptr;
  wgc_ctx->held_slot = slot;
  wgc_ctx->held_captured_100ns = captured;
}

// Logs the period's WGCFrameStats once WGC_STATS_PERIOD_100NS has passed and
// starts the next. The frames taken from the pool per slot filled show what
// MinUpdateInterval saves; the offset range, how far the delivered pictures
// sit from their slots. Under critical_section.
#define WGC_STATS_PERIOD_100NS (10 * 10000000LL)
static void wgc_log_stats_locked(WGCScreenPlatformContext *wgc_ctx) {
  WGCFrameStats &s = wgc_ctx->stats;
  const LONGLONG now = wgc_now_100ns(wgc_ctx);
  if (s.start_100ns == 0) {
    s.start_100ns = now;
    return;
  }
  if (now - s.start_100ns < WGC_STATS_PERIOD_100NS)
    return;
  char offsets[64] = "", copy[96] = "", readback[80] = "";
  if (s.filled)
    snprintf(offsets, sizeof(offsets), "; capture-to-slot %+.1f..%+.1f ms",
             s.offset_min_100ns / 10000.0, s.offset_max_100ns / 10000.0);
  if (s.copies || s.copy_drops)
    snprintf(copy, sizeof(copy),
             "; GPU copy mean %.2f max %.2f ms (%u done, %u dropped)",
             s.copies ? s.copy_sum_100ns / 10000.0 / s.copies : 0.0,
             s.copy_max_100ns / 10000.0, s.copies, s.copy_drops);
  if (s.readbacks)
    snprintf(readback, sizeof(readback),
             "; CPU readback mean %.2f max %.2f ms (%u)",
             s.readback_sum_100ns / 10000.0 / s.readbacks,
             s.readback_max_100ns / 10000.0, s.readbacks);
  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "WGC: last %.1f s at %lld/%lld fps: %u frames from the pool for "
             "%u slots%s%s%s.",
             (now - s.start_100ns) / 1e7, wgc_ctx->pace_num, wgc_ctx->pace_den,
             s.taken, s.filled, offsets, copy, readback);
  s = WGCFrameStats{};
  s.start_100ns = now;
}

// --- Track content resizes ---
// The pool was sized once from capture_item.Size() at StartCapture and never
// revisited, so growing a captured window left every later frame arriving on
// an undersized surface while frame.ContentSize() reported the new, larger
// size. Direct3D11CaptureFramePool::Recreate is the documented remedy and is
// safe to call from the FrameArrived handler. wgc_pump calls this with no
// frame from the pool open: it delivers the held frame first.
//
// LOCKING: under the context's critical section, which is the same lock
// wgc_stop_capture holds while it calls frame_pool.Close(). That makes "pool
// is being closed" and "pool is being recreated" mutually exclusive, and
// wgc_pump checked is_streaming under it, so a stop that won the race has
// already turned this into a no-op.
static void wgc_recreate_pool_locked(WGCScreenPlatformContext *wgc_ctx) {
  const UINT w = wgc_ctx->pending_pool_w;
  const UINT h = wgc_ctx->pending_pool_h;
  wgc_ctx->pending_pool_w = 0;
  wgc_ctx->pending_pool_h = 0;
  if (!wgc_ctx->frame_pool || !wgc_ctx->d3d_device_winrt ||
      (wgc_ctx->pool_width == w && wgc_ctx->pool_height == h))
    return;
  try {
    winrt::Windows::Graphics::SizeInt32 new_size{static_cast<int32_t>(w),
                                                 static_cast<int32_t>(h)};
    wgc_ctx->frame_pool.Recreate(
        wgc_ctx->d3d_device_winrt,
        winrt::Windows::Graphics::DirectX::DirectXPixelFormat::
            B8G8R8A8UIntNormalized,
        WGC_POOL_BUFFERS, new_size);
    miniav_log(MINIAV_LOG_LEVEL_INFO,
               "WGC: capture content resized %ux%u -> %ux%u; frame pool "
               "recreated.",
               wgc_ctx->pool_width, wgc_ctx->pool_height, w, h);
    wgc_ctx->pool_width = w;
    wgc_ctx->pool_height = h;
    g_wgc_pool_recreates.fetch_add(1, std::memory_order_relaxed);
  } catch (winrt::hresult_error const &ex) {
    // RO_E_CLOSED here just means teardown got the pool first.
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: frame pool Recreate to %ux%u failed: %ls (0x%08X); "
               "continuing at the old pool size.",
               w, h, ex.message().c_str(), ex.code().value);
  } catch (...) {
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "WGC: frame pool Recreate to %ux%u failed (unknown).", w, h);
  }
}

// Takes every frame waiting in the pool, keeps the newest one per output slot,
// and delivers each held frame once its slot's window has closed, stamped with
// the slot's time. A 60 Hz compose stream recorded at 30 fps therefore comes
// out on an even 33.3 ms grid, carrying the newest picture of each slot.
//
// This replaces sleeping out the interval on the callback thread. While that
// thread slept, WGC kept capturing into the pool, so the frame delivered next
// was the OLDEST queued one, captured up to an interval before its delivery
// and stamped with that capture time. The consumer's own rate limiter then
// threw away the newer frame queued behind it, and on a screen that had just
// stopped changing that newer frame was the last picture there would be.
// Holding means nothing ever blocks and nothing newer is lost.
//
// Runs on WGC's FrameArrived thread and on the pacing timer's. Both hold a
// WGCCallbackRef and serialise on the critical section, which is held
// throughout, across the app callback too, as delivery always was.
static void wgc_pump(WGCScreenPlatformContext *wgc_ctx) {
  EnterCriticalSection(&wgc_ctx->critical_section);
  if (!wgc_ctx->is_streaming || !wgc_ctx->frame_pool ||
      !wgc_ctx->app_callback_internal) {
    // Stopping, stopped or lost: hand everything back to the pool.
    wgc_close_frame(wgc_ctx->held_frame);
    if (wgc_ctx->frame_pool) {
      try {
        for (WGCFrame stale = wgc_ctx->frame_pool.TryGetNextFrame(); stale;
             stale = wgc_ctx->frame_pool.TryGetNextFrame())
          stale.Close();
      } catch (...) {
      }
    }
    LeaveCriticalSection(&wgc_ctx->critical_section);
    return;
  }

  const char *lost_why = nullptr;
  const LONGLONG arrived = wgc_now_100ns(wgc_ctx);
  for (;;) {
    WGCFrame frame{nullptr};
    try {
      frame = wgc_ctx->frame_pool.TryGetNextFrame();
    } catch (winrt::hresult_error const &ex) {
      miniav_log(MINIAV_LOG_LEVEL_WARN, "WGC: TryGetNextFrame failed: %ls",
                 ex.message().c_str());
      // Distinguish transient hiccups from a genuinely lost capture: a removed
      // D3D device or a closed session/pool will never produce frames again —
      // tell the app instead of leaving it waiting forever.
      HRESULT removed_reason =
          wgc_ctx->d3d_device ? wgc_ctx->d3d_device->GetDeviceRemovedReason()
                              : S_OK;
      if (removed_reason != S_OK ||
          ex.code() == static_cast<winrt::hresult>(DXGI_ERROR_DEVICE_REMOVED) ||
          ex.code() == static_cast<winrt::hresult>(RO_E_CLOSED)) {
        lost_why = "device removed / session closed";
      }
      break;
    }
    if (!frame)
      break;
    wgc_take_frame_locked(wgc_ctx, frame, arrived);
  }

  // The pool must not be recreated while a frame from it is held, so a resize
  // delivers the held frame early. It carries its slot's time either way.
  const bool resize = !lost_why && wgc_ctx->pending_pool_w &&
                      wgc_ctx->pending_pool_h &&
                      !wgc_stress_no_pool_recreate();
  if (wgc_ctx->held_frame && !lost_why) {
    const LONGLONG due = wgc_slot_due(wgc_ctx, wgc_ctx->held_slot);
    const LONGLONG now = wgc_now_100ns(wgc_ctx);
    if (resize || now >= due ||
        !wgc_arm_pace_wake_locked(wgc_ctx, due - now))
      wgc_deliver_held_locked(wgc_ctx);
  }
  if (resize)
    wgc_recreate_pool_locked(wgc_ctx);
  wgc_log_stats_locked(wgc_ctx);

  const DWORD park_ms =
      wgc_stress_force_pace_sleep()
          ? (DWORD)(1000 * wgc_ctx->pace_den / wgc_ctx->pace_num)
          : 0;
  LeaveCriticalSection(&wgc_ctx->critical_section);

  if (park_ms) {
    // MINIAV_WGC_STRESS_PACE_SLEEP=1 (test-only): park outside the lock,
    // blind to teardown, the way the pacing wait this replaced did.
    Sleep(park_ms);
    if (!wgc_ctx_alive(wgc_ctx, "pacing park"))
      return;
  }
  // Last: the app may stop or destroy the capture from lost_cb.
  if (lost_why)
    wgc_notify_capture_lost(wgc_ctx, lost_why);
}

// Threadpool entry point for the pacing timer, which delivers a held frame
// whose slot closed without a newer frame arriving to do it.
static VOID CALLBACK wgc_on_pace_wake(PTP_CALLBACK_INSTANCE /*instance*/,
                                      PVOID param, PTP_WAIT /*wait*/,
                                      TP_WAIT_RESULT /*result*/) {
  WGCScreenPlatformContext *wgc_ctx =
      static_cast<WGCScreenPlatformContext *>(param);
  WGCCallbackRef cb_ref(wgc_ctx);
  if (!cb_ref)
    return; // context already torn down — must not dereference it
  if (!wgc_ctx_alive(wgc_ctx, "pace timer"))
    return;
  wgc_pump(wgc_ctx);
}

// Threadpool entry point for the window check (see
// wgc_arm_window_watch_locked). Ends the capture as lost once the window is
// gone or its handle names a different window; stops checking once the
// capture has ended.
static VOID CALLBACK wgc_on_window_watch(PTP_CALLBACK_INSTANCE /*instance*/,
                                         PVOID param, PTP_TIMER /*timer*/) {
  WGCScreenPlatformContext *wgc_ctx =
      static_cast<WGCScreenPlatformContext *>(param);
  WGCCallbackRef cb_ref(wgc_ctx);
  if (!cb_ref)
    return; // context already torn down — must not dereference it
  if (!wgc_ctx_alive(wgc_ctx, "window check"))
    return;
  EnterCriticalSection(&wgc_ctx->critical_section);
  const bool streaming = wgc_ctx->is_streaming &&
                         wgc_ctx->current_target_type == WGC_TARGET_WINDOW;
  const HWND hwnd = wgc_ctx->selected_hwnd;
  const DWORD tid = wgc_ctx->watched_tid;
  const DWORD pid = wgc_ctx->watched_pid;
  if (!streaming && wgc_ctx->window_watch)
    SetThreadpoolTimer(wgc_ctx->window_watch, nullptr, 0, 0);
  LeaveCriticalSection(&wgc_ctx->critical_section);
  if (!streaming)
    return;
  DWORD now_pid = 0;
  const DWORD now_tid =
      IsWindow(hwnd) ? GetWindowThreadProcessId(hwnd, &now_pid) : 0;
  if (now_tid == 0 || now_tid != tid || now_pid != pid)
    wgc_notify_capture_lost(wgc_ctx, "captured window closed");
}

// --- Frame Arrived Handler ---
static void wgc_on_frame_arrived(
    WGCScreenPlatformContext *wgc_ctx,
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool const &sender,
    winrt::Windows::Foundation::IInspectable const & /*args*/) {
  // Threadpool entry point: the reference is held for the entire body.
  WGCCallbackRef cb_ref(wgc_ctx);
  if (!cb_ref) {
    // Context already sealed/destroyed: do NOT dereference wgc_ctx. Still
    // drain the pool frame (touches only `sender`) so it is not held hostage.
    if (sender) {
      try {
        auto frame = sender.TryGetNextFrame();
        if (frame)
          frame.Close();
      } catch (...) {
      }
    }
    return;
  }
  if (!wgc_ctx_alive(wgc_ctx, "on_frame_arrived"))
    return;
  wgc_pump(wgc_ctx);
}

// --- Ops struct and Platform Init ---
const ScreenContextInternalOps g_screen_ops_win_wgc = {
    wgc_init_platform,
    wgc_destroy_platform,
    wgc_enumerate_displays,
    wgc_enumerate_windows,
    wgc_configure_display,
    wgc_configure_window,
    wgc_configure_region, // Not supported
    wgc_start_capture,
    wgc_stop_capture,
    wgc_release_buffer,
    wgc_get_default_formats,
    wgc_get_configured_video_formats};

MiniAVResultCode
miniav_screen_context_platform_init_windows_wgc(MiniAVScreenContext *ctx) {
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;

  // Check if WGC is supported on this system
  if (!winrt::Windows::Graphics::Capture::GraphicsCaptureSession::
          IsSupported()) {
    miniav_log(
        MINIAV_LOG_LEVEL_ERROR,
        "WGC: Windows Graphics Capture is not supported on this system.");
    return MINIAV_ERROR_NOT_SUPPORTED;
  }

  ctx->ops = &g_screen_ops_win_wgc;
  miniav_log(MINIAV_LOG_LEVEL_DEBUG,
             "WGC: Assigned Windows Graphics Capture screen ops.");
  // The caller (e.g., MiniAV_Screen_CreateContext) will call
  // ctx->ops->init_platform()
  return MINIAV_SUCCESS;
}
