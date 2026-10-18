#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "screen_context_win_wgc_strict.h"
#include "wgc_frame_texture.h"
#include "wgc_fixed_geometry.h"
#include "wgc_delegate_storage.h"
#include "../../common/miniav_com_win.h"
#include "../../common/miniav_utils.h"

#include <d3d11_4.h>
#include <dwmapi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.Metadata.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>

namespace {
using namespace winrt::Windows::Graphics::Capture;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using namespace std::chrono_literals;

// Queried by trusted hosts before registering fixed callback custody. Keep the
// exported contract and the actual native allocation gate on this one value.
constexpr uint32_t max_outstanding_buffers = miniav::wgc_strict::outstanding_snapshots;
constexpr size_t max_window_candidates = 128;

enum class Mode { fresh, generic, strict };
struct Owner;
using Holder = std::shared_ptr<Owner>;

// Monotonic IDs are never recycled, including on a failed selection. Exhaustion
// refuses rather than wrapping into a prior source/window incarnation.
std::atomic<uint64_t> next_id{1};
uint64_t mint_id() noexcept {
  auto value = next_id.load();
  while (value != UINT64_MAX) {
    if (next_id.compare_exchange_weak(value, value + 1)) return value;
  }
  return 0;
}

uint64_t filetime_value(FILETIME value) noexcept {
  return (uint64_t(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}

// 100 ns units on the QPC timeline, the clock of SystemRelativeTime.
int64_t qpc_now() noexcept {
  LARGE_INTEGER count{}, frequency{};
  QueryPerformanceCounter(&count);
  QueryPerformanceFrequency(&frequency);
  const auto whole = count.QuadPart / frequency.QuadPart;
  const auto part = count.QuadPart % frequency.QuadPart;
  return whole * 10000000 + part * 10000000 / frequency.QuadPart;
}

bool pin_module() noexcept {
  HMODULE module = nullptr;
  return GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_PIN,
      reinterpret_cast<LPCWSTR>(&pin_module), &module) != FALSE;
}

struct Candidate;

// A delegate's *last copy* can outlive both event revocation and invocation.
// Keep this separate from entered callback counts. Tokens alone are not proof.
// Tickets live inside callables: copies count independently, moves transfer
// that obligation, and an emptied source has no destruction obligation.
struct DelegateTicket {
  Holder owner;
  explicit DelegateTicket(Holder value);
  DelegateTicket(const DelegateTicket &value);
  DelegateTicket(DelegateTicket &&value) noexcept;
  DelegateTicket &operator=(const DelegateTicket &) = delete;
  DelegateTicket &operator=(DelegateTicket &&) = delete;
  ~DelegateTicket();
};
struct Invocation {
  Holder owner;
  explicit Invocation(Holder value, bool already_charged = false);
  ~Invocation();
};

using ClosedEvent = winrt::Windows::Foundation::TypedEventHandler<
    GraphicsCaptureItem, winrt::Windows::Foundation::IInspectable>;
using FrameEvent = winrt::Windows::Foundation::TypedEventHandler<
    Direct3D11CaptureFramePool, winrt::Windows::Foundation::IInspectable>;
struct ClosedCallable {
  DelegateTicket ticket;
  Candidate *const candidate;
  ClosedCallable(Holder owner, Candidate *value) : ticket(std::move(owner)), candidate(value) {}
  static void *operator new(size_t bytes);
  static void operator delete(void *address) noexcept;
  void operator()(GraphicsCaptureItem const&,
      winrt::Windows::Foundation::IInspectable const&) const;
};
struct FrameCallable {
  DelegateTicket ticket;
  explicit FrameCallable(Holder owner) : ticket(std::move(owner)) {}
  static void *operator new(size_t bytes);
  static void operator delete(void *address) noexcept;
  void operator()(Direct3D11CaptureFramePool const&,
      winrt::Windows::Foundation::IInspectable const&) const;
};
using ClosedDelegate = winrt::impl::delegate<ClosedEvent, ClosedCallable>;
using FrameDelegate = winrt::impl::delegate<FrameEvent, FrameCallable>;
static_assert(&ClosedDelegate::operator new == &ClosedCallable::operator new &&
    &ClosedDelegate::operator delete == &ClosedCallable::operator delete,
    "The actual WinRT Closed delegate must use its handler's storage");
static_assert(&FrameDelegate::operator new == &FrameCallable::operator new &&
    &FrameDelegate::operator delete == &FrameCallable::operator delete,
    "The actual WinRT FrameArrived delegate must use its handler's storage");
namespace delegate_storage = miniav::wgc_delegate_storage;
void unknown_delegate_storage(void *owner) noexcept;

struct Candidate {
  MiniAVWindowsScreenCandidateV1 public_value{};
  uint64_t incarnation = 0;
  GraphicsCaptureItem item{nullptr};
  winrt::event_token token{};
  bool registered = false;
  std::atomic<bool> closed{false};
  delegate_storage::Slot<ClosedDelegate> delegate;
};

struct DispatchLease {
  const bool held = miniav_dispatch_guard_acquire_if_enabled() != 0;
  ~DispatchLease() { if (held) miniav_dispatch_guard_release(); }
};

struct PendingFrame {
  Direct3D11CaptureFrame frame{nullptr};
  winrt::com_ptr<ID3D11Texture2D> source, snapshot;
  winrt::com_ptr<ID3D11Query> query;
  HANDLE handle = nullptr;
  bool issued = false;
  bool complete = false;
  // The copy's value on the owner's fence, else 0 and `query` reports it.
  uint64_t fence_value = 0;
  bool armed = false; // The GPU sets the owner's `copied` when it is done.
  UINT width = 0, height = 0;
  int64_t timestamp = 0;
};

struct Payload {
  Holder owner;
  winrt::com_ptr<ID3D11Texture2D> snapshot;
  HANDLE handle = nullptr;
  bool posted = false;
  bool release_failed = false;
};

enum class FramePhase { empty, preparing, ready, releasing, quarantined };
struct FrameSlot {
  MiniAVBuffer buffer{};
  MiniAVNativeBufferInternalPayload internal{};
  Payload payload;
  FramePhase phase = FramePhase::empty;
};

struct Owner : std::enable_shared_from_this<Owner> {
  MiniAVScreenContext *const parent;
  void *const platform;
  const MiniAVWgcTakeDevice take_device;
  const bool module_pinned;
  std::mutex mutex;
  std::condition_variable changed;
  Mode mode = Mode::fresh;
  bool terminal = false, nonce_spent = false, configured = false;
  bool start_spent = false, started = false, frame_ready = false;
  bool worker_started = false, producer_closed = false, lost_notified = false;
  bool cursor = false;
  uint32_t state = 0, operations = 0, callbacks = 0, delegates = 0;
  uint32_t buffers = 0, releases = 0;
  int32_t reason = 0, cleanup_error = 0;
  uint64_t posted = 0, released = 0, selection_deadline = 0;
  uint64_t selected = 0, capture_id = 0;
  HANDLE process = nullptr;
  MiniAVWindowsAppAdmissionV1 admission{};
  MiniAVWindowsSelectionNonceV1 nonce{};
  MiniAVVideoInfo format{};
  MiniAVBufferCallback callback = nullptr;
  void *callback_data = nullptr;
  MiniAVContextLostCallback lost = nullptr;
  void *lost_data = nullptr;
  // Stable slots are paid by the original Owner allocation before activation.
  // A queued delegate retains this Owner through its ticket, so slots stay
  // alive even after event revocation/COM cleanup. Never recycle their IDs.
  std::array<Candidate, max_window_candidates> candidates{};
  size_t candidate_count = 0;
  Candidate *chosen = nullptr;
  std::thread worker;

  // Mutated by Begin/Configure/Start only while operations > 0, then solely by
  // the native worker. That worker is the only immediate-context executor.
  winrt::com_ptr<ID3D11Device> device;
  winrt::com_ptr<ID3D11DeviceContext> immediate;
  IDirect3DDevice rt_device{nullptr};
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession session{nullptr};
  winrt::event_token frame_token{};
  bool frame_registered = false;
  delegate_storage::Slot<FrameDelegate> frame_delegate;
  std::optional<PendingFrame> pending;
  // The newest acquired frame not yet delivered. It is held, never dropped,
  // until it is due and a buffer is free, so a window's last change always
  // goes out. `arriving` owns the next frame while the one it replaces closes.
  Direct3D11CaptureFrame latest{nullptr}, arriving{nullptr};
  int64_t next_due = 0; // QPC timeline, 100 ns units.
  // Each snapshot copy signals the next value of `fence`, and the GPU sets
  // `copied` on reaching it, so the worker wakes as soon as a copy is done
  // instead of polling for it. Created by the first copy. Without fences
  // (before Windows 10 1703 or a WDDM 2.2 driver) an event query reports
  // each copy and the worker rechecks it.
  winrt::com_ptr<ID3D11Fence> fence;
  winrt::com_ptr<ID3D11DeviceContext4> fence_context;
  HANDLE copied = nullptr; // Auto-reset.
  uint64_t fence_value = 0;
  bool fence_unavailable = false;
  // Actual envelope bytes are in the original quoted Owner, not per-frame
  // heaps. Occupied slots retain this Owner until their genuine release.
  std::array<FrameSlot, max_outstanding_buffers> frames{};

  Owner(MiniAVScreenContext *p, void *wgc, MiniAVWgcTakeDevice take)
      : parent(p), platform(wgc), take_device(take),
        module_pinned(pin_module()) {}

  Candidate *append_candidate() noexcept {
    if (candidate_count == candidates.size()) return nullptr;
    return &candidates[candidate_count++];
  }

  Candidate *find_candidate(uint64_t id) noexcept {
    if (!id) return nullptr;
    for (size_t i = 0; i < candidate_count; ++i)
      if (candidates[i].public_value.candidate_id == id) return &candidates[i];
    return nullptr;
  }

  bool prepare_pending() {
    if (pending) return false; // Occupied/uncertain GPU work is never replaced.
    pending.emplace();
    return true;
  }

  FrameSlot *prepare_frame() {
    auto retained = shared_from_this();
    std::lock_guard<std::mutex> lock(mutex);
    if (state == 3 || buffers >= frames.size()) return nullptr;
    for (auto &slot : frames) {
      if (slot.phase != FramePhase::empty) continue;
      slot.buffer = {};
      slot.internal = {};
      slot.payload.owner = std::move(retained);
      slot.payload.posted = slot.payload.release_failed = false;
      slot.phase = FramePhase::preparing;
      ++buffers; // Reserve before any native ownership transfer or exposure.
      return &slot;
    }
    return nullptr;
  }

  void stop_locked(int32_t why) {
    if (!terminal) {
      terminal = true;
      reason = why;
      state = 1;
    }
    changed.notify_all();
  }

  void stop(int32_t why) {
    std::lock_guard<std::mutex> lock(mutex);
    stop_locked(why);
  }

  void failed(int32_t error) {
    std::lock_guard<std::mutex> lock(mutex);
    stop_locked(error);
    if (!cleanup_error) cleanup_error = error;
    state = 3; // Sticky quarantine; no timeout or process exit can clear it.
    changed.notify_all();
  }

  bool alive_locked() {
    if (terminal) return false;
    const auto deadline = configured ? admission.valid_until_tick_ms
                                     : selection_deadline;
    if (deadline && GetTickCount64() >= deadline) {
      stop_locked(MINIAV_ERROR_PERMISSION_DENIED);
      return false;
    }
    return true;
  }

  bool launch_locked() {
    if (worker_started) return true;
    try {
      // The platform holder remains until checked destruction joins this
      // thread. The thread is never the last owner of its own joinable object.
      worker = std::thread([this] { run(); });
      worker_started = true;
      return true;
    } catch (...) {
      terminal = true;
      reason = cleanup_error = MINIAV_ERROR_SYSTEM_CALL_FAILED;
      state = 3;
      return false;
    }
  }

  MiniAVResultCode claim_locked() {
    if (!module_pinned || miniav_com_legacy_percall())
      return MINIAV_ERROR_NOT_SUPPORTED;
    if (mode != Mode::fresh) return MINIAV_ERROR_INVALID_OPERATION;
    mode = Mode::strict;
    cursor = parent->capture_cursor;
    lost = parent->lost_cb;
    lost_data = parent->lost_cb_user_data;
    return launch_locked() ? MINIAV_SUCCESS : MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  struct Operation {
    Owner *owner;
    explicit Operation(Owner *value) : owner(value) {}
    ~Operation() {
      std::lock_guard<std::mutex> lock(owner->mutex);
      --owner->operations;
      owner->changed.notify_all();
    }
  };

  void adopt_device() {
    if (device) return;
    void *d = nullptr, *c = nullptr, *r = nullptr;
    const auto result = take_device(platform, &d, &c, &r);
    if (result != MINIAV_SUCCESS || !d || !c || !r)
      throw winrt::hresult_error(E_FAIL);
    device.attach(static_cast<ID3D11Device *>(d));
    immediate.attach(static_cast<ID3D11DeviceContext *>(c));
    winrt::attach_abi(rt_device, r);
  }

  bool process_current() const noexcept {
    FILETIME creation{}, exit{}, kernel{}, user{};
    return process && GetProcessId(process) == admission.process_id &&
        GetProcessTimes(process, &creation, &exit, &kernel, &user) &&
        filetime_value(creation) == admission.process_creation_filetime &&
        WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
  }

  static bool window_current(HWND window, DWORD expected) noexcept {
    DWORD actual = 0;
    return IsWindow(window) && GetWindowThreadProcessId(window, &actual) &&
           actual == expected;
  }

  // Closed is not raised for every destroyed window (a closed popup whose
  // process lives on never raised it), so the handle is checked directly too.
  bool chosen_current() const noexcept {
    return chosen && !chosen->closed &&
           window_current(reinterpret_cast<HWND>(chosen->public_value.hwnd_value),
                          admission.process_id);
  }

  void item_closed(Candidate *candidate) {
    candidate->closed = true;
    std::lock_guard<std::mutex> lock(mutex);
    if (selected == candidate->public_value.candidate_id)
      stop_locked(MINIAV_ERROR_DEVICE_LOST);
  }

  ClosedEvent closed_callback(Candidate *candidate) {
    bool original = false;
    for (size_t i = 0; i < candidate_count; ++i)
      if (&candidates[i] == candidate) { original = true; break; }
    if (!original) throw std::bad_alloc();
    auto retained = shared_from_this();
    delegate_storage::Scope<ClosedDelegate> scope(candidate->delegate, retained,
        unknown_delegate_storage);
    return ClosedEvent(ClosedCallable(std::move(retained), candidate));
  }

  FrameEvent frame_callback() {
    auto retained = shared_from_this();
    delegate_storage::Scope<FrameDelegate> scope(frame_delegate, retained,
        unknown_delegate_storage);
    return FrameEvent(FrameCallable(std::move(retained)));
  }

  void retain_window(HWND window) {
    if (!window_current(window, admission.process_id) ||
        !IsWindowVisible(window) ||
        (GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOOLWINDOW)) return;
    DWORD cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                        sizeof(cloaked))) && cloaked) return;
    auto *value = append_candidate();
    if (!value) throw winrt::hresult_error(E_OUTOFMEMORY);
    value->public_value.struct_size = sizeof(value->public_value);
    value->public_value.abi_version = 1;
    value->public_value.candidate_id = mint_id();
    value->incarnation = mint_id();
    if (!value->public_value.candidate_id || !value->incarnation)
      throw winrt::hresult_error(E_OUTOFMEMORY);
    value->public_value.hwnd_value = reinterpret_cast<uint64_t>(window);
    value->public_value.process_id = admission.process_id;
    value->public_value.process_creation_filetime =
        admission.process_creation_filetime;
    auto interop = winrt::get_activation_factory<GraphicsCaptureItem,
                                                IGraphicsCaptureItemInterop>();
    winrt::check_hresult(interop->CreateForWindow(window,
        winrt::guid_of<GraphicsCaptureItem>(), winrt::put_abi(value->item)));
    // The original owner retains this slot before any COM/event registration.
    // An early Closed is recorded even before Begin publishes its array.
    value->token = value->item.Closed(closed_callback(value));
    value->registered = true;
    if (!window_current(window, admission.process_id)) value->closed = true;
    wchar_t title[256]{};
    GetWindowTextW(window, title, 256);
    char utf8[1024]{};
    const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        title, -1, utf8, sizeof(utf8), nullptr, nullptr);
    if (length > 0) {
      size_t size = std::min<size_t>(length - 1, 255);
      while (size && (static_cast<unsigned char>(utf8[size]) & 0xc0) == 0x80)
        --size;
      std::memcpy(value->public_value.title_utf8, utf8, size);
    }
  }

  MiniAVResultCode begin(const MiniAVWindowsAppAdmissionV1& original,
      MiniAVWindowsSelectionNonceV1 *out,
      MiniAVWindowsScreenCandidateV1 **out_candidates, uint32_t *count) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      const auto result = claim_locked();
      if (result != MINIAV_SUCCESS) return result;
      ++operations;
      admission = original;
      selection_deadline = std::min(original.valid_until_tick_ms,
                                    GetTickCount64() + 60000);
    }
    Operation operation(this);
    try {
      uint8_t digest = 0;
      for (auto byte : original.executable_sha256) digest |= byte;
      if (!original.host_epoch || !original.grant_generation ||
          !original.runtime_source_generation || !original.process_id ||
          !original.process_creation_filetime || !digest ||
          original.valid_until_tick_ms <= GetTickCount64() ||
          !original.admitted_process_handle ||
          static_cast<int64_t>(original.admitted_process_handle) < 0) {
        stop(MINIAV_ERROR_PERMISSION_DENIED);
        return MINIAV_ERROR_PERMISSION_DENIED;
      }
      HANDLE duplicate = nullptr;
      if (!DuplicateHandle(GetCurrentProcess(), reinterpret_cast<HANDLE>(
              original.admitted_process_handle), GetCurrentProcess(), &duplicate,
              PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0)) {
        stop(MINIAV_ERROR_PERMISSION_DENIED);
        return MINIAV_ERROR_PERMISSION_DENIED;
      }
      // The source keeps this duplicated query/wait handle until checked
      // native retirement, never a reopened PID or mutable executable path.
      {
        std::lock_guard<std::mutex> lock(mutex);
        process = duplicate;
      }
      if (!process_current()) {
        stop(MINIAV_ERROR_PERMISSION_DENIED);
        return MINIAV_ERROR_PERMISSION_DENIED;
      }
      GUID random{};
      winrt::check_hresult(CoCreateGuid(&random));
      nonce.struct_size = sizeof(nonce);
      nonce.abi_version = 1;
      std::memcpy(nonce.nonce, &random, sizeof(random));
      struct Enumeration { Owner *owner; bool failed = false; } enumeration{this};
      EnumWindows([](HWND window, LPARAM raw) -> BOOL {
        auto& pass = *reinterpret_cast<Enumeration *>(raw);
        try {
          {
            std::lock_guard<std::mutex> lock(pass.owner->mutex);
            if (!pass.owner->alive_locked()) return FALSE;
          }
          pass.owner->retain_window(window);
          return TRUE;
        } catch (...) {
          pass.failed = true;
          return FALSE;
        }
      }, reinterpret_cast<LPARAM>(&enumeration));
      if (enumeration.failed || !process_current()) {
        stop(MINIAV_ERROR_PERMISSION_DENIED);
        return MINIAV_ERROR_PERMISSION_DENIED;
      }
      // V1 retains its owned-array ABI. V2 leaves the original bounded records
      // in this Owner and copies them individually into caller-owned storage.
      MiniAVWindowsScreenCandidateV1 *values = nullptr;
      if (out_candidates && candidate_count) {
        values = static_cast<MiniAVWindowsScreenCandidateV1 *>(miniav_calloc(
            candidate_count, sizeof(MiniAVWindowsScreenCandidateV1)));
        if (!values) throw std::bad_alloc();
        for (size_t i = 0; i < candidate_count; ++i)
          values[i] = candidates[i].public_value;
      }
      bool current = false;
      {
        std::lock_guard<std::mutex> lock(mutex);
        current = alive_locked();
        if (current) {
          *out = nonce;
          if (out_candidates) *out_candidates = values;
          *count = static_cast<uint32_t>(candidate_count);
        }
      }
      if (!current) {
        if (values) miniav_free(values);
        return MINIAV_ERROR_PERMISSION_DENIED;
      }
      return MINIAV_SUCCESS;
    } catch (...) {
      stop(MINIAV_ERROR_SYSTEM_CALL_FAILED);
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }

  MiniAVResultCode copy_candidate(const MiniAVWindowsSelectionNonceV1 &supplied,
      uint32_t index, MiniAVWindowsScreenCandidateV1 *out) {
    std::lock_guard<std::mutex> lock(mutex);
    if (mode != Mode::strict || !alive_locked() || nonce_spent || operations)
      return MINIAV_ERROR_INVALID_OPERATION;
    if (std::memcmp(supplied.nonce, nonce.nonce, sizeof(nonce.nonce)))
      return MINIAV_ERROR_PERMISSION_DENIED;
    if (index >= candidate_count) return MINIAV_ERROR_INVALID_ARG;
    if (candidates[index].closed) return MINIAV_ERROR_DEVICE_LOST;
    *out = candidates[index].public_value;
    return MINIAV_SUCCESS;
  }

  // Revocation/Close can block or fail; call outside metadata/GPU locks and
  // retain a failed object instead of manufacturing a cleanup certificate.
  void discard_candidate(Candidate *value) {
    if (value->registered) {
      // The projected event remover is noexcept and discards its HRESULT.
      // Use the ABI so failed revocation cannot become a clean certificate.
      auto abi = reinterpret_cast<winrt::impl::abi_t<IGraphicsCaptureItem> *>(
          winrt::get_abi(value->item));
      const auto result = abi->remove_Closed(value->token);
      if (FAILED(result)) {
        failed(MINIAV_ERROR_SYSTEM_CALL_FAILED);
        winrt::throw_hresult(result);
      }
      value->registered = false;
    }
    value->item = nullptr;
  }

  MiniAVResultCode configure(const MiniAVWindowsSelectionNonceV1& supplied,
      uint64_t id, const MiniAVVideoInfo& requested,
      MiniAVWindowsStrictWindowWitnessV1 *out) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (mode != Mode::strict || !alive_locked() || nonce_spent || operations)
        return MINIAV_ERROR_INVALID_OPERATION;
      if (std::memcmp(supplied.nonce, nonce.nonce, sizeof(nonce.nonce)))
        return MINIAV_ERROR_PERMISSION_DENIED;
      nonce_spent = true;
      selected = id;
      ++operations;
    }
    Operation operation(this);
    try {
      chosen = find_candidate(id);
      if (!chosen_current() || !process_current()) {
        stop(MINIAV_ERROR_DEVICE_LOST);
        return MINIAV_ERROR_DEVICE_LOST;
      }
      if (requested.output_preference != MINIAV_OUTPUT_PREFERENCE_GPU ||
          requested.pixel_format != MINIAV_PIXEL_FORMAT_BGRA32 ||
          !requested.frame_rate_numerator || !requested.frame_rate_denominator) {
        stop(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
        return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
      }
      for (size_t i = 0; i < candidate_count; ++i)
        if (&candidates[i] != chosen) discard_candidate(&candidates[i]);
      const auto size = chosen->item.Size();
      if (size.Width <= 0 || size.Height <= 0 || chosen->closed)
        throw winrt::hresult_error(E_FAIL);
      uint64_t bytes = 0;
      if (!miniav::wgc_strict::frame_bytes(static_cast<uint32_t>(size.Width),
          static_cast<uint32_t>(size.Height), bytes)) {
        stop(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
        return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
      }
      adopt_device();
      format = requested;
      format.width = static_cast<uint32_t>(size.Width);
      format.height = static_cast<uint32_t>(size.Height);
      const auto new_capture_id = mint_id();
      if (!new_capture_id) throw std::bad_alloc();
      std::lock_guard<std::mutex> lock(mutex);
      if (!alive_locked() || chosen->closed) return MINIAV_ERROR_DEVICE_LOST;
      capture_id = new_capture_id;
      configured = true;
      out->struct_size = sizeof(*out);
      out->abi_version = 1;
      std::memcpy(out->selection_nonce, nonce.nonce, sizeof(nonce.nonce));
      out->capture_id = capture_id;
      out->window_incarnation = chosen->incarnation;
      out->hwnd_value = chosen->public_value.hwnd_value;
      out->process_id = admission.process_id;
      out->process_creation_filetime = admission.process_creation_filetime;
      out->host_epoch = admission.host_epoch;
      out->grant_generation = admission.grant_generation;
      out->runtime_source_generation = admission.runtime_source_generation;
      out->valid_until_tick_ms = admission.valid_until_tick_ms;
      std::memcpy(out->executable_sha256, admission.executable_sha256, 32);
      return MINIAV_SUCCESS;
    } catch (...) {
      stop(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
      return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
    }
  }

  MiniAVResultCode start(MiniAVBufferCallback target, void *data) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (!alive_locked() || !configured || start_spent || operations)
        return MINIAV_ERROR_INVALID_OPERATION;
      start_spent = true;
      ++operations;
      callback = target;
      callback_data = data;
    }
    Operation operation(this);
    try {
      if (!process_current() || !chosen_current()) {
        stop(MINIAV_ERROR_DEVICE_LOST);
        return MINIAV_ERROR_DEVICE_LOST;
      }
      const auto size = chosen->item.Size();
      const auto admitted = miniav::wgc_strict::fixed_pool(format,
          size.Width, size.Height, [&](uint32_t width, uint32_t height,
                                      uint32_t slots) {
            pool = Direct3D11CaptureFramePool::CreateFreeThreaded(rt_device,
                DirectXPixelFormat::B8G8R8A8UIntNormalized, slots,
                {static_cast<int32_t>(width), static_cast<int32_t>(height)});
            return MINIAV_SUCCESS;
          });
      if (admitted != MINIAV_SUCCESS) {
        stop(admitted);
        return admitted;
      }
      frame_token = pool.FrameArrived(frame_callback());
      frame_registered = true;
      session = pool.CreateCaptureSession(chosen->item);
      if (winrt::Windows::Foundation::Metadata::ApiInformation::IsPropertyPresent(
              L"Windows.Graphics.Capture.GraphicsCaptureSession",
              L"IsCursorCaptureEnabled")) {
        session.IsCursorCaptureEnabled(cursor);
      } else if (!cursor) {
        stop(MINIAV_ERROR_NOT_SUPPORTED);
        return MINIAV_ERROR_NOT_SUPPORTED;
      }
      miniav_dispatch_set_enabled(1);
      {
        std::lock_guard<std::mutex> lock(mutex);
        if (!alive_locked() || chosen->closed)
          return MINIAV_ERROR_DEVICE_LOST;
        started = true;
      }
      session.StartCapture();
      std::lock_guard<std::mutex> lock(mutex);
      return alive_locked() ? MINIAV_SUCCESS : MINIAV_ERROR_PERMISSION_DENIED;
    } catch (...) {
      stop(MINIAV_ERROR_DEVICE_LOST);
      return MINIAV_ERROR_DEVICE_LOST;
    }
  }

  MiniAVResultCode release_payload(MiniAVNativeBufferInternalPayload *internal) {
    if (!internal) return MINIAV_ERROR_INVALID_ARG;
    FrameSlot *slot = nullptr;
    Holder retained;
    bool was_posted = false;
    {
      std::lock_guard<std::mutex> lock(mutex);
      // Compare addresses before dereferencing any caller-provided payload.
      for (auto &candidate : frames)
        if (&candidate.internal == internal) { slot = &candidate; break; }
      if (!slot) return MINIAV_ERROR_INVALID_HANDLE;
      if (slot->phase == FramePhase::quarantined)
        return MINIAV_ERROR_SYSTEM_CALL_FAILED;
      if (slot->phase != FramePhase::ready)
        return MINIAV_ERROR_INVALID_OPERATION;
      if (internal->native_singular_resource_ptr != &slot->payload ||
          internal->parent_miniav_buffer_ptr != &slot->buffer ||
          internal->context_owner != parent ||
          internal->handle_type != MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN ||
          slot->buffer.internal_handle != internal ||
          slot->payload.owner.get() != this)
        return MINIAV_ERROR_INVALID_HANDLE;
      retained = slot->payload.owner; // Protect slot and release epilogue.
      was_posted = slot->payload.posted;
      slot->phase = FramePhase::releasing;
      ++releases;
    }
    auto *payload = &slot->payload;
    if (payload->release_failed ||
        (payload->handle && !CloseHandle(payload->handle))) {
      payload->release_failed = true;
      failed(MINIAV_ERROR_SYSTEM_CALL_FAILED);
      std::lock_guard<std::mutex> lock(mutex);
      slot->phase = FramePhase::quarantined;
      --releases;
      return MINIAV_ERROR_SYSTEM_CALL_FAILED; // Keep slot/resources/debt.
    }
    payload->handle = nullptr;
    payload->snapshot = nullptr;
    payload->owner.reset();
    // Last context/owner use of the release call. The raw parent survives until
    // both counters are zero; no epilogue reads a returned/reusable slot.
    std::lock_guard<std::mutex> lock(mutex);
    slot->phase = FramePhase::empty;
    --buffers;
    --releases;
    if (was_posted) ++released;
    changed.notify_all();
    return MINIAV_SUCCESS; // Consumed even if another slot quarantined source.
  }

  // Called only after exact completion/Close by publish. Shared with the cold
  // ownership witness; constructing an envelope grants no GPU/publication right.
  FrameSlot *wrap_pending_frame() {
    if (!pending || !pending->issued || !pending->complete || pending->frame ||
        pending->source || pending->query) return nullptr;
    auto *slot = prepare_frame();
    if (!slot) return nullptr; // Pending and all its resources remain owned.
    auto *buffer = &slot->buffer;
    auto *internal = &slot->internal;
    auto *payload = &slot->payload;
    payload->snapshot = std::move(pending->snapshot);
    payload->handle = pending->handle;
    pending->handle = nullptr;
    buffer->type = MINIAV_BUFFER_TYPE_VIDEO;
    buffer->content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE;
    buffer->timestamp_us = pending->timestamp;
    buffer->data.video.info = format;
    buffer->data.video.info.width = pending->width;
    buffer->data.video.info.height = pending->height;
    buffer->data.video.num_planes = 1;
    auto& plane = buffer->data.video.planes[0];
    plane.data_ptr = payload->handle;
    plane.width = pending->width;
    plane.height = pending->height;
    plane.dmabuf_fd = -1;
    plane.drm_format_modifier = wgc_frame_import_tag(true, S_OK);
    internal->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
    internal->context_owner = parent;
    internal->native_singular_resource_ptr = payload;
    internal->parent_miniav_buffer_ptr = buffer;
    buffer->internal_handle = internal;
    pending.reset();
    {
      std::lock_guard<std::mutex> lock(mutex);
      slot->phase = FramePhase::ready;
    }
    return slot;
  }

  void publish() {
    // Exact S_OK has already been observed on the native executor. Close the
    // WGC frame before publication; only the fresh immutable snapshot escapes.
    close_frame(pending->frame);
    pending->source = nullptr;
    pending->query = nullptr;
    auto *slot = wrap_pending_frame();
    if (!slot) {
      failed(MINIAV_ERROR_INVALID_OPERATION);
      return;
    }
    auto *buffer = &slot->buffer;
    auto *internal = &slot->internal;
    auto *payload = &slot->payload;
    DispatchLease dispatch;
    if (!dispatch.held) {
      release_payload(internal);
      return;
    }
    MiniAVBufferCallback target = nullptr;
    void *data = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (alive_locked()) {
        target = callback;
        data = callback_data;
        payload->posted = true;
        ++posted;
        ++callbacks;
      }
    }
    if (target) {
      // A listener may queue delivery and return immediately. That buffer's
      // charge remains until its actual MiniAV_ReleaseBuffer, even after Stop.
      Invocation entered(shared_from_this(), true);
      target(buffer, data);
    } else {
      release_payload(internal);
    }
  }

  void close_frame(Direct3D11CaptureFrame& frame) {
    if (!frame) return;
    try {
      frame.Close();
      frame = nullptr;
    } catch (...) {
      // Keep the failed frame in pending, and keep failure sticky even if a
      // later Close could succeed. Ordinary capture-stop recovery is weaker.
      failed(MINIAV_ERROR_SYSTEM_CALL_FAILED);
      throw;
    }
  }

  // Creates the copy fence and its event on first use. False, from then on,
  // when the device has no fences: copies are then reported by event queries.
  bool fence_ready() {
    if (fence) return true;
    if (fence_unavailable) return false;
    fence_unavailable = true;
    const auto device5 = device.try_as<ID3D11Device5>();
    auto context4 = immediate.try_as<ID3D11DeviceContext4>();
    winrt::com_ptr<ID3D11Fence> created;
    if (!device5 || !context4 ||
        FAILED(device5->CreateFence(0, D3D11_FENCE_FLAG_NONE,
                                    __uuidof(ID3D11Fence), created.put_void())))
      return false;
    copied = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!copied) return false;
    fence = std::move(created);
    fence_context = std::move(context4);
    fence_unavailable = false;
    return true;
  }

  bool complete_pending(bool deliver) {
    if (!pending) return true;
    if (pending->issued && !pending->complete) {
      if (pending->fence_value) {
        // A removed device reads as UINT64_MAX, or never finishes the copy.
        const auto reached = fence->GetCompletedValue();
        if (reached == UINT64_MAX ||
            (reached < pending->fence_value &&
             device->GetDeviceRemovedReason() != S_OK)) {
          failed(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
          return false; // Retain all issued GPU work; never infer completion.
        }
        if (reached < pending->fence_value) return false;
      } else if (pending->query) {
        const auto result = immediate->GetData(pending->query.get(), nullptr, 0,
                                               D3D11_ASYNC_GETDATA_DONOTFLUSH);
        if (result == S_FALSE) return false;
        if (result != S_OK) {
          failed(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
          return false; // Retain all issued GPU work; never infer completion.
        }
      } else {
        return false; // Nothing reports this copy's end (see admit).
      }
      pending->complete = true;
    }
    if (deliver) {
      publish();
    } else {
      close_frame(pending->frame);
      if (pending->handle && !CloseHandle(pending->handle))
        throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()));
      pending->handle = nullptr;
      pending.reset();
    }
    return true;
  }

  // The one geometry rule. It runs as each frame arrives, so a resize stops
  // the source even while every buffer is out, and again with `copy`, which
  // takes the frame's single GPU snapshot into pending.
  MiniAVResultCode admit(Direct3D11CaptureFrame const& frame, bool copy) {
    winrt::com_ptr<ID3D11Texture2D> texture;
    auto access = frame.Surface().as<
        ::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    winrt::check_hresult(access->GetInterface(
        __uuidof(ID3D11Texture2D), texture.put_void()));
    D3D11_TEXTURE2D_DESC source{};
    texture->GetDesc(&source);
    const auto size = frame.ContentSize();
    return miniav::wgc_strict::fixed_snapshot(format,
        size.Width, size.Height, source.Width, source.Height,
        source.Format == DXGI_FORMAT_B8G8R8A8_UNORM, source.MipLevels,
        source.ArraySize, source.SampleDesc.Count, source.SampleDesc.Quality,
        [&](uint32_t width, uint32_t height) {
          if (!copy) return MINIAV_SUCCESS;
          pending->source = std::move(texture);
          pending->width = width;
          pending->height = height;
          pending->timestamp = frame.SystemRelativeTime().count() / 10;
          D3D11_TEXTURE2D_DESC snapshot{};
          snapshot.Width = width;
          snapshot.Height = height;
          snapshot.MipLevels = snapshot.ArraySize = snapshot.SampleDesc.Count = 1;
          snapshot.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
          snapshot.Usage = D3D11_USAGE_DEFAULT;
          snapshot.BindFlags = D3D11_BIND_SHADER_RESOURCE;
          snapshot.MiscFlags = D3D11_RESOURCE_MISC_SHARED_NTHANDLE |
                               D3D11_RESOURCE_MISC_SHARED;
          winrt::check_hresult(device->CreateTexture2D(&snapshot, nullptr,
                                                     pending->snapshot.put()));
          // No copy submission until the snapshot and a way to see the copy
          // finish (the fence, else an event query) are both admitted.
          const bool fenced = fence_ready();
          if (!fenced) {
            D3D11_QUERY_DESC query{D3D11_QUERY_EVENT, 0};
            winrt::check_hresult(device->CreateQuery(&query, pending->query.put()));
          }
          auto resource = pending->snapshot.as<IDXGIResource1>();
          winrt::check_hresult(resource->CreateSharedHandle(nullptr,
              DXGI_SHARED_RESOURCE_READ, nullptr, &pending->handle));
          D3D11_BOX bounds{0, 0, 0, width, height, 1};
          pending->issued = true;
          immediate->CopySubresourceRegion(pending->snapshot.get(), 0, 0, 0, 0,
                                          pending->source.get(), 0, &bounds);
          if (!fenced) {
            immediate->End(pending->query.get());
            immediate->Flush();
            return MINIAV_SUCCESS;
          }
          if (FAILED(fence_context->Signal(fence.get(), fence_value + 1))) {
            // The copy is issued and nothing can report its end.
            failed(MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
            return MINIAV_SUCCESS;
          }
          pending->fence_value = ++fence_value;
          immediate->Flush();
          // A completion seen by polling can leave the event set; clear it so
          // this copy's wait does not end at once.
          ResetEvent(copied);
          pending->armed = SUCCEEDED(fence->SetEventOnCompletion(fence_value, copied));
          return MINIAV_SUCCESS;
        });
  }

  void pump() {
    if (!complete_pending(true)) return;
    bool arrived;
    uint32_t outstanding;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (!alive_locked()) return;
      arrived = frame_ready;
      frame_ready = false;
      outstanding = buffers;
    }
    // FrameArrived coalesces, so take every frame the pool holds and keep the
    // newest. No more than the pool's slots can have arrived before the flag
    // was cleared; a later arrival sets it again. Every acquired frame stays
    // owned until its Close succeeds, and a failed Close is sticky.
    for (uint32_t i = 0; arrived && i < miniav::wgc_strict::pool_slots; ++i) {
      arriving = pool.TryGetNextFrame();
      if (!arriving) break;
      close_frame(latest);
      latest = std::move(arriving);
      const auto checked = admit(latest, false);
      if (checked != MINIAV_SUCCESS) {
        stop(checked); // Cleanup closes the retained frame; never resize/retry.
        return;
      }
    }
    if (!latest || outstanding >= max_outstanding_buffers) return;
    const auto now = qpc_now();
    if (now < next_due) return;
    // An absolute schedule holds the requested rate; after a gap it restarts
    // from now instead of bursting to catch up.
    const auto interval = int64_t(format.frame_rate_denominator) * 10000000 /
                          format.frame_rate_numerator;
    next_due = now - next_due < interval ? next_due + interval : now + interval;
    if (!prepare_pending()) {
      failed(MINIAV_ERROR_INVALID_OPERATION);
      return;
    }
    pending->frame = std::move(latest);
    const auto admitted = admit(pending->frame, true);
    if (admitted != MINIAV_SUCCESS) {
      stop(admitted); // Cleanup closes the retained frame; never resize/retry.
      return;
    }
    complete_pending(true); // Pending remains owned and bounded to one copy.
  }

  void notify_lost() {
    MiniAVContextLostCallback target = nullptr;
    void *data = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (reason && !lost_notified) {
        lost_notified = true;
        target = lost;
        data = lost_data;
        if (target) ++callbacks;
      }
    }
    if (!target) return;
    Invocation entered(shared_from_this(), true);
    DispatchLease dispatch;
    if (dispatch.held) {
      target(reason, data);
    }
  }

  void cleanup() {
    notify_lost();
    // No metadata lock is held across event revocation, Close, COM release,
    // GPU polling or callback/queued-delegate/buffer waits.
    if (frame_registered) {
      auto abi = reinterpret_cast<
          winrt::impl::abi_t<IDirect3D11CaptureFramePool> *>(winrt::get_abi(pool));
      const auto result = abi->remove_FrameArrived(frame_token);
      if (FAILED(result)) {
        failed(MINIAV_ERROR_SYSTEM_CALL_FAILED);
        winrt::throw_hresult(result);
      }
      frame_registered = false;
    }
    for (size_t i = 0; i < candidate_count; ++i)
      discard_candidate(&candidates[i]);
    if (session) {
      session.Close();
      session = nullptr;
    }
    for (;;) {
      std::unique_lock<std::mutex> lock(mutex);
      if (state == 3) return;
      if (!callbacks) break;
      changed.wait_for(lock, 1ms);
    }
    if (!complete_pending(false)) return;
    close_frame(latest);
    if (pool) {
      pool.Close();
      pool = nullptr;
    }
    chosen = nullptr;
    // Keep slots/IDs constructed for late queued Closed delegates. Their
    // tickets retain this Owner; only actual Owner destruction ends the slots.
    {
      std::lock_guard<std::mutex> lock(mutex);
      producer_closed = true;
    }
    for (;;) {
      std::unique_lock<std::mutex> lock(mutex);
      if (state == 3) return;
      if (!callbacks && !delegates && !buffers && !releases) break;
      changed.wait_for(lock, 10ms);
    }
    // A stopped-before-Begin context also transfers/releases its original
    // unstarted device here. No generic D3D references survive the receipt.
    adopt_device();
    fence = nullptr;
    fence_context = nullptr;
    rt_device = nullptr;
    immediate = nullptr;
    device = nullptr;
    if (copied && !CloseHandle(copied))
      throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()));
    copied = nullptr;
    if (process && !CloseHandle(process))
      throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()));
    process = nullptr;
    std::lock_guard<std::mutex> lock(mutex);
    if (state != 3 && !callbacks && !delegates && !buffers && !releases &&
        posted == released) state = 2;
    changed.notify_all();
  }

  void run() noexcept {
    bool apartment = false;
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      apartment = true;
      for (;;) {
        bool stopping, can_pump;
        {
          std::unique_lock<std::mutex> lock(mutex);
          alive_locked();
          if (state == 3) break;
          stopping = terminal;
          if (operations) {
            changed.wait_for(lock, 1ms);
            continue;
          }
          can_pump = started && !stopping;
        }
        // Once started, `chosen` changes only on this thread, in cleanup.
        if (!stopping && ((process && !process_current()) ||
                          (can_pump && !chosen_current()))) {
          stop(MINIAV_ERROR_DEVICE_LOST);
          continue;
        }
        if (stopping) {
          cleanup();
          std::lock_guard<std::mutex> lock(mutex);
          if (state == 2 || state == 3) break;
        } else if (can_pump) {
          try { pump(); }
          catch (...) { stop(MINIAV_ERROR_FORMAT_NOT_SUPPORTED); }
        }
        // A copy in flight blocks every other step, so its event is all the
        // worker waits for. A frame that arrived during the pass is taken at
        // once; a held frame, or a copy only a query reports, is rechecked
        // within a millisecond.
        if (pending && pending->armed && !pending->complete) {
          WaitForSingleObject(copied, 10);
          continue;
        }
        std::unique_lock<std::mutex> lock(mutex);
        if (terminal || !frame_ready)
          changed.wait_for(lock, pending || latest ? 1ms : 10ms);
      }
    } catch (...) {
      failed(MINIAV_ERROR_SYSTEM_CALL_FAILED);
    }
    if (apartment) winrt::uninit_apartment();
  }
};

