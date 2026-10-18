// Running qualification of the strict window source against a real window.
// A child process (this executable, --window) owns the only admitted window;
// the parent is the trusted host. It captures that window through the
// production provider and reads pixels back through the published handles.
// The window is a flat dark fill whose colour moves by ONE level per change,
// so nothing visible flashes. It sits off-screen when Windows still composes
// it there, else in the corner of the primary work area.
// Last, ordinary (generic) window capture of the same kind of window must
// notice the window closing, which Windows does not report for it.
// Exit 77 means the environment refused (no WGC, or no frames at all).
// --adapters lists the DXGI adapters; the provider captures on adapter 0.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "../../../include/miniav.h"
#include <windows.h>
#include <d3d11_1.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <memory>
#include <mutex>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {
constexpr int window_width = 320, window_height = 240;
constexpr wchar_t window_class[] = L"MiniAVStrictQualification";
constexpr wchar_t window_title[] = L"miniav strict qualification";
// Child controls: hold a final fill (wParam selects it), resume changing.
constexpr UINT hold_message = WM_APP, resume_message = WM_APP + 1;

[[noreturn]] void fail(const char *what) {
  std::fflush(stdout);
  std::fprintf(stderr, "FAIL %s\n", what);
  std::fflush(stderr);
  // A capture worker may still be running: skip process-exit teardown. The
  // job object ends the window process with this one.
  TerminateProcess(GetCurrentProcess(), 1);
  for (;;) Sleep(INFINITE);
}
void require(bool value, const char *what) {
  if (!value) fail(what);
}
uint64_t filetime_value(FILETIME value) {
  return (uint64_t(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
// Microseconds on the QPC timeline, the clock of buffer timestamps.
int64_t qpc_us() {
  LARGE_INTEGER count{}, frequency{};
  QueryPerformanceCounter(&count);
  QueryPerformanceFrequency(&frequency);
  return count.QuadPart / frequency.QuadPart * 1000000 +
         count.QuadPart % frequency.QuadPart * 1000000 / frequency.QuadPart;
}

// ---------------------------------------------------------------------------
// Child: the admitted application.
struct Fill {
  bool changing = true;
  unsigned phase = 0;
  WPARAM hold = 0;
} fill;
HWND target = nullptr;

COLORREF fill_colour() {
  // Changing: red alternates 48/49. Held fill k: green 49, blue 48 + (k & 1).
  if (fill.changing) return RGB(48 + (fill.phase & 1), 48, 48);
  return RGB(48, 49, 48 + (fill.hold & 1));
}

LRESULT CALLBACK child_procedure(HWND window, UINT message, WPARAM w, LPARAM l) {
  switch (message) {
  case WM_PAINT: {
    PAINTSTRUCT paint;
    HDC dc = BeginPaint(window, &paint);
    RECT client{};
    GetClientRect(window, &client);
    HBRUSH brush = CreateSolidBrush(fill_colour());
    FillRect(dc, &client, brush);
    DeleteObject(brush);
    EndPaint(window, &paint);
    return 0;
  }
  case WM_ERASEBKGND:
    return 1;
  case WM_MOUSEACTIVATE:
    return MA_NOACTIVATE;
  case hold_message:
    fill.changing = false;
    fill.hold = w;
    InvalidateRect(window, nullptr, FALSE);
    return 0;
  case resume_message:
    fill.changing = true;
    return 0;
  case WM_CLOSE:
    DestroyWindow(window); // The process stays alive.
    return 0;
  case WM_DESTROY:
    if (window == target) target = nullptr;
    return 0;
  }
  return DefWindowProcW(window, message, w, l);
}

int child_main(int x, int y, DWORD parent_id) {
  HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, parent_id);
  WNDCLASSEXW type{sizeof(type)};
  type.lpfnWndProc = child_procedure;
  type.hInstance = GetModuleHandleW(nullptr);
  type.hCursor = LoadCursor(nullptr, IDC_ARROW);
  type.lpszClassName = window_class;
  if (!RegisterClassExW(&type)) return 2;
  // A hidden owner keeps the target off the taskbar. It is never visible, so
  // the provider never offers it.
  HWND owner = CreateWindowExW(0, window_class, L"", WS_POPUP, 0, 0, 0, 0,
                               nullptr, nullptr, type.hInstance, nullptr);
  target = CreateWindowExW(WS_EX_NOACTIVATE, window_class, window_title,
                           WS_POPUP, x, y, window_width, window_height, owner,
                           nullptr, type.hInstance, nullptr);
  if (!owner || !target) return 3;
  ShowWindow(target, SW_SHOWNOACTIVATE);
  UpdateWindow(target);
  HANDLE timer = CreateWaitableTimerExW(nullptr, nullptr,
      CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
  LARGE_INTEGER due{};
  due.QuadPart = -80000; // 8 ms: faster than common refresh rates.
  if (timer && !SetWaitableTimer(timer, &due, 8, nullptr, nullptr, FALSE)) {
    CloseHandle(timer);
    timer = nullptr;
  }
  const auto until = GetTickCount64() + 300000; // Never outlive a lost host.
  while (GetTickCount64() < until) {
    if (parent && WaitForSingleObject(parent, 0) != WAIT_TIMEOUT) break;
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    if (target && fill.changing) {
      ++fill.phase;
      InvalidateRect(target, nullptr, FALSE);
      UpdateWindow(target);
    }
    if (timer) MsgWaitForMultipleObjects(1, &timer, FALSE, 100, QS_ALLINPUT);
    else Sleep(8);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Parent: the trusted host, its listener and a consumer device.
HANDLE job = nullptr;
POINT origin{};

struct Child {
  PROCESS_INFORMATION process{};
  HANDLE query = nullptr; // The original query/wait handle the host admits.
  HWND window = nullptr;
  uint64_t created = 0;
};

struct Search {
  DWORD process_id;
  HWND found;
};

BOOL CALLBACK find_target(HWND window, LPARAM raw) {
  auto &search = *reinterpret_cast<Search *>(raw);
  DWORD owner = 0;
  wchar_t title[64]{};
  GetWindowThreadProcessId(window, &owner);
  GetWindowTextW(window, title, 64);
  if (owner != search.process_id || !IsWindowVisible(window) ||
      std::wcscmp(title, window_title))
    return TRUE;
  search.found = window;
  return FALSE;
}

std::unique_ptr<Child> spawn() {
  wchar_t path[MAX_PATH]{};
  require(GetModuleFileNameW(nullptr, path, MAX_PATH) > 0, "own executable path");
  wchar_t command[2 * MAX_PATH]{};
  std::swprintf(command, sizeof(command) / sizeof(command[0]),
                L"\"%ls\" --window %ld %ld %lu", path, origin.x, origin.y,
                GetCurrentProcessId());
  STARTUPINFOW startup{sizeof(startup)};
  auto child = std::make_unique<Child>();
  require(CreateProcessW(path, command, nullptr, nullptr, FALSE,
                         CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr,
                         &startup, &child->process) != FALSE,
          "spawn the admitted process");
  require(AssignProcessToJobObject(job, child->process.hProcess) != FALSE,
          "window process joins the harness job");
  ResumeThread(child->process.hThread);
  FILETIME created{}, exited{}, kernel{}, user{};
  require(GetProcessTimes(child->process.hProcess, &created, &exited, &kernel,
                          &user) != FALSE, "admitted process creation time");
  child->created = filetime_value(created);
  require(DuplicateHandle(GetCurrentProcess(), child->process.hProcess,
              GetCurrentProcess(), &child->query,
              PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, 0) != FALSE,
          "original query/wait handle");
  Search search{child->process.dwProcessId, nullptr};
  const auto until = GetTickCount64() + 10000;
  for (;;) {
    EnumWindows(find_target, reinterpret_cast<LPARAM>(&search));
    if (search.found) break;
    require(WaitForSingleObject(child->process.hProcess, 0) == WAIT_TIMEOUT,
            "window process stays alive");
    require(GetTickCount64() < until, "admitted window appears");
    Sleep(10);
  }
  child->window = search.found;
  return child;
}

void end(std::unique_ptr<Child> &child) {
  TerminateProcess(child->process.hProcess, 0);
  WaitForSingleObject(child->process.hProcess, 10000);
  CloseHandle(child->query);
  CloseHandle(child->process.hThread);
  CloseHandle(child->process.hProcess);
  child.reset();
}

MiniAVWindowsAppAdmissionV1 admission(const Child &child, uint64_t until) {
  MiniAVWindowsAppAdmissionV1 value{};
  value.struct_size = sizeof(value);
  value.abi_version = 1;
  value.host_epoch = 11;
  value.grant_generation = 12;
  value.runtime_source_generation = 13;
  value.valid_until_tick_ms = until;
  value.admitted_process_handle = reinterpret_cast<uint64_t>(child.query);
  value.process_creation_filetime = child.created;
  value.process_id = child.process.dwProcessId;
  // Synthetic host attestation: this harness is not an installed provider.
  value.executable_sha256[0] = 1;
  return value;
}

struct Listener {
  std::mutex mutex;
  std::vector<const MiniAVBuffer *> held;
  std::vector<int64_t> latency_us; // Capture to delivery, per frame.
  std::atomic<uint32_t> delivered{0}, malformed{0}, reordered{0};
  std::atomic<uint32_t> lost_calls{0};
  std::atomic<int> lost_reason{0};
  std::atomic<int64_t> last_timestamp{0};
  uint32_t width = 0, height = 0;
};

void on_frame(const MiniAVBuffer *buffer, void *data) {
  const auto arrived = qpc_us();
  auto &listener = *static_cast<Listener *>(data);
  const auto &video = buffer->data.video;
  const auto &plane = video.planes[0];
  if (buffer->type != MINIAV_BUFFER_TYPE_VIDEO ||
      buffer->content_type != MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE ||
      video.info.pixel_format != MINIAV_PIXEL_FORMAT_BGRA32 ||
      video.info.width != listener.width ||
      video.info.height != listener.height || video.num_planes != 1 ||
      !plane.data_ptr || plane.dmabuf_fd != -1 ||
      plane.width != listener.width || plane.height != listener.height ||
      plane.drm_format_modifier != MINIAV_D3D11_IMMUTABLE_READY_TAG ||
      !buffer->internal_handle)
    listener.malformed.fetch_add(1);
  if (buffer->timestamp_us <= listener.last_timestamp.exchange(buffer->timestamp_us))
    listener.reordered.fetch_add(1);
  std::lock_guard<std::mutex> lock(listener.mutex);
  listener.held.push_back(buffer);
  listener.latency_us.push_back(arrived - buffer->timestamp_us);
  listener.delivered.fetch_add(1);
}

void on_lost(int reason, void *data) {
  auto &listener = *static_cast<Listener *>(data);
  listener.lost_reason = reason;
  listener.lost_calls.fetch_add(1);
}

struct Reader {
  ComPtr<ID3D11Device1> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<ID3D11Texture2D> staging;
} reader;

void open_reader() {
  ComPtr<ID3D11Device> base;
  require(SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE,
              nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
              D3D11_SDK_VERSION, &base, nullptr, &reader.context)) &&
              SUCCEEDED(base.As(&reader.device)),
          "consumer D3D11 device on the default adapter");
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = desc.Height = desc.MipLevels = desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_STAGING;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  require(SUCCEEDED(reader.device->CreateTexture2D(&desc, nullptr,
                                                   &reader.staging)),
          "consumer readback texture");
}

// Centre pixel of a published snapshot, imported through its shared handle on
// the consumer's own device: 0xAARRGGBB.
uint32_t centre(const MiniAVBuffer *buffer) {
  const auto &plane = buffer->data.video.planes[0];
  ComPtr<ID3D11Texture2D> texture;
  require(SUCCEEDED(reader.device->OpenSharedResource1(
              static_cast<HANDLE>(plane.data_ptr), IID_PPV_ARGS(&texture))),
          "published handle imports on a consumer device");
  D3D11_TEXTURE2D_DESC desc{};
  texture->GetDesc(&desc);
  require(desc.Width == plane.width && desc.Height == plane.height &&
              desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM &&
              desc.MipLevels == 1 && desc.ArraySize == 1,
          "imported snapshot matches its buffer");
  const UINT x = desc.Width / 2, y = desc.Height / 2;
  D3D11_BOX box{x, y, 0, x + 1, y + 1, 1};
  reader.context->CopySubresourceRegion(reader.staging.Get(), 0, 0, 0, 0,
                                        texture.Get(), 0, &box);
  D3D11_MAPPED_SUBRESOURCE mapped{};
  require(SUCCEEDED(reader.context->Map(reader.staging.Get(), 0,
                                        D3D11_MAP_READ, 0, &mapped)),
          "map consumer readback");
  uint32_t value = 0;
  std::memcpy(&value, mapped.pData, sizeof(value));
  reader.context->Unmap(reader.staging.Get(), 0);
  return value;
}

// Colours as 0xRRGGBB; alpha is not part of the comparison.
uint32_t held_colour(WPARAM k) { return 0x303130u + (k & 1); }
bool changing_colour(uint32_t value) {
  value &= 0xffffffu;
  return value == 0x303030u || value == 0x313030u;
}

struct Source {
  MiniAVScreenContextHandle ctx = nullptr;
  Listener listener;
  MiniAVWindowsSelectionNonceV1 nonce{};
  MiniAVWindowsStrictWindowWitnessV1 witness{};
  MiniAVWindowsStrictResourceProfileV1 profile{};
};

MiniAVWindowsStrictRetirementV1 receipt(MiniAVScreenContextHandle ctx) {
  MiniAVWindowsStrictRetirementV1 value{};
  value.struct_size = sizeof(value);
  value.abi_version = 1;
  require(MiniAV_Screen_Windows_GetStrictRetirementV1(ctx, &value) == 0,
          "retirement query");
  return value;
}

size_t held(Source &source) {
  std::lock_guard<std::mutex> lock(source.listener.mutex);
  return source.listener.held.size();
}

// Releases every held buffer. Returns the centre pixel of the newest one when
// `read` is set, else 0.
uint32_t drain(Source &source, bool read = false) {
  std::vector<const MiniAVBuffer *> taken;
  {
    std::lock_guard<std::mutex> lock(source.listener.mutex);
    taken.swap(source.listener.held);
  }
  uint32_t newest = 0;
  if (read && !taken.empty()) newest = centre(taken.back());
  for (auto *buffer : taken)
    require(MiniAV_ReleaseBuffer(buffer->internal_handle) == 0,
            "release a delivered buffer");
  return newest;
}

uint64_t candidate_for(Source &source, const Child &child, uint32_t count) {
  uint64_t id = 0;
  for (uint32_t i = 0; i < count; ++i) {
    MiniAVWindowsScreenCandidateV1 candidate{sizeof(candidate), 1};
    require(MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(
                source.ctx, &source.nonce, i, &candidate) == 0,
            "copy a selection candidate");
    require(candidate.process_id == child.process.dwProcessId &&
                candidate.process_creation_filetime == child.created &&
                candidate.candidate_id,
            "candidate belongs to the admitted process");
    if (candidate.hwnd_value == reinterpret_cast<uint64_t>(child.window)) {
      require(!std::strcmp(candidate.title_utf8, "miniav strict qualification"),
              "candidate carries the window title");
      id = candidate.candidate_id;
    }
  }
  return id;
}

void create(Source &source) {
  require(MiniAV_Screen_CreateContext(&source.ctx) == 0 && source.ctx,
          "create a screen context");
  require(MiniAV_Screen_SetContextLostCallback(source.ctx, on_lost,
                                               &source.listener) == 0,
          "lost callback before Begin");
}

void begin(Source &source, const Child &child, uint64_t until,
           uint32_t *count_out) {
  create(source);
  const auto value = admission(child, until);
  source.nonce = {sizeof(source.nonce), 1};
  require(MiniAV_Screen_Windows_BeginStrictSelectionV2(source.ctx, &value,
              &source.nonce, count_out) == 0,
          "Begin on the admitted process");
}

MiniAVResultCode configure(Source &source, uint64_t id, uint32_t fps,
                           MiniAVOutputPreference output =
                               MINIAV_OUTPUT_PREFERENCE_GPU) {
  MiniAVVideoInfo format{0, 0, MINIAV_PIXEL_FORMAT_BGRA32, fps, 1, output};
  MiniAVWindowsStrictCaptureOptionsV1 options{sizeof(options), 1, 1, 0};
  source.witness = {sizeof(source.witness), 1};
  return MiniAV_Screen_Windows_ConfigureStrictWindowV1(
      source.ctx, &source.nonce, id, &format, &options, &source.witness);
}

void start(Source &source) {
  source.profile = {sizeof(source.profile), 1};
  require(MiniAV_Screen_Windows_GetStrictResourceProfileV1(
              source.ctx, &source.profile) == 0,
          "resource profile after Configure");
  source.listener.width = source.profile.width;
  source.listener.height = source.profile.height;
  require(MiniAV_Screen_StartCapture(source.ctx, on_frame, &source.listener) ==
              0, "Start the configured window");
}

// Begin, select the child's only window, configure and start.
void open(Source &source, const Child &child, uint64_t until, uint32_t fps) {
  uint32_t count = 0;
  begin(source, child, until, &count);
  const auto id = candidate_for(source, child, count);
  require(count == 1 && id, "exactly the admitted window is offered");
  require(configure(source, id, fps) == 0, "Configure the admitted window");
  start(source);
}

bool wait_frames(Source &source, uint32_t frames, DWORD milliseconds,
                 bool release) {
  const auto until = GetTickCount64() + milliseconds;
  while (source.listener.delivered < frames) {
    if (GetTickCount64() >= until) return false;
    if (release) drain(source);
    Sleep(2);
  }
  return true;
}

// Keeps releasing until the source stops by itself; returns its receipt.
MiniAVWindowsStrictRetirementV1 wait_terminal(Source &source, DWORD milliseconds,
                                              const char *what) {
  const auto until = GetTickCount64() + milliseconds;
  for (;;) {
    drain(source);
    const auto value = receipt(source.ctx);
    if (value.state != 0) return value;
    require(GetTickCount64() < until, what);
    Sleep(2);
  }
}

void retire(Source &source, int reason) {
  const auto until = GetTickCount64() + 5000;
  for (;;) {
    drain(source);
    const auto value = receipt(source.ctx);
    require(value.state != 3, "cleanup failed instead of retiring");
    if (value.state == 2) {
      require(value.flags == 31 && value.callbacks_in_flight == 0 &&
                  value.buffers_outstanding == 0 &&
                  value.frames_posted == value.frames_released &&
                  value.cleanup_error == 0 && value.terminal_reason == reason &&
                  value.capture_id == source.witness.capture_id,
              "actual running retirement witness");
      require(value.frames_posted == source.listener.delivered,
              "every posted frame reached the listener");
      break;
    }
    require(GetTickCount64() < until, "running retirement remained pending");
    Sleep(2);
  }
  require(MiniAV_Screen_DestroyContext(source.ctx) == 0,
          "checked destruction after retirement");
  source.ctx = nullptr;
  if (reason)
    require(source.listener.lost_calls == 1 &&
                source.listener.lost_reason == reason,
            "one lost callback carries the terminal reason");
  else
    require(source.listener.lost_calls == 0, "requested stop is not a loss");
  require(source.listener.malformed == 0, "every delivered buffer was well formed");
  require(source.listener.reordered == 0, "timestamps strictly increase");
}

void list_adapters() {
  ComPtr<IDXGIFactory1> factory;
  require(SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))), "DXGI factory");
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
    DXGI_ADAPTER_DESC1 desc{};
    adapter->GetDesc1(&desc);
    UINT outputs = 0;
    ComPtr<IDXGIOutput> output;
    while (adapter->EnumOutputs(outputs, &output) != DXGI_ERROR_NOT_FOUND) ++outputs;
    std::printf("adapter %u: %ls (outputs %u)\n", i, desc.Description, outputs);
  }
}

