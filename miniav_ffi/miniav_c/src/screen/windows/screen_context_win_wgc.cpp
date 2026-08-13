// IMPORTANT: This file should be compiled as C++

#include "screen_context_win_wgc.h"
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

void shutdown_winrt_for_wgc() {
  std::lock_guard<std::mutex> lock(g_wgc_init_mutex);
  g_wgc_init_count--;
  if (g_wgc_init_count == 0) {
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
typedef enum WGCCaptureTargetType {
  WGC_TARGET_NONE,
  WGC_TARGET_DISPLAY,
  WGC_TARGET_WINDOW
} WGCCaptureTargetType;

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

typedef struct WGCScreenPlatformContext {
  volatile ULONG ctx_magic; // WGC_CTX_MAGIC_LIVE while the context is usable
  MiniAVScreenContext *parent_ctx;

  winrt::com_ptr<ID3D11Device> d3d_device;
  winrt::com_ptr<ID3D11DeviceContext> d3d_context;
  winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice
      d3d_device_winrt{nullptr};

  winrt::Windows::Graphics::Capture::GraphicsCaptureItem capture_item{nullptr};
  winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool frame_pool{
      nullptr};
  winrt::Windows::Graphics::Capture::GraphicsCaptureSession session{nullptr};
  winrt::event_token frame_arrived_token{};
  winrt::event_token item_closed_token{};
  // One-shot guard so a lost-capture cascade (item closed + device removed +
  // failing TryGetNextFrame) fires lost_cb exactly once per capture run.
  std::atomic<BOOL> lost_cb_fired{FALSE};

  MiniAVBufferCallback app_callback_internal;
  void *app_callback_user_data_internal;

  std::atomic<BOOL> is_streaming;
  // Number of WinRT threadpool callbacks (FrameArrived / item Closed)
  // currently executing against this context. Teardown drains this to zero
  // before closing handles or freeing — see the "callback lifetime protocol"
  // block below wgc_ctx_alive().
  std::atomic<long> callbacks_in_flight;
  HANDLE stop_event_handle;          // Manual reset event
  CRITICAL_SECTION critical_section; // To protect shared members like callback
                                     // and streaming state

  MiniAVVideoInfo
      configured_video_format; // User's request (FPS, output_preference)
  UINT target_fps;
  UINT frame_width;
  UINT frame_height;
  // Size the Direct3D11CaptureFramePool was last created/recreated at. The
  // pool's surfaces are ALWAYS this size; frame.ContentSize() is the live
  // target size and drifts away from it the moment a captured window is
  // resized. Tracking it is what lets wgc_on_frame_arrived notice the drift
  // and call Direct3D11CaptureFramePool::Recreate. Written under
  // critical_section.
  UINT pool_width;
  UINT pool_height;
  MiniAVPixelFormat pixel_format; // Typically BGRA32

  LARGE_INTEGER qpc_frequency;

  // FPS pacing state (see the tail of wgc_on_frame_arrived): deliveries are
  // paced against an absolute QPC schedule slept on a high-resolution
  // waitable timer.
  LONGLONG pace_interval_qpc;
  LONGLONG pace_next_deadline_qpc;
  HANDLE pace_timer;

  WGCCaptureTargetType current_target_type;
  char selected_item_id[MINIAV_DEVICE_ID_MAX_LEN]; // e.g., "HMONITOR:0x1234" or
                                                   // "HWND:0x5678"
  HWND selected_hwnd;                              // If window capture
  HMONITOR selected_hmonitor;                      // If display capture

  // --- Audio Loopback Members ---
  MiniAVLoopbackContextHandle loopback_audio_ctx;
  BOOL audio_loopback_enabled_and_configured;
  MiniAVAudioInfo configured_audio_format; // Actual format from loopback

} WGCScreenPlatformContext;

// ===========================================================================
// Threadpool-callback lifetime protocol
// ===========================================================================
// WinRT dispatches FrameArrived and GraphicsCaptureItem.Closed on threadpool
// threads. Revoking an event token does NOT wait for a handler that is already
// running, and wgc_on_frame_arrived deliberately BLOCKS for up to a frame
// interval in its FPS pacing loop *after* releasing the critical section. So
// the owner thread could previously CloseHandle(pace_timer /
// stop_event_handle), DeleteCriticalSection() and miniav_free() the context
// while a callback thread was still reading it and waiting on those handles.
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
//   * An in-flight wgc_on_frame_arrived can block on (a) the context's
//     critical section, (b) g_wgc_live_mutex, (c) the pacing wait.
//   * The drain is therefore always performed with the critical section NOT
//     held. Draining under it would block the very handler we are waiting for
//     in EnterCriticalSection — a guaranteed hang.
//   * g_wgc_live_mutex is a leaf: it is never held while acquiring the
//     critical section, while calling into WinRT/D3D, or while draining. The
//     acquire/release helpers take it only around a vector scan and one atomic.
//   * The pacing wait cannot outlast the drain because teardown sets
//     is_streaming = FALSE and SetEvent(stop_event_handle) *before* draining,
//     and every branch of the pacing loop either tests is_streaming or waits
//     on stop_event_handle (including the no-waitable-timer fallback).
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
//                                 callback drain in stop/destroy, and the
//                                 pacing loop's no-timer fallback goes back to
//                                 a bare stop-event-blind Sleep().
//  MINIAV_WGC_STRESS_PACE_SLEEP=1 force the pacing loop down that no-timer
//                                 fallback (normally only reached when the
//                                 waitable timer could not be created or
//                                 armed). Together the two reproduce the
//                                 original wide use-after-free window.
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
                 "WGC: MINIAV_WGC_STRESS_PACE_SLEEP=1 — pacing loop forced onto "
                 "the no-waitable-timer fallback (test-only).");
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

  MiniAVResultCode res = init_winrt_for_wgc();
  if (res != MINIAV_SUCCESS)
    return res;

  WGCScreenPlatformContext *wgc_ctx = (WGCScreenPlatformContext *)miniav_calloc(
      1, sizeof(WGCScreenPlatformContext));
  if (!wgc_ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Failed to allocate WGCScreenPlatformContext.");
    shutdown_winrt_for_wgc();
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->platform_ctx = wgc_ctx;
  // NOTE: miniav_calloc gives raw zeroed memory — the struct's in-class member
  // initializers never run, so anything needing a non-zero initial value must
  // be assigned here explicitly.
  wgc_ctx->ctx_magic = WGC_CTX_MAGIC_LIVE;
  wgc_ctx->callbacks_in_flight = 0;
  wgc_ctx->parent_ctx = ctx;
  wgc_ctx->pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // WGC default
  wgc_ctx->is_streaming = FALSE;
  wgc_ctx->qpc_frequency = miniav_get_qpc_frequency();
  wgc_ctx->loopback_audio_ctx = NULL; // Initialize audio loopback members
  wgc_ctx->audio_loopback_enabled_and_configured = FALSE;

  wgc_ctx->stop_event_handle =
      CreateEvent(NULL, TRUE, FALSE, NULL); // Manual-reset, non-signaled
  if (wgc_ctx->stop_event_handle == NULL) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: Failed to create stop event.");
    miniav_free(wgc_ctx);
    ctx->platform_ctx = NULL;
    shutdown_winrt_for_wgc();
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (!InitializeCriticalSectionAndSpinCount(&wgc_ctx->critical_section,
                                             0x00000400)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "WGC: Failed to initialize critical section.");
    CloseHandle(wgc_ctx->stop_event_handle);
    miniav_free(wgc_ctx);
    ctx->platform_ctx = NULL;
    shutdown_winrt_for_wgc();
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  res = wgc_init_d3d_device(wgc_ctx);
  if (res != MINIAV_SUCCESS) {
    DeleteCriticalSection(&wgc_ctx->critical_section);
    CloseHandle(wgc_ctx->stop_event_handle);
    miniav_free(wgc_ctx);
    ctx->platform_ctx = NULL;
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
  // 1. Under the lock: kill the streaming flag, wake any pacing wait, revoke
  //    the FrameArrived / Closed tokens and close the session + frame pool.
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

  if (wgc_ctx->pace_timer) {
    CloseHandle(wgc_ctx->pace_timer);
    wgc_ctx->pace_timer = NULL;
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
  wgc_ctx->ctx_magic = WGC_CTX_MAGIC_DEAD;
  miniav_free(wgc_ctx);
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

  // Reset FPS pacing for this run. Interval from the requested rational
  // frame rate (falling back to the integral target_fps) so the absolute
  // schedule carries no cumulative rounding drift.
  {
    LARGE_INTEGER pace_freq;
    QueryPerformanceFrequency(&pace_freq);
    UINT pace_num = wgc_ctx->configured_video_format.frame_rate_numerator;
    UINT pace_den = wgc_ctx->configured_video_format.frame_rate_denominator;
    if (pace_num == 0 || pace_den == 0) {
      pace_num = wgc_ctx->target_fps ? wgc_ctx->target_fps : 30;
      pace_den = 1;
    }
    wgc_ctx->pace_interval_qpc =
        (LONGLONG)((ULONGLONG)pace_freq.QuadPart * pace_den / pace_num);
    wgc_ctx->pace_next_deadline_qpc = 0;
    if (!wgc_ctx->pace_timer) {
      wgc_ctx->pace_timer = CreateWaitableTimerExW(
          NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
      if (!wgc_ctx->pace_timer) {
        // Pre-1803 Windows: plain waitable timer (system-tick resolution, but
        // the absolute schedule still removes the systematic fast bias).
        wgc_ctx->pace_timer = CreateWaitableTimerW(NULL, FALSE, NULL);
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: high-resolution pacing timer unavailable — pacing "
                   "resolution limited to the system tick.");
      }
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
                               2, // Number of buffers in the pool
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

  // Wait out any FrameArrived/Closed callback still executing — notably one
  // parked in the FPS pacing loop, which runs outside the critical section and
  // keeps dereferencing wgc_ctx. is_streaming = FALSE and the stop event are
  // both already set above, so every pacing branch exits within ~1 ms.
  // The drain is deliberately AFTER LeaveCriticalSection: an in-flight
  // wgc_on_frame_arrived takes the same critical section, so draining under it
  // would deadlock.
  wgc_drain_callbacks(wgc_ctx, "stop_capture");

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
          // have completed its import (OpenSharedResource1 / minigpu
          // mgpuImportVideoFrame, which copies into a private texture before
          // returning) before calling MiniAV_ReleaseBuffer. Leaving this to
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
// GraphicsCaptureItem.Closed event (window closed / display disconnected) and
// from device-removed detection in the frame-arrived path — previously WGC
// had no loss notification at all: frames just stopped while the app believed
// capture was still running (unlike DXGI's ACCESS_LOST -> lost_cb handling).
//
// LIFETIME: the caller MUST already hold a WGCCallbackRef (both call sites —
// the item Closed lambda and the device-removed branch of
// wgc_on_frame_arrived — do), so the context cannot be freed underneath this.
// Neither call site holds the critical section, so taking it here is safe.
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
    SetEvent(wgc_ctx->stop_event_handle); // unblock any in-flight pacing wait
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

// --- Frame Arrived Handler ---
// --- Frame Arrived Handler ---
static void wgc_on_frame_arrived(
    WGCScreenPlatformContext *wgc_ctx,
    winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool const &sender,
    winrt::Windows::Foundation::IInspectable const & /*args*/) {
  // Threadpool entry point. The reference is held for the ENTIRE body,
  // including the FPS pacing loop at the tail which runs outside the critical
  // section and can block for a frame interval — that window is exactly where
  // the context used to be freed underneath this thread.
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

  if (!wgc_ctx->is_streaming) { // Check atomic bool
    if (sender) { // Try to get next frame to release it back to pool if session
                  // is active
      try {
        auto frame = sender.TryGetNextFrame();
        if (frame)
          frame.Close();
      } catch (...) {
      }
    }
    return;
  }

  // Check stop event
  if (WaitForSingleObject(wgc_ctx->stop_event_handle, 0) == WAIT_OBJECT_0) {
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

  winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame frame{nullptr};
  try {
    frame = sender.TryGetNextFrame();
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
      wgc_notify_capture_lost(wgc_ctx, "device removed / session closed");
    }
    return;
  }

  if (!frame) {
    // miniav_log(MINIAV_LOG_LEVEL_DEBUG, "WGC: No frame available.");
    return;
  }

  // Enter CS to safely access app_callback and user_data
  // This also protects against concurrent stop_capture changing these.
  EnterCriticalSection(&wgc_ctx->critical_section);
  if (!wgc_ctx->is_streaming || !wgc_ctx->app_callback_internal) {
    LeaveCriticalSection(&wgc_ctx->critical_section);
    if (frame)
      frame.Close();
    return;
  }

  MiniAVBuffer *buffer = (MiniAVBuffer *)miniav_calloc(1, sizeof(MiniAVBuffer));
  if (!buffer) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "WGC: Failed to allocate MiniAVBuffer");
    LeaveCriticalSection(&wgc_ctx->critical_section);
    if (frame)
      frame.Close();
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
  // Set when the live content size has drifted from the pool size; the pool is
  // recreated at the tail of this function (outside the frame's lifetime).
  UINT pending_pool_w = 0, pending_pool_h = 0;

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

    auto timestamp_raw =
        frame.SystemRelativeTime(); // TimeSpan (100-nanosecond units)
    buffer->timestamp_us = static_cast<uint64_t>(timestamp_raw.count() /
                                                 10); // Convert 100ns to us

    // The surface handed out by the frame pool is ALWAYS pool-sized;
    // frame.ContentSize() is the live size of the capture target and grows the
    // instant a captured window is resized. Describing the buffer with the raw
    // content size while the bytes come from a pool-sized (and therefore
    // smaller) surface is how data_size_bytes used to run past the end of the
    // mapping. Report what actually exists — the intersection of the two — and
    // queue a pool recreate so the following frames carry the full content.
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

    if ((content_w != wgc_ctx->pool_width ||
         content_h != wgc_ctx->pool_height) &&
        content_w > 0 && content_h > 0) {
      pending_pool_w = content_w;
      pending_pool_h = content_h;
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

      winrt::com_ptr<ID3D11Texture2D> texture_to_share_com =
          acquired_texture_com;
      bool needs_copy_for_sharing =
          !(acquired_desc.MiscFlags & D3D11_RESOURCE_MISC_SHARED_NTHANDLE) &&
          !(acquired_desc.MiscFlags & D3D11_RESOURCE_MISC_SHARED);

      winrt::com_ptr<ID3D11Texture2D> shareable_copy_temp_com = nullptr;

      if (needs_copy_for_sharing) {
        miniav_log(
            MINIAV_LOG_LEVEL_DEBUG,
            "WGC: Acquired texture not shareable, creating a shareable copy.");
        D3D11_TEXTURE2D_DESC shareable_desc = acquired_desc; // Start with copy
        shareable_desc.Usage = D3D11_USAGE_DEFAULT;
        shareable_desc.BindFlags =
            D3D11_BIND_SHADER_RESOURCE |
            D3D11_BIND_RENDER_TARGET; // Typical for shared
        shareable_desc.CPUAccessFlags = 0;
        shareable_desc.MiscFlags =
            D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED;

        hr = wgc_ctx->d3d_device->CreateTexture2D(
            &shareable_desc, nullptr, shareable_copy_temp_com.put());
        if (SUCCEEDED(hr)) {
          wgc_ctx->d3d_context->CopyResource(shareable_copy_temp_com.get(),
                                             acquired_texture_com.get());
          texture_to_share_com = shareable_copy_temp_com;
        } else {
          miniav_log(MINIAV_LOG_LEVEL_ERROR,
                     "WGC: Failed to create shareable GPU texture copy: 0x%X. "
                     "Fallback to CPU.",
                     hr);
          // Force CPU path by not setting processed_as_gpu
        }
      }

      if (SUCCEEDED(hr) &&
          texture_to_share_com) { // Original was shareable or copy succeeded
        winrt::com_ptr<IDXGIResource1> dxgi_resource_to_share;
        hr = texture_to_share_com->QueryInterface(
            IID_PPV_ARGS(dxgi_resource_to_share.put()));

        if (SUCCEEDED(hr)) {
          hr = dxgi_resource_to_share->CreateSharedHandle(
              nullptr, DXGI_SHARED_RESOURCE_READ, nullptr,
              &shared_handle_for_app);
          if (SUCCEEDED(hr) && shared_handle_for_app) {
            // CRITICAL: synchronise the producer device before exposing the
            // shared NT handle to a different-device consumer (e.g. an FFmpeg
            // encoder). Without a fence the consumer may read garbage / black
            // because pending GPU work on texture_to_share_com has not yet
            // executed. See screen_context_win_dxgi.c for full rationale.
            {
              D3D11_QUERY_DESC fence_desc{};
              fence_desc.Query = D3D11_QUERY_EVENT;
              winrt::com_ptr<ID3D11Query> copy_done;
              HRESULT q_hr = wgc_ctx->d3d_device->CreateQuery(
                  &fence_desc, copy_done.put());
              if (SUCCEEDED(q_hr) && copy_done) {
                wgc_ctx->d3d_context->End(copy_done.get());
                wgc_ctx->d3d_context->Flush();
                // Wait up to ~16 ms (one 60 fps frame) for the GPU to commit,
                // then proceed — timeout is now LOGGED (rate-limited) instead
                // of silently proceeding (real black-frame risk under GPU
                // contention). True fence handoff is deferred (NATIVE_AUDIT.md).
                ULONGLONG poll_start = GetTickCount64();
                bool fence_done = false;
                for (;;) {
                  if (wgc_ctx->d3d_context->GetData(copy_done.get(), nullptr, 0,
                                                    0) != S_FALSE) {
                    fence_done = true;
                    break;
                  }
                  if (GetTickCount64() - poll_start > 16)
                    break;
                  YieldProcessor();
                }
                if (!fence_done) {
                  static ULONGLONG s_last_fence_warn_ms = 0;
                  ULONGLONG now_ms = GetTickCount64();
                  if (now_ms - s_last_fence_warn_ms > 2000) {
                    s_last_fence_warn_ms = now_ms;
                    miniav_log(MINIAV_LOG_LEVEL_WARN,
                               "WGC: GPU sync fence did not signal within 16ms "
                               "— sharing anyway (possible torn/black frame "
                               "under GPU contention).");
                  }
                }
              } else {
                wgc_ctx->d3d_context->Flush();
              }
            }

            texture_for_payload_ref_com =
                texture_to_share_com; // This is the texture whose handle was
                                      // shared
            texture_for_payload_ref_com->AddRef(); // AddRef for payload
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
      // NOTE: buffer->native_fence is deliberately left zeroed — miniav never
      // creates an ID3D11Fence. The synchronisation actually performed is the
      // D3D11_QUERY_EVENT busy-poll above, which PROCEEDS ON TIMEOUT. See
      // miniav_buffer.h `native_fence` and NATIVE_AUDIT.md P2 §1.
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
      // calculate data size based on width, height, and pixel format
      buffer->data_size_bytes =
          ((size_t)buffer->data.video.info.width *
           buffer->data.video.info.height * 4); // BGRA32 = 4 bytes per pixel

      // Same oracle as the CPU path: the shared texture is the pool-sized
      // surface (or a same-desc copy of it), so its extent bounds what the
      // consumer can legally read.
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
               "WGC: Error in on_frame_arrived: %ls (0x%08X)",
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
               "WGC: Unknown error in on_frame_arrived.");
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

  LeaveCriticalSection(&wgc_ctx->critical_section);
  if (frame)
    frame.Close(); // Release frame back to pool

  // --- Track content resizes ---
  // The pool was sized once from capture_item.Size() at StartCapture and never
  // revisited, so growing a captured window left every later frame arriving on
  // an undersized surface while frame.ContentSize() reported the new, larger
  // size. Direct3D11CaptureFramePool::Recreate is the documented remedy and is
  // safe to call from inside the FrameArrived handler — do it AFTER
  // frame.Close() so the surface we just read is back in the pool.
  //
  // LOCKING: taken under the context's critical section, which is the same
  // lock wgc_stop_capture holds while it calls frame_pool.Close(). That makes
  // "pool is being closed" and "pool is being recreated" mutually exclusive,
  // and re-checking is_streaming inside means a stop that won the race turns
  // this into a no-op. No deadlock against the callback drain: the drain runs
  // with the critical section RELEASED, and this block never waits on anything
  // but the lock itself. cb_ref (top of the function) is still held throughout.
  if (pending_pool_w && pending_pool_h && !wgc_stress_no_pool_recreate() &&
      wgc_ctx_alive(wgc_ctx, "pool recreate")) {
    EnterCriticalSection(&wgc_ctx->critical_section);
    if (wgc_ctx->is_streaming && wgc_ctx->frame_pool &&
        wgc_ctx->d3d_device_winrt &&
        (wgc_ctx->pool_width != pending_pool_w ||
         wgc_ctx->pool_height != pending_pool_h)) {
      try {
        winrt::Windows::Graphics::SizeInt32 new_size{
            static_cast<int32_t>(pending_pool_w),
            static_cast<int32_t>(pending_pool_h)};
        wgc_ctx->frame_pool.Recreate(
            wgc_ctx->d3d_device_winrt,
            winrt::Windows::Graphics::DirectX::DirectXPixelFormat::
                B8G8R8A8UIntNormalized,
            2, new_size);
        miniav_log(MINIAV_LOG_LEVEL_INFO,
                   "WGC: capture content resized %ux%u -> %ux%u; frame pool "
                   "recreated.",
                   wgc_ctx->pool_width, wgc_ctx->pool_height, pending_pool_w,
                   pending_pool_h);
        wgc_ctx->pool_width = pending_pool_w;
        wgc_ctx->pool_height = pending_pool_h;
        g_wgc_pool_recreates.fetch_add(1, std::memory_order_relaxed);
      } catch (winrt::hresult_error const &ex) {
        // RO_E_CLOSED here just means teardown got the pool first.
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: frame pool Recreate to %ux%u failed: %ls (0x%08X); "
                   "continuing at the old pool size.",
                   pending_pool_w, pending_pool_h, ex.message().c_str(),
                   ex.code().value);
      } catch (...) {
        miniav_log(MINIAV_LOG_LEVEL_WARN,
                   "WGC: frame pool Recreate to %ux%u failed (unknown).",
                   pending_pool_w, pending_pool_h);
      }
    }
    LeaveCriticalSection(&wgc_ctx->critical_section);
  }

  // FPS pacing. WGC is event-driven at the compose rate, so throttling works
  // by blocking this frame-pool callback thread until the next output slot.
  // Deliveries are paced against an ABSOLUTE QPC schedule (deadline += exact
  // interval) slept on a high-resolution waitable timer. The previous
  // relative Sleep(interval - 2) systematically ran ~5% fast in
  // timer-resolution-raised processes (any Flutter app): a 30 fps target
  // delivered ~31.4 fps, and the consumer's fps throttle then deleted the
  // excess frame every ~20 frames — one double-length presentation hole every
  // ~0.7 s, a metronomic visible stutter in recordings. The absolute schedule
  // also self-corrects after a slow frame instead of drifting.
  //
  // LIFETIME: this whole block runs with the critical section RELEASED, so it
  // is only safe because cb_ref (top of the function) is still held —
  // stop_capture / destroy_platform block in wgc_drain_callbacks() until this
  // returns. Both set is_streaming = FALSE and signal stop_event_handle before
  // draining, and every wait below is bounded by one of the two, so the drain
  // cannot be held up for more than ~1 ms.
  if (!wgc_ctx_alive(wgc_ctx, "pacing loop"))
    return;
  if (wgc_ctx->target_fps > 0 && wgc_ctx->is_streaming &&
      wgc_ctx->pace_interval_qpc > 0) {
    LARGE_INTEGER pace_freq;
    QueryPerformanceFrequency(&pace_freq);
    LARGE_INTEGER pace_now;
    QueryPerformanceCounter(&pace_now);
    if (wgc_ctx->pace_next_deadline_qpc == 0) {
      wgc_ctx->pace_next_deadline_qpc =
          pace_now.QuadPart + wgc_ctx->pace_interval_qpc;
    } else {
      wgc_ctx->pace_next_deadline_qpc += wgc_ctx->pace_interval_qpc;
      if (pace_now.QuadPart - wgc_ctx->pace_next_deadline_qpc >
          wgc_ctx->pace_interval_qpc) {
        // More than a full interval behind (idle stretch on a static screen,
        // or a stalled iteration): resync instead of bursting stale catch-up
        // deliveries. Being behind by LESS than an interval intentionally
        // skips the wait once, pulling the next delivery back onto schedule.
        wgc_ctx->pace_next_deadline_qpc = pace_now.QuadPart;
      }
    }
    // The liveness check is FIRST (short-circuit) on purpose: a context freed
    // while this thread was parked leaves is_streaming reading as garbage/zero,
    // which would otherwise exit the loop quietly and hide the violation.
    while (wgc_ctx_alive(wgc_ctx, "pacing wait") && wgc_ctx->is_streaming) {
      QueryPerformanceCounter(&pace_now);
      LONGLONG pace_remaining =
          wgc_ctx->pace_next_deadline_qpc - pace_now.QuadPart;
      if (pace_remaining <= 0)
        break;
      LONGLONG pace_remaining_100ns =
          pace_remaining * 10000000LL / pace_freq.QuadPart;
      if (pace_remaining_100ns < 5000) // <0.5 ms — close enough
        break;
      if (wgc_ctx->pace_timer && !wgc_stress_force_pace_sleep()) {
        LARGE_INTEGER pace_due;
        pace_due.QuadPart = -pace_remaining_100ns; // negative = relative
        if (SetWaitableTimer(wgc_ctx->pace_timer, &pace_due, 0, NULL, NULL,
                             FALSE)) {
          HANDLE pace_waits[2] = {wgc_ctx->stop_event_handle,
                                  wgc_ctx->pace_timer};
          DWORD pace_w = WaitForMultipleObjects(
              2, pace_waits, FALSE,
              (DWORD)(pace_remaining_100ns / 10000) + 50);
          if (pace_w == WAIT_OBJECT_0)
            break;  // stop requested
          continue; // timer fired (or timed out) — re-check the deadline
        }
      }
      // Fallback when the high-resolution waitable timer is unavailable or
      // SetWaitableTimer failed. Still sleeps to the same ABSOLUTE deadline,
      // but on the stop event instead of a bare Sleep(): the bare version
      // ignored teardown entirely and parked this thread — and the teardown
      // drain waiting on it — for a full frame interval (≈1 s at 1 fps).
      const DWORD pace_fallback_ms = (DWORD)(pace_remaining_100ns / 10000) + 1;
      if (wgc_stress_legacy_teardown()) {
        Sleep(pace_fallback_ms); // pre-fix, stop-event-blind (test-only)
        continue;
      }
      if (WaitForSingleObject(wgc_ctx->stop_event_handle, pace_fallback_ms) ==
          WAIT_OBJECT_0)
        break; // stop requested
    }
  }
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