void *ClosedCallable::operator new(size_t bytes) {
  return delegate_storage::allocate<ClosedDelegate>(bytes);
}
void ClosedCallable::operator delete(void *address) noexcept {
  delegate_storage::release<ClosedDelegate>(address);
}
void ClosedCallable::operator()(GraphicsCaptureItem const&,
    winrt::Windows::Foundation::IInspectable const&) const {
  Invocation entered(ticket.owner);
  ticket.owner->item_closed(candidate);
}
void *FrameCallable::operator new(size_t bytes) {
  return delegate_storage::allocate<FrameDelegate>(bytes);
}
void FrameCallable::operator delete(void *address) noexcept {
  delegate_storage::release<FrameDelegate>(address);
}
void FrameCallable::operator()(Direct3D11CaptureFramePool const&,
    winrt::Windows::Foundation::IInspectable const&) const {
  Invocation entered(ticket.owner);
  std::lock_guard<std::mutex> lock(ticket.owner->mutex);
  if (ticket.owner->alive_locked()) {
    ticket.owner->frame_ready = true;
    ticket.owner->changed.notify_all();
  }
}
void unknown_delegate_storage(void *value) noexcept {
  try { static_cast<Owner *>(value)->failed(MINIAV_ERROR_SYSTEM_CALL_FAILED); }
  catch (...) {} // Retained original storage still prevents a fabricated refund.
}