// ---------------------------------------------------------------------------
// Cases.
void placement() {
  // Off-screen first: nothing then appears on the desktop at all.
  origin = {GetSystemMetrics(SM_XVIRTUALSCREEN) +
                GetSystemMetrics(SM_CXVIRTUALSCREEN) + 200,
            GetSystemMetrics(SM_YVIRTUALSCREEN) + 200};
  for (int attempt = 0; attempt < 2; ++attempt) {
    auto child = spawn();
    auto source = std::make_unique<Source>();
    open(*source, *child, GetTickCount64() + 30000, 30);
    const bool flowing = wait_frames(*source, 3, 3000, true);
    require(MiniAV_Screen_Windows_RequestStrictStopV1(source->ctx, 0) == 0,
            "stop the placement probe");
    retire(*source, 0);
    end(child);
    if (flowing) {
      std::printf("PASS frames flow with the window at %ld,%ld\n", origin.x,
                  origin.y);
      return;
    }
    RECT work{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    origin = {work.right - window_width - 16, work.bottom - window_height - 16};
  }
  std::puts("UNAVAILABLE no frames from a composed window");
  std::fflush(stdout);
  TerminateProcess(GetCurrentProcess(), 77);
}

void selection_rules() {
  auto child = spawn();
  {
    auto source = std::make_unique<Source>();
    create(*source);
    auto value = admission(*child, GetTickCount64() + 30000);
    value.process_id += 4;
    uint32_t count = 99;
    source->nonce = {sizeof(source->nonce), 1};
    require(MiniAV_Screen_Windows_BeginStrictSelectionV2(source->ctx, &value,
                &source->nonce, &count) == MINIAV_ERROR_PERMISSION_DENIED &&
                !count,
            "a handle of another process is refused");
    retire(*source, MINIAV_ERROR_PERMISSION_DENIED);
  }
  {
    auto source = std::make_unique<Source>();
    create(*source);
    auto value = admission(*child, GetTickCount64() + 30000);
    value.process_creation_filetime += 1;
    uint32_t count = 99;
    source->nonce = {sizeof(source->nonce), 1};
    require(MiniAV_Screen_Windows_BeginStrictSelectionV2(source->ctx, &value,
                &source->nonce, &count) == MINIAV_ERROR_PERMISSION_DENIED,
            "a reused PID with another creation time is refused");
    retire(*source, MINIAV_ERROR_PERMISSION_DENIED);
  }
  {
    auto source = std::make_unique<Source>();
    uint32_t count = 0;
    begin(*source, *child, GetTickCount64() + 30000, &count);
    const auto id = candidate_for(*source, *child, count);
    require(count == 1 && id, "exactly the admitted window is offered");
    require(configure(*source, id, 30, MINIAV_OUTPUT_PREFERENCE_CPU) ==
                MINIAV_ERROR_FORMAT_NOT_SUPPORTED,
            "a CPU output request is refused");
    retire(*source, MINIAV_ERROR_FORMAT_NOT_SUPPORTED);
  }
  end(child);
  std::puts("PASS foreign handle, stale creation time and CPU output refused");
}

void running_contract() {
  auto child = spawn();
  auto source = std::make_unique<Source>();
  const auto until = GetTickCount64() + 60000;
  uint32_t count = 0;
  begin(*source, *child, until, &count);
  const auto id = candidate_for(*source, *child, count);
  require(count == 1 && id, "exactly the admitted window is offered");
  {
    MiniAVWindowsScreenCandidateV1 candidate{sizeof(candidate), 1};
    auto wrong = source->nonce;
    wrong.nonce[0] ^= 1;
    require(MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(source->ctx,
                &wrong, 0, &candidate) == MINIAV_ERROR_PERMISSION_DENIED,
            "copy with a foreign nonce is refused");
    candidate = {sizeof(candidate), 1};
    require(MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(source->ctx,
                &source->nonce, count, &candidate) == MINIAV_ERROR_INVALID_ARG,
            "copy past the selection is refused");
    auto kept = source->nonce;
    source->nonce = wrong;
    require(configure(*source, id, 30) == MINIAV_ERROR_PERMISSION_DENIED,
            "Configure with a foreign nonce is refused");
    source->nonce = kept;
  }
  require(configure(*source, id, 30) == 0, "Configure the admitted window");
  const auto &witness = source->witness;
  require(witness.struct_size == sizeof(witness) && witness.abi_version == 1 &&
              witness.capture_id && witness.window_incarnation &&
              witness.hwnd_value == reinterpret_cast<uint64_t>(child->window) &&
              witness.process_id == child->process.dwProcessId &&
              witness.process_creation_filetime == child->created &&
              witness.host_epoch == 11 && witness.grant_generation == 12 &&
              witness.runtime_source_generation == 13 &&
              witness.valid_until_tick_ms == until &&
              witness.executable_sha256[0] == 1 &&
              !std::memcmp(witness.selection_nonce, source->nonce.nonce, 16),
          "window witness repeats the admission");
  {
    MiniAVWindowsStrictWindowWitnessV1 again{sizeof(again), 1};
    MiniAVVideoInfo format{0, 0, MINIAV_PIXEL_FORMAT_BGRA32, 30, 1,
                           MINIAV_OUTPUT_PREFERENCE_GPU};
    MiniAVWindowsStrictCaptureOptionsV1 options{sizeof(options), 1, 1, 0};
    require(MiniAV_Screen_Windows_ConfigureStrictWindowV1(source->ctx,
                &source->nonce, id, &format, &options, &again) ==
                MINIAV_ERROR_INVALID_OPERATION,
            "the selection nonce is single use");
    MiniAVWindowsScreenCandidateV1 candidate{sizeof(candidate), 1};
    require(MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(source->ctx,
                &source->nonce, 0, &candidate) == MINIAV_ERROR_INVALID_OPERATION,
            "no candidate copy after Configure");
    require(MiniAV_Screen_ConfigureWindow(source->ctx, "HWND:0", &format,
                                          false) == MINIAV_ERROR_INVALID_OPERATION,
            "generic configure cannot replace the strict owner");
    require(MiniAV_Screen_SetCaptureCursor(source->ctx, true) ==
                MINIAV_ERROR_INVALID_OPERATION,
            "cursor is fixed after Configure");
  }
  start(*source);
  const auto &profile = source->profile;
  RECT bounds{};
  GetWindowRect(child->window, &bounds);
  std::printf("window %ldx%ld, configured %ux%u\n", bounds.right - bounds.left,
              bounds.bottom - bounds.top, profile.width, profile.height);
  require(profile.capture_id == witness.capture_id &&
              profile.window_incarnation == witness.window_incarnation &&
              profile.width == uint32_t(bounds.right - bounds.left) &&
              profile.height == uint32_t(bounds.bottom - bounds.top) &&
              profile.pixel_format == MINIAV_PIXEL_FORMAT_BGRA32 &&
              profile.pool_slots == 2 && profile.max_outstanding_buffers == 3 &&
              profile.flags == 1 &&
              profile.frame_bytes == uint64_t(profile.width) * profile.height * 4,
          "resource profile describes the configured window");
  require(MiniAV_Screen_StartCapture(source->ctx, on_frame, &source->listener) ==
              MINIAV_ERROR_INVALID_OPERATION, "Start is single use");
  require(MiniAV_Screen_SetContextLostCallback(source->ctx, on_lost,
              &source->listener) == MINIAV_ERROR_INVALID_OPERATION,
          "lost callback is fixed after Start");
  {
    MiniAVWindowsStrictResourceProfileV1 late{sizeof(late), 1};
    require(MiniAV_Screen_Windows_GetStrictResourceProfileV1(source->ctx, &late) ==
                MINIAV_ERROR_NOT_CONFIGURED,
            "no resource profile after Start");
  }

  // Three buffers held by the listener stop publication without a stall.
  require(wait_frames(*source, 3, 3000, false), "three frames while holding");
  Sleep(500);
  require(source->listener.delivered == 3 && held(*source) == 3,
          "no fourth buffer while three are held");
  {
    const auto value = receipt(source->ctx);
    require(value.state == 0 && value.buffers_outstanding == 3 &&
                value.frames_posted == 3 && value.frames_released == 0 &&
                value.capture_id == witness.capture_id,
            "receipt counts the held buffers");
  }
  {
    std::vector<const MiniAVBuffer *> taken;
    {
      std::lock_guard<std::mutex> lock(source->listener.mutex);
      taken = source->listener.held;
    }
    for (auto *buffer : taken) {
      const auto pixel = centre(buffer);
      if (!changing_colour(pixel)) {
        std::printf("centre pixel 0x%08x\n", pixel);
        fail("published pixels are the window's fill");
      }
    }
  }
  drain(*source);
  require(receipt(source->ctx).frames_released == 3, "released buffers count");

  // Free running: the rate stays at or under the configured 30 per second.
  {
    std::lock_guard<std::mutex> lock(source->listener.mutex);
    source->listener.latency_us.clear();
  }
  const uint32_t before = source->listener.delivered;
  const auto began = GetTickCount64();
  while (GetTickCount64() - began < 2000) {
    drain(*source);
    Sleep(2);
  }
  const uint32_t frames = source->listener.delivered - before;
  std::printf("free running: %u frames in 2 s at 30/s requested\n", frames);
  require(frames >= 10 && frames <= 63, "free-running rate follows the request");
  {
    std::vector<int64_t> latency;
    {
      std::lock_guard<std::mutex> lock(source->listener.mutex);
      latency.swap(source->listener.latency_us);
    }
    std::sort(latency.begin(), latency.end());
    std::printf("capture to delivery: median %.2f ms, 90th %.2f ms, max %.2f ms\n",
                latency[latency.size() / 2] / 1000.0,
                latency[latency.size() * 9 / 10] / 1000.0,
                latency.back() / 1000.0);
  }

  // The last change of a window that then stops changing is delivered.
  for (WPARAM k = 1; k <= 4; ++k) {
    require(PostMessageW(child->window, hold_message, k, 0) != FALSE,
            "hold the window fill");
    uint32_t newest = 0;
    const auto settle = GetTickCount64();
    while (GetTickCount64() - settle < 600) {
      const auto pixel = drain(*source, true);
      if (pixel) newest = pixel;
      Sleep(5);
    }
    if ((newest & 0xffffffu) != held_colour(k)) {
      std::printf("hold %llu: newest delivered centre 0x%08x, window shows "
                  "0x%08x\n", static_cast<unsigned long long>(k), newest,
                  held_colour(k));
      fail("a window's last change is delivered");
    }
    require(PostMessageW(child->window, resume_message, 0, 0) != FALSE,
            "resume the window fill");
    const auto resumed = GetTickCount64();
    while (GetTickCount64() - resumed < 200) {
      drain(*source);
      Sleep(2);
    }
  }

  // Stop while the listener holds buffers: pending until their release.
  require(wait_frames(*source, source->listener.delivered + 2, 3000, false),
          "frames to hold across Stop");
  require(MiniAV_Screen_Windows_RequestStrictStopV1(source->ctx, 0) == 0,
          "RequestStop while buffers are held");
  const uint32_t at_stop = source->listener.delivered;
  require(MiniAV_Screen_DestroyContext(source->ctx) == MINIAV_ERROR_TIMEOUT,
          "Destroy waits for held buffers");
  Sleep(300);
  {
    const auto value = receipt(source->ctx);
    require(value.state == 1 && (value.flags & 1) &&
                value.buffers_outstanding == held(*source) &&
                value.buffers_outstanding >= 2,
            "stopped source stays pending while buffers are held");
    require(source->listener.delivered <= at_stop + 1,
            "no publication after RequestStop beyond one in flight");
  }
  retire(*source, 0);
  end(child);
  std::puts("PASS selection, configuration, buffer bound, freshness, held Stop");
}

void terminal_case(const char *name, int expected, uint64_t lifetime,
                   void (*act)(Child &)) {
  auto child = spawn();
  auto source = std::make_unique<Source>();
  open(*source, *child, GetTickCount64() + lifetime, 30);
  require(wait_frames(*source, 2, 3000, true), "frames before the event");
  if (act) act(*child);
  // The worker checks the window and the process on every pass, so an event
  // stops the source within a second; only the deadline needs longer.
  const auto acted = GetTickCount64();
  const auto value = wait_terminal(*source, act ? 1000 : 5000, name);
  const auto latency = GetTickCount64() - acted;
  if (value.terminal_reason != expected) {
    std::printf("%s: terminal reason %d, expected %d\n", name,
                value.terminal_reason, expected);
    fail(name);
  }
  retire(*source, expected);
  end(child);
  std::printf("PASS %s (%llu ms)\n", name,
              static_cast<unsigned long long>(latency));
}

void resize(Child &child) {
  require(SetWindowPos(child.window, nullptr, 0, 0, window_width - 40,
                       window_height - 30,
                       SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE) != FALSE,
          "resize the captured window");
}
void close_window(Child &child) {
  require(PostMessageW(child.window, WM_CLOSE, 0, 0) != FALSE,
          "close the captured window");
  const auto until = GetTickCount64() + 2000;
  while (IsWindow(child.window)) {
    require(GetTickCount64() < until, "the captured window is destroyed");
    Sleep(2);
  }
}
void exit_process(Child &child) {
  require(TerminateProcess(child.process.hProcess, 0) != FALSE,
          "end the admitted process");
}

// Ordinary window capture, which hands frames back as they come.
struct Generic {
  std::atomic<uint32_t> frames{0}, lost_calls{0};
  std::atomic<int> lost_reason{0};
};

void on_generic_frame(const MiniAVBuffer *buffer, void *data) {
  static_cast<Generic *>(data)->frames.fetch_add(1);
  if (buffer->internal_handle) MiniAV_ReleaseBuffer(buffer->internal_handle);
}

void on_generic_lost(int reason, void *data) {
  auto &generic = *static_cast<Generic *>(data);
  generic.lost_reason = reason;
  generic.lost_calls.fetch_add(1);
}

// Windows raises no Closed for this window, so only the capture's own window
// check can end it.
void generic_close() {
  auto child = spawn();
  Generic generic;
  MiniAVScreenContextHandle ctx = nullptr;
  require(MiniAV_Screen_CreateContext(&ctx) == 0 && ctx,
          "create a generic screen context");
  require(MiniAV_Screen_SetContextLostCallback(ctx, on_generic_lost,
                                               &generic) == 0,
          "generic lost callback");
  char id[MINIAV_DEVICE_ID_MAX_LEN]{};
  std::snprintf(id, sizeof(id), "HWND:0x%p", static_cast<void *>(child->window));
  MiniAVVideoInfo format{window_width, window_height, MINIAV_PIXEL_FORMAT_BGRA32,
                         30, 1, MINIAV_OUTPUT_PREFERENCE_GPU};
  require(MiniAV_Screen_ConfigureWindow(ctx, id, &format, false) == 0,
          "generic configure of the window");
  require(MiniAV_Screen_StartCapture(ctx, on_generic_frame, &generic) == 0,
          "generic start");
  const auto until = GetTickCount64() + 3000;
  while (generic.frames < 2) {
    require(GetTickCount64() < until, "generic frames before the close");
    Sleep(2);
  }
  close_window(*child);
  const auto closed = GetTickCount64();
  while (!generic.lost_calls) {
    require(GetTickCount64() - closed < 2000,
            "generic capture notices the closed window");
    Sleep(1);
  }
  const auto latency = GetTickCount64() - closed;
  require(generic.lost_reason == MINIAV_ERROR_DEVICE_LOST,
          "the generic loss is a lost device");
  require(MiniAV_Screen_StopCapture(ctx) == 0, "generic stop after the loss");
  require(MiniAV_Screen_DestroyContext(ctx) == 0, "generic destroy");
  require(generic.lost_calls == 1, "one generic lost callback");
  end(child);
  std::printf("PASS closing the window ends a generic capture (%llu ms)\n",
              static_cast<unsigned long long>(latency));
}
} // namespace

