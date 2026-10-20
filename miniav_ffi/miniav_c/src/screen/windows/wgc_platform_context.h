#pragma once
// Real constructed WGC platform storage. COM/WinRT references and atomics may
// not be initialized by calloc or disposed by free. Native activation is a
// separate later stage; these helpers create no COM/GPU/dispatcher/capture.
#include "screen_context_win_wgc.h"
#include "wgc_owner_storage.h"
#include <windows.h>
#include <d3d11_4.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <atomic>
#include <new>
#include <type_traits>

typedef enum WGCCaptureTargetType {
  WGC_TARGET_NONE,
  WGC_TARGET_DISPLAY,
  WGC_TARGET_WINDOW
} WGCCaptureTargetType;

// One period of capture, logged by wgc_pump (see wgc_log_stats_locked). Times
// in 100 ns units.
typedef struct WGCFrameStats {
  LONGLONG start_100ns; // 0 until the period's first pump
  UINT32 taken;         // frames taken from the pool
  UINT32 filled;        // slots a frame was delivered for
  LONGLONG offset_min_100ns; // capture time minus slot time, over those
  LONGLONG offset_max_100ns;
  UINT32 copies;     // GPU frames, from the copy until the GPU finished it
  UINT32 copy_drops; // GPU frames dropped as unfinished
  LONGLONG copy_sum_100ns;
  LONGLONG copy_max_100ns;
  UINT32 readbacks; // CPU frames, from the copy until it was mapped
  LONGLONG readback_sum_100ns;
  LONGLONG readback_max_100ns;
} WGCFrameStats;

typedef struct WGCScreenPlatformContext {
  volatile ULONG ctx_magic; // WGC_CTX_MAGIC_LIVE while the context is usable
  MiniAVScreenContext *parent_ctx;
  void *strict_holder; // Separately constructed strict owner.

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

  std::atomic<BOOL> is_streaming{FALSE};
  // Number of WinRT threadpool callbacks (FrameArrived / item Closed)
  // currently executing against this context. Teardown drains this to zero
  // before closing handles or freeing — see the "callback lifetime protocol"
  // block below wgc_ctx_alive().
  std::atomic<long> callbacks_in_flight{0};
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
  // resized. Tracking it is what lets wgc_take_frame_locked notice the drift
  // and wgc_recreate_pool_locked call Direct3D11CaptureFramePool::Recreate.
  // Written under critical_section.
  UINT pool_width;
  UINT pool_height;
  MiniAVPixelFormat pixel_format; // Typically BGRA32

  LARGE_INTEGER qpc_frequency;

  // Output pacing (see wgc_pump). Frames are filed under the slots of a grid
  // at the configured rate, pace_num/pace_den fps, that starts at the run's
  // first capture time; the newest frame of each slot is held until the
  // slot's window closes and is then delivered stamped with the slot's time.
  // All of it under critical_section.
  LONGLONG pace_num;
  LONGLONG pace_den;
  LONGLONG grid_origin_100ns; // -1 until the run's first frame
  LONGLONG last_slot;         // last slot delivered, -1 for none
  winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame held_frame{
      nullptr};
  LONGLONG held_slot;
  LONGLONG held_captured_100ns; // when held_frame was captured
  WGCFrameStats stats;
  UINT pending_pool_w; // content size a pool recreate waits for, 0 for none
  UINT pending_pool_h;
  // Delivers a held frame when no newer frame comes to do it: a threadpool
  // wait on a high-resolution waitable timer. The wait is created by start
  // and closed by stop and destroy; the timer lasts as long as the context.
  PTP_WAIT pace_tp_wait;
  HANDLE pace_wake_timer;
  // A window capture's check that its window still exists and belongs to the
  // thread that owned it at start, since Windows does not raise Closed for
  // every window that goes away (see wgc_arm_window_watch_locked). Created by
  // start, closed by stop and destroy.
  PTP_TIMER window_watch;
  DWORD watched_pid;
  DWORD watched_tid;

  // Completion fence for the copy each GPU frame is shared from (see
  // wgc_wait_copy_locked). Created on first use, released by stop and with
  // the device.
  winrt::com_ptr<ID3D11Fence> copy_fence;
  winrt::com_ptr<ID3D11DeviceContext4> copy_fence_ctx;
  HANDLE copy_fence_event;
  UINT64 copy_fence_value;
  bool copy_fence_unavailable;

  WGCCaptureTargetType current_target_type;
  char selected_item_id[MINIAV_DEVICE_ID_MAX_LEN]; // e.g., "HMONITOR:0x1234" or
                                                   // "HWND:0x5678"
  HWND selected_hwnd;                              // If window capture
  HMONITOR selected_hmonitor;                      // If display capture

  // --- Audio Loopback Members ---
  MiniAVLoopbackContextHandle loopback_audio_ctx;
  BOOL audio_loopback_enabled_and_configured;
  MiniAVAudioInfo configured_audio_format; // Actual format from loopback

  miniav::wgc_owner_storage::Ticket storage_ticket;

} WGCScreenPlatformContext;

namespace miniav::wgc_platform_storage {
static_assert(std::is_nothrow_default_constructible_v<WGCScreenPlatformContext>);
static_assert(std::is_nothrow_destructible_v<WGCScreenPlatformContext>);
inline WGCScreenPlatformContext *allocate() noexcept {
  return new (std::nothrow) WGCScreenPlatformContext{};
}
// Caller has drained callbacks, closed sessions and released native resources.
inline void destroy(WGCScreenPlatformContext *value) noexcept {
  // Funded contexts have a distinct checked destructor. Refuse plain delete.
  if (value && value->storage_ticket) { value->storage_ticket.quarantine(); return; }
  delete value;
}
} // namespace miniav::wgc_platform_storage