DelegateTicket::DelegateTicket(Holder value) : owner(std::move(value)) {
  if (!owner) return;
  std::lock_guard<std::mutex> lock(owner->mutex);
  ++owner->delegates;
}
DelegateTicket::DelegateTicket(const DelegateTicket &value)
    : DelegateTicket(value.owner) {}
DelegateTicket::DelegateTicket(DelegateTicket &&value) noexcept
    : owner(std::move(value.owner)) {}
DelegateTicket::~DelegateTicket() {
  if (!owner) return;
  std::lock_guard<std::mutex> lock(owner->mutex);
  --owner->delegates;
  owner->changed.notify_all();
}
Invocation::Invocation(Holder value, bool already_charged)
    : owner(std::move(value)) {
  if (!already_charged) {
    std::lock_guard<std::mutex> lock(owner->mutex);
    ++owner->callbacks;
  }
}
Invocation::~Invocation() {
  std::lock_guard<std::mutex> lock(owner->mutex);
  --owner->callbacks;
  owner->changed.notify_all();
}

using StorageTicket = miniav::wgc_owner_storage::Ticket;
using StorageEvent = miniav::wgc_owner_storage::Event;
struct HolderBox {
  Holder owner;
  StorageTicket ticket;
  HolderBox(Holder value, StorageTicket funding = {}) noexcept
      : owner(std::move(value)), ticket(std::move(funding)) {}
};
Holder get(void *value) { return static_cast<HolderBox *>(value)->owner; }