int main(int argc, char **argv) {
  // Both sides work in physical pixels, as the capture item does.
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  if (argc == 5 && !std::strcmp(argv[1], "--window"))
    return child_main(std::atoi(argv[2]), std::atoi(argv[3]),
                      static_cast<DWORD>(std::strtoul(argv[4], nullptr, 10)));
  if (argc == 2 && !std::strcmp(argv[1], "--adapters")) {
    list_adapters();
    return 0;
  }
  std::setvbuf(stdout, nullptr, _IONBF, 0); // Keep order with library logs.
  uint32_t bits = 0;
  uint64_t now = 0;
  const auto support = MiniAV_Screen_Windows_StrictCapabilitiesV1(&bits, &now);
  if (support != 0 || bits != 15 || !now) {
    std::printf("UNAVAILABLE strict WGC code=%d bits=%u\n", support, bits);
    return 77;
  }
  job = CreateJobObjectW(nullptr, nullptr);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  require(job && SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                         &limits, sizeof(limits)) != FALSE,
          "window processes end with the harness");
  open_reader();
  list_adapters();

  placement();
  selection_rules();
  running_contract();
  terminal_case("resize stops the source", MINIAV_ERROR_FORMAT_NOT_SUPPORTED,
                30000, resize);
  terminal_case("closing the window stops the source", MINIAV_ERROR_DEVICE_LOST,
                30000, close_window);
  terminal_case("process exit stops the source", MINIAV_ERROR_DEVICE_LOST,
                30000, exit_process);
  terminal_case("the admission deadline stops the source",
                MINIAV_ERROR_PERMISSION_DENIED, 1500, nullptr);
  generic_close();
  std::puts("PASS strict running qualification");
  std::fflush(stdout);
  CloseHandle(job);
  return 0;
}