miniav::wgc_owner_storage::Extent holder_storage_extent() noexcept {
  return {sizeof(HolderBox), alignof(HolderBox)};
}

} // namespace

MiniAVResultCode miniav_wgc_strict_owner_storage_profile(
    MiniAVWindowsStrictOwnerStorageProfileV1 *out) {
  if (!out) return MINIAV_ERROR_INVALID_ARG;
  *out = {};
  using namespace miniav::wgc_owner_storage;
  const auto holder = holder_storage_extent();
  const auto owner = shared_extent<Owner>();
  if (!layout_supported || !holder.bytes || !owner.bytes ||
      holder.bytes > UINT64_MAX - owner.bytes) return MINIAV_ERROR_NOT_SUPPORTED;
  static_assert(sizeof(MiniAVWindowsStrictOwnerStorageProfileV1) == 128);
  static_assert(offsetof(MiniAVWindowsStrictOwnerStorageProfileV1, roles) == 80);
  out->struct_size = sizeof(*out);
  out->abi_version = 1;
  out->factory_revision = 1;
  out->flags = 3;
  identity(out->build_identity);
  out->role_count = out->additional_resources = 2;
  out->total_requested_bytes = holder.bytes + owner.bytes;
  out->roles[0] = {0, holder.alignment, holder.bytes, 0};
  out->roles[1] = {1, owner.alignment, owner.bytes, 0};
  return MINIAV_SUCCESS;
}

void *miniav_wgc_strict_create(MiniAVScreenContext *parent, void *platform,
                               MiniAVWgcTakeDevice take_device) {
  try { return new HolderBox(std::make_shared<Owner>(parent, platform, take_device)); }
  catch (...) { return nullptr; }
}

MiniAVResultCode miniav_wgc_strict_create_funded(
    MiniAVScreenContext *parent, void *platform, MiniAVWgcTakeDevice take_device,
    const StorageTicket &holder_ticket, const StorageTicket &owner_ticket,
    void **out) noexcept {
  if (!out) return MINIAV_ERROR_INVALID_ARG;
  *out = nullptr;
  using namespace miniav::wgc_owner_storage;
  if (!layout_supported) return MINIAV_ERROR_NOT_SUPPORTED;
  // Validate the COMPLETE pair before either allocation or payload constructor.
  if (!holder_ticket.role(0) || !owner_ticket.role(1) ||
      !holder_ticket.same_transaction(owner_ticket) ||
      !holder_ticket.matches(holder_storage_extent()) ||
      !owner_ticket.matches(shared_extent<Owner>())) return MINIAV_ERROR_INVALID_ARG;
  Pending holder_pending(holder_ticket), owner_pending(owner_ticket);
  try {
    auto owner = miniav::wgc_owner_storage::make_shared<Owner>(
        owner_ticket, parent, platform, take_device);
    Allocator<HolderBox> allocator(holder_ticket);
    auto *box = allocator.allocate(1);
    try { allocator.construct(box, std::move(owner), holder_ticket); }
    catch (...) { allocator.deallocate(box, 1); throw; }
    *out = box;
    return MINIAV_SUCCESS;
  } catch (const std::bad_alloc &) { return MINIAV_ERROR_OUT_OF_MEMORY; }
  catch (miniav::wgc_owner_storage::Error error) {
    return error == miniav::wgc_owner_storage::Error::Refused ? MINIAV_ERROR_INVALID_OPERATION
                                   : MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  catch (...) {
    // Constructor exceptions have completed member rollback. Allocator storage
    // still follows its genuine deallocation receipts, never invented join.
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
}

MiniAVResultCode miniav_wgc_strict_delete(void *holder) {
  if (!holder) return MINIAV_ERROR_INVALID_ARG;
  auto *box = static_cast<HolderBox *>(holder);
  if (!box->ticket) { delete box; return MINIAV_SUCCESS; }
  // Preserve actual owner and callback authority through payload destruction,
  // matching Box free, and all callback tails. No source lock is held here.
  Holder retained = box->owner;
  StorageTicket ticket = box->ticket;
  box->~HolderBox();
  const bool disposed = ticket.notify(StorageEvent::Disposed);
  if (!disposed || !ticket.begin_free(box, sizeof(HolderBox), alignof(HolderBox))) {
    // Same allocation and readable owner survive any pre-free refusal. The
    // quarantined ledger cannot refund or accept another allocation attempt.
    ::new (static_cast<void *>(box)) HolderBox(std::move(retained), ticket);
    if (!disposed) ticket.quarantine(); // begin_free already retains its own refusal.
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  ticket.free_returned(box, alignof(HolderBox));
  return MINIAV_SUCCESS; // Actual free consumed the pointer; no dangling retry.
}

bool miniav_wgc_strict_claimed(void *holder) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  return owner->mode == Mode::strict;
}

MiniAVResultCode miniav_wgc_strict_claim_generic(void *holder) {
  // A funded private strict owner must never fall back into generic capture.
  if (static_cast<HolderBox *>(holder)->ticket) return MINIAV_ERROR_INVALID_OPERATION;
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode == Mode::strict) return MINIAV_ERROR_INVALID_OPERATION;
  owner->mode = Mode::generic;
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_prepare_destroy(void *holder) {
  auto owner = get(holder);
  {
    std::lock_guard<std::mutex> lock(owner->mutex);
    if (owner->mode != Mode::strict) return MINIAV_SUCCESS;
    if (owner->state == 3) return static_cast<MiniAVResultCode>(owner->cleanup_error);
    owner->stop_locked(0);
    if (owner->state != 2) return MINIAV_ERROR_TIMEOUT;
  }
  if (owner->worker.joinable()) owner->worker.join();
  return MINIAV_SUCCESS;
}

void miniav_wgc_strict_cleanup_failed(void *holder, MiniAVResultCode error) {
  get(holder)->failed(error);
}

MiniAVResultCode miniav_wgc_strict_start(void *holder,
    MiniAVBufferCallback callback, void *user_data, bool *handled) {
  auto owner = get(holder);
  {
    std::lock_guard<std::mutex> lock(owner->mutex);
    *handled = owner->mode == Mode::strict;
    if (!*handled) {
      owner->mode = Mode::generic;
      return MINIAV_SUCCESS;
    }
  }
  return owner->start(callback, user_data);
}

MiniAVResultCode miniav_wgc_strict_stop(void *holder, bool *handled) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  *handled = owner->mode == Mode::strict;
  if (*handled) owner->stop_locked(0);
  else owner->mode = Mode::generic;
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_set_lost(void *holder,
    MiniAVContextLostCallback callback, void *user_data) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode == Mode::strict) {
    if (owner->terminal || owner->start_spent) return MINIAV_ERROR_INVALID_OPERATION;
    owner->lost = callback;
    owner->lost_data = user_data;
  } else {
    owner->parent->lost_cb = callback;
    owner->parent->lost_cb_user_data = user_data;
  }
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_set_cursor(void *holder, bool enabled) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode == Mode::strict) {
    if (owner->terminal || owner->nonce_spent) return MINIAV_ERROR_INVALID_OPERATION;
    owner->cursor = enabled;
  } else {
    if (owner->parent->is_configured) return MINIAV_ERROR_INVALID_OPERATION;
    owner->parent->capture_cursor = enabled;
  }
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_formats(void *holder,
    MiniAVVideoInfo *video, MiniAVAudioInfo *audio) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (audio) std::memset(audio, 0, sizeof(*audio));
  if (owner->mode == Mode::strict) {
    if (!owner->configured || owner->terminal) return MINIAV_ERROR_NOT_CONFIGURED;
    *video = owner->format;
  } else {
    *video = owner->parent->configured_video_format;
    if (audio) *audio = owner->parent->configured_audio_format;
    if (!video->width || !video->height) return MINIAV_ERROR_NOT_CONFIGURED;
  }
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_release(void *holder,
    MiniAVNativeBufferInternalPayload *internal) {
  auto owner = get(holder);
  return owner->release_payload(internal);
}

MiniAVResultCode miniav_wgc_strict_capabilities(uint32_t *bits, uint64_t *tick) {
#if defined(_M_X64) || defined(__x86_64__)
  if (miniav_com_legacy_percall()) return MINIAV_ERROR_NOT_SUPPORTED;
  try {
    miniav_com_ensure_mta();
    if (!GraphicsCaptureSession::IsSupported()) return MINIAV_ERROR_NOT_SUPPORTED;
    const auto now = GetTickCount64();
    if (!now) return MINIAV_ERROR_NOT_SUPPORTED;
    *bits = 15;
    *tick = now;
    return MINIAV_SUCCESS;
  } catch (...) {}
#endif
  return MINIAV_ERROR_NOT_SUPPORTED;
}

MiniAVResultCode miniav_wgc_strict_max_outstanding_buffers(uint32_t *maximum) {
  if (!maximum) return MINIAV_ERROR_INVALID_ARG;
  *maximum = max_outstanding_buffers;
  return MINIAV_SUCCESS; // No COM, context, capture or graphics initialization.
}

MiniAVResultCode miniav_wgc_strict_resource_profile(void *holder,
    MiniAVWindowsStrictResourceProfileV1 *profile) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode != Mode::strict || !owner->configured || owner->operations ||
      owner->start_spent || !owner->alive_locked() || !owner->chosen)
    return MINIAV_ERROR_NOT_CONFIGURED;
  uint64_t bytes = 0;
  if (!miniav::wgc_strict::frame_bytes(owner->format.width, owner->format.height, bytes))
    return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
  *profile = {sizeof(*profile), 1, owner->capture_id, owner->chosen->incarnation,
      owner->format.width, owner->format.height, MINIAV_PIXEL_FORMAT_BGRA32,
      miniav::wgc_strict::pool_slots, max_outstanding_buffers, 1, bytes, 0};
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_begin(void *holder,
    const MiniAVWindowsAppAdmissionV1 *admission,
    MiniAVWindowsSelectionNonceV1 *nonce,
    MiniAVWindowsScreenCandidateV1 **candidates, uint32_t *count) {
  return get(holder)->begin(*admission, nonce, candidates, count);
}

MiniAVResultCode miniav_wgc_strict_copy_candidate(void *holder,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint32_t index,
    MiniAVWindowsScreenCandidateV1 *candidate) {
  return get(holder)->copy_candidate(*nonce, index, candidate);
}

MiniAVResultCode miniav_wgc_strict_configure(void *holder,
    const MiniAVWindowsSelectionNonceV1 *nonce, uint64_t candidate_id,
    const MiniAVVideoInfo *format, MiniAVWindowsStrictWindowWitnessV1 *witness) {
  return get(holder)->configure(*nonce, candidate_id, *format, witness);
}

MiniAVResultCode miniav_wgc_strict_request_stop(void *holder, int32_t reason) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode == Mode::generic) return MINIAV_ERROR_INVALID_OPERATION;
  if (owner->mode == Mode::fresh) {
    const auto result = owner->claim_locked();
    if (result != MINIAV_SUCCESS) return result;
  }
  owner->stop_locked(reason);
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_retirement(void *holder,
    MiniAVWindowsStrictRetirementV1 *receipt) {
  auto owner = get(holder);
  std::lock_guard<std::mutex> lock(owner->mutex);
  if (owner->mode != Mode::strict) return MINIAV_ERROR_INVALID_OPERATION;
  owner->alive_locked();
  receipt->struct_size = sizeof(*receipt);
  receipt->abi_version = 1;
  receipt->capture_id = owner->capture_id;
  receipt->state = owner->state;
  receipt->terminal_reason = owner->reason;
  receipt->cleanup_error = owner->cleanup_error;
  receipt->callbacks_in_flight = owner->callbacks + owner->delegates;
  receipt->buffers_outstanding = owner->buffers;
  receipt->frames_posted = owner->posted;
  receipt->frames_released = owner->released;
  receipt->flags = owner->terminal ? 1 : 0;
  if (owner->producer_closed) receipt->flags |= 2;
  if (owner->state == 2) receipt->flags = 31;
  return MINIAV_SUCCESS;
}
