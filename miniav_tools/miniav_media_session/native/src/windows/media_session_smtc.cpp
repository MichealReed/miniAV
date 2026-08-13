/*
 * Windows backend: System Media Transport Controls.
 *
 * THREADING MODEL
 * ---------------
 * SMTC is reached through ISystemMediaTransportControlsInterop::GetForWindow,
 * so a window is mandatory, and a window needs a thread that pumps messages.
 * This backend owns one: it creates a hidden top-level window, acquires SMTC
 * for it, and runs a message loop until destroy.
 *
 * Every public setter is called from the Dart isolate, NOT from that thread.
 * Rather than call apartment-bound WinRT objects across threads and hope they
 * are agile, setters write into a mutex-guarded snapshot, mark it dirty and
 * post WM_MS_APPLY; the pump thread is the only thing that ever touches the
 * SMTC objects. That also coalesces for free — a position push every 250 ms
 * that arrives while the pump is busy collapses into one apply rather than
 * queueing.
 *
 * TRAP: a message-only window (HWND_MESSAGE) will NOT work. It is not
 * associated with a display surface and SMTC will not publish for it. The
 * window created here is a real top-level window that is simply never shown.
 *
 * TRAP: a session with default state is INVISIBLE. IsEnabled must be true, the
 * individual buttons must be enabled, PlaybackStatus must be something other
 * than Closed, and DisplayUpdater::Update() must be called — miss any of them
 * and the flyout silently never appears, which reads as "the API did not work".
 */
#include <windows.h>

#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cwchar>
#include <mutex>
#include <string>
#include <thread>

/* Has its own extern "C" guards; wrapping it in another would drag <stdint.h>
 * and <stddef.h> in with C linkage. */
#include "media_session_internal.h"

namespace {

namespace wf = winrt::Windows::Foundation;
namespace wm = winrt::Windows::Media;
namespace wss = winrt::Windows::Storage::Streams;

constexpr UINT WM_MS_APPLY = WM_APP + 1;
constexpr UINT WM_MS_QUIT = WM_APP + 2;
constexpr wchar_t kWindowClass[] = L"MiniAVMediaSessionHost";

HWND g_host_window_override = nullptr;

std::wstring Widen(const char *utf8) {
  if (utf8 == nullptr || *utf8 == '\0') return std::wstring();
  const int needed =
      MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  if (needed <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(needed - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out.data(), needed);
  return out;
}

wf::TimeSpan MicrosToTimeSpan(int64_t micros) {
  if (micros < 0) micros = 0;
  return std::chrono::duration_cast<wf::TimeSpan>(
      std::chrono::microseconds(micros));
}

/* Everything the pump thread needs, written by callers under `mutex`. */
struct Snapshot {
  bool metadata_dirty = false;
  bool state_dirty = false;
  bool position_dirty = false;
  bool actions_dirty = false;

  std::wstring title;
  std::wstring artist;
  std::wstring album;
  std::wstring artwork_uri;  /* empty when none */
  int32_t track_number = 0;

  MiniAVMediaSessionState state = MINIAV_MS_STATE_NONE;

  int64_t position_us = 0;
  int64_t duration_us = -1;
  double speed = 1.0;

  uint32_t actions = 0;
};

struct SmtcBackend {
  std::thread thread;
  std::mutex mutex;
  std::condition_variable ready_cv;
  bool ready = false;
  bool ok = false;
  std::string error;

  HWND window = nullptr;
  bool owns_window = false;
  DWORD thread_id = 0;

  /* Temp file materialised from MediaArtwork.bytes, deleted on destroy. SMTC
   * takes a stream reference, not a buffer, so byte art has to land on disk
   * somewhere — and mp3 cover art arrives as bytes (an ID3 APIC frame), which
   * makes this the common path rather than an edge case. */
  std::wstring artwork_temp_path;

  Snapshot pending;

  wm::SystemMediaTransportControls smtc{nullptr};
  winrt::event_token button_token{};
  winrt::event_token position_token{};

  MiniAVMediaSession *session = nullptr;
};

LRESULT CALLBACK HostWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                             LPARAM lparam) {
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

struct FindWindowContext {
  DWORD pid;
  HWND found;
};

BOOL CALLBACK FindOwnWindowProc(HWND hwnd, LPARAM lparam) {
  auto *ctx = reinterpret_cast<FindWindowContext *>(lparam);
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid != ctx->pid) return TRUE;
  if (!IsWindowVisible(hwnd)) return TRUE;
  /* Owned windows are dialogs and tooltips, not the app. */
  if (GetWindow(hwnd, GW_OWNER) != nullptr) return TRUE;

  wchar_t cls[64] = {};
  GetClassNameW(hwnd, cls, 64);
  if (wcscmp(cls, kWindowClass) == 0) return TRUE;  /* our own helper */

  ctx->found = hwnd;
  return FALSE;
}

/*
 * The host app's own visible top-level window, if it has one.
 *
 * PREFERRED over a hidden helper window, because the shell draws its card from
 * the app identity behind the HWND — the name and icon. A hidden, never-shown
 * window in a console process gives the shell nothing to render, so the session
 * registers (media keys route to it) while no card ever appears. Adopting the
 * real window is also what Microsoft's desktop SMTC guidance assumes.
 */
HWND FindOwnMainWindow() {
  FindWindowContext ctx{GetCurrentProcessId(), nullptr};
  EnumWindows(FindOwnWindowProc, reinterpret_cast<LPARAM>(&ctx));
  return ctx.found;
}

HWND CreateHiddenHostWindow() {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = HostWndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kWindowClass;
  /* Re-registration across sessions is expected; ERROR_CLASS_ALREADY_EXISTS is
   * not a failure. */
  RegisterClassExW(&wc);

  /* WS_OVERLAPPED, never shown, 1x1 rather than 0x0 — a degenerate zero-size
   * window is a poor bet with shell integrations. Deliberately NOT
   * HWND_MESSAGE: see the file header. */
  return CreateWindowExW(0, kWindowClass, L"miniav media session",
                         WS_OVERLAPPED, 0, 0, 1, 1, nullptr, nullptr, instance,
                         nullptr);
}

/* Written by the pump thread during create; read by MiniAV_MediaSession_Describe.
 * Single-session-per-process makes a global safe here. */
std::mutex g_describe_mutex;
std::string g_describe;

void SetDescribe(std::string text) {
  std::lock_guard<std::mutex> lock(g_describe_mutex);
  g_describe = std::move(text);
}

std::wstring TempArtworkPath(const char *mime) {
  wchar_t dir[MAX_PATH] = {};
  const DWORD n = GetTempPathW(MAX_PATH, dir);
  if (n == 0 || n > MAX_PATH) return std::wstring();

  const std::string m = mime == nullptr ? std::string() : std::string(mime);
  const wchar_t *ext = L".img";
  if (m == "image/png") ext = L".png";
  else if (m == "image/jpeg" || m == "image/jpg") ext = L".jpg";
  else if (m == "image/bmp") ext = L".bmp";

  /* A fresh name per track, not one reused path: SMTC keys the thumbnail off
   * the URI, so writing new bytes to the same path leaves the FIRST cover on
   * screen for the rest of the session. The caller deletes the previous file. */
  static unsigned long generation = 0;
  wchar_t name[80] = {};
  swprintf(name, 80, L"miniav_ms_%lu_%lu%ls", GetCurrentProcessId(),
           ++generation, ext);
  return std::wstring(dir) + name;
}

/* file:///C:/path/with/forward/slashes */
std::wstring PathToFileUri(const std::wstring &path) {
  std::wstring uri = L"file:///";
  for (wchar_t c : path) uri.push_back(c == L'\\' ? L'/' : c);
  return uri;
}

bool WriteFileBytes(const std::wstring &path, const uint8_t *bytes,
                    size_t len) {
  const HANDLE file =
      CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                  FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  bool ok = true;
  size_t written_total = 0;
  while (written_total < len) {
    const DWORD chunk =
        static_cast<DWORD>((len - written_total) > 0x10000000u
                               ? 0x10000000u
                               : (len - written_total));
    DWORD written = 0;
    if (!WriteFile(file, bytes + written_total, chunk, &written, nullptr)) {
      ok = false;
      break;
    }
    written_total += written;
  }
  CloseHandle(file);
  return ok;
}

void ApplyActions(SmtcBackend *backend, uint32_t actions) {
  auto &smtc = backend->smtc;
  const bool has_play = (actions & MINIAV_MS_ACTION_PLAY) != 0;
  const bool has_pause = (actions & MINIAV_MS_ACTION_PAUSE) != 0;
  /* SMTC has discrete Play and Pause buttons and no combined one. A hardware
   * play/pause key arrives as whichever the current PlaybackStatus implies, so
   * PLAY_PAUSE is served by enabling both — but only when the app did not also
   * declare the discrete actions, otherwise one press would emit two commands.
   * Same rule as the web backend. */
  const bool synth_toggle =
      (actions & MINIAV_MS_ACTION_PLAY_PAUSE) != 0 && !has_play && !has_pause;

  smtc.IsPlayEnabled(has_play || synth_toggle);
  smtc.IsPauseEnabled(has_pause || synth_toggle);
  smtc.IsStopEnabled((actions & MINIAV_MS_ACTION_STOP) != 0);
  smtc.IsNextEnabled((actions & MINIAV_MS_ACTION_NEXT) != 0);
  smtc.IsPreviousEnabled((actions & MINIAV_MS_ACTION_PREVIOUS) != 0);
  smtc.IsFastForwardEnabled((actions & MINIAV_MS_ACTION_SEEK_FORWARD) != 0);
  smtc.IsRewindEnabled((actions & MINIAV_MS_ACTION_SEEK_BACKWARD) != 0);
}

void ApplyMetadata(SmtcBackend *backend, const Snapshot &snap) {
  auto updater = backend->smtc.DisplayUpdater();
  updater.Type(wm::MediaPlaybackType::Music);
  auto music = updater.MusicProperties();
  music.Title(snap.title);
  music.Artist(snap.artist);
  music.AlbumTitle(snap.album);
  if (snap.track_number > 0) {
    music.TrackNumber(static_cast<uint32_t>(snap.track_number));
  }

  if (!snap.artwork_uri.empty()) {
    try {
      updater.Thumbnail(
          wss::RandomAccessStreamReference::CreateFromUri(wf::Uri(snap.artwork_uri)));
    } catch (winrt::hresult_error const &) {
      /* A bad art URI must not cost the whole card its title. */
      updater.Thumbnail(nullptr);
    }
  } else {
    updater.Thumbnail(nullptr);
  }

  /* Without this the shell keeps showing the PREVIOUS track's fields. */
  updater.Update();
}

void ApplyState(SmtcBackend *backend, MiniAVMediaSessionState state) {
  using wm::MediaPlaybackStatus;
  MediaPlaybackStatus status = MediaPlaybackStatus::Closed;
  switch (state) {
    case MINIAV_MS_STATE_PLAYING:
      status = MediaPlaybackStatus::Playing;
      break;
    case MINIAV_MS_STATE_PAUSED:
      status = MediaPlaybackStatus::Paused;
      break;
    case MINIAV_MS_STATE_STOPPED:
      status = MediaPlaybackStatus::Stopped;
      break;
    case MINIAV_MS_STATE_NONE:
    default:
      status = MediaPlaybackStatus::Closed;
      break;
  }
  backend->smtc.PlaybackStatus(status);
}

void ApplyPosition(SmtcBackend *backend, const Snapshot &snap) {
  /* A timeline with no duration draws no scrub bar, which is correct for a
   * live source — pushing a zero end time instead would render a bar pinned at
   * 100%. */
  if (snap.duration_us <= 0) return;

  wm::SystemMediaTransportControlsTimelineProperties timeline;
  timeline.StartTime(wf::TimeSpan::zero());
  timeline.MinSeekTime(wf::TimeSpan::zero());
  timeline.Position(MicrosToTimeSpan(snap.position_us));
  timeline.MaxSeekTime(MicrosToTimeSpan(snap.duration_us));
  timeline.EndTime(MicrosToTimeSpan(snap.duration_us));
  backend->smtc.UpdateTimelineProperties(timeline);
  backend->smtc.PlaybackRate(snap.speed);
}

void ApplyPending(SmtcBackend *backend) {
  Snapshot snap;
  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    snap = backend->pending;
    backend->pending.metadata_dirty = false;
    backend->pending.state_dirty = false;
    backend->pending.position_dirty = false;
    backend->pending.actions_dirty = false;
  }
  if (!backend->smtc) return;

  try {
    if (snap.actions_dirty) ApplyActions(backend, snap.actions);
    if (snap.metadata_dirty) ApplyMetadata(backend, snap);
    if (snap.state_dirty) ApplyState(backend, snap.state);
    if (snap.position_dirty) ApplyPosition(backend, snap);
  } catch (winrt::hresult_error const &) {
    /* One rejected update must not tear the session down; the card simply goes
     * stale until the next push. */
  }
}

void OnButtonPressed(SmtcBackend *backend,
                     wm::SystemMediaTransportControlsButtonPressedEventArgs const
                         &args) {
  uint32_t action = 0;
  switch (args.Button()) {
    case wm::SystemMediaTransportControlsButton::Play:
      action = MINIAV_MS_ACTION_PLAY;
      break;
    case wm::SystemMediaTransportControlsButton::Pause:
      action = MINIAV_MS_ACTION_PAUSE;
      break;
    case wm::SystemMediaTransportControlsButton::Stop:
      action = MINIAV_MS_ACTION_STOP;
      break;
    case wm::SystemMediaTransportControlsButton::Next:
      action = MINIAV_MS_ACTION_NEXT;
      break;
    case wm::SystemMediaTransportControlsButton::Previous:
      action = MINIAV_MS_ACTION_PREVIOUS;
      break;
    case wm::SystemMediaTransportControlsButton::FastForward:
      action = MINIAV_MS_ACTION_SEEK_FORWARD;
      break;
    case wm::SystemMediaTransportControlsButton::Rewind:
      action = MINIAV_MS_ACTION_SEEK_BACKWARD;
      break;
    default:
      return;
  }

  /* Synthesised toggle: the app asked only for PLAY_PAUSE, so report that
   * rather than the discrete button the shell happened to render. */
  uint32_t declared = 0;
  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    declared = backend->pending.actions;
  }
  const bool synth_toggle = (declared & MINIAV_MS_ACTION_PLAY_PAUSE) != 0 &&
                            (declared & MINIAV_MS_ACTION_PLAY) == 0 &&
                            (declared & MINIAV_MS_ACTION_PAUSE) == 0;
  if (synth_toggle &&
      (action == MINIAV_MS_ACTION_PLAY || action == MINIAV_MS_ACTION_PAUSE)) {
    action = MINIAV_MS_ACTION_PLAY_PAUSE;
  }

  ms_emit_command(backend->session, action, -1, -1);
}

void PumpThread(SmtcBackend *backend, std::wstring app_name) {
  /* Multi-threaded apartment: this thread owns the WinRT objects, and nothing
   * else touches them, so an STA buys nothing here. */
  winrt::init_apartment(winrt::apartment_type::multi_threaded);

  bool ok = false;
  std::string error;

  /* Window preference, best identity first. The shell renders its card from the
   * app behind the HWND, so a real window is worth far more than a synthetic
   * one — see FindOwnMainWindow. */
  HWND window = g_host_window_override;
  bool owns_window = false;
  const char *how = "adopted the HWND supplied by the app";
  if (window == nullptr) {
    window = FindOwnMainWindow();
    how = "adopted this process's visible top-level window";
  }
  if (window == nullptr) {
    window = CreateHiddenHostWindow();
    owns_window = true;
    how =
        "created a hidden host window - this process has no visible top-level "
        "window, so the shell may have no app identity to draw a card from "
        "even though the session is registered and media keys route to it";
  }

  if (window == nullptr) {
    error = "failed to create the SMTC host window";
  } else {
    try {
      auto interop = winrt::get_activation_factory<
          wm::SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
      wm::SystemMediaTransportControls smtc{nullptr};
      winrt::check_hresult(interop->GetForWindow(
          window, winrt::guid_of<wm::SystemMediaTransportControls>(),
          winrt::put_abi(smtc)));

      smtc.IsEnabled(true);
      backend->button_token = smtc.ButtonPressed(
          [backend](auto &&, auto &&args) { OnButtonPressed(backend, args); });
      backend->position_token = smtc.PlaybackPositionChangeRequested(
          [backend](auto &&, auto &&args) {
            const int64_t micros =
                std::chrono::duration_cast<std::chrono::microseconds>(
                    args.RequestedPlaybackPosition())
                    .count();
            ms_emit_command(backend->session, MINIAV_MS_ACTION_SEEK_TO, micros,
                            -1);
          });

      backend->smtc = smtc;
      backend->window = window;
      backend->owns_window = owns_window;
      backend->thread_id = GetCurrentThreadId();
      ok = true;

      char detail[512] = {};
      _snprintf_s(detail, sizeof(detail), _TRUNCATE, "smtc: %s (hwnd 0x%p)",
                  how, static_cast<void *>(window));
      SetDescribe(detail);
    } catch (winrt::hresult_error const &e) {
      error = "SMTC unavailable: " + winrt::to_string(e.message());
    }
  }

  if (!ok && owns_window && window != nullptr) {
    DestroyWindow(window);
    window = nullptr;
  }

  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    backend->ok = ok;
    backend->error = error;
    backend->ready = true;
  }
  backend->ready_cv.notify_one();
  if (!ok) {
    winrt::uninit_apartment();
    return;
  }

  (void)app_name;  /* SMTC takes its source label from the process itself. */

  MSG msg;
  bool running = true;
  while (running && GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (msg.hwnd == nullptr || msg.hwnd == backend->window) {
      if (msg.message == WM_MS_APPLY) {
        ApplyPending(backend);
        continue;
      }
      if (msg.message == WM_MS_QUIT) {
        running = false;
        continue;
      }
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  /* Revoke before releasing: after this returns, ms_platform_destroy is free to
   * let the Dart NativeCallable be closed, so no callback may still be in
   * flight. Revoking on this thread — the only one that raises them — is what
   * makes that guarantee true. */
  if (backend->smtc) {
    backend->smtc.ButtonPressed(backend->button_token);
    backend->smtc.PlaybackPositionChangeRequested(backend->position_token);
    backend->smtc.IsEnabled(false);
    backend->smtc = nullptr;
  }
  if (backend->owns_window && backend->window != nullptr) {
    DestroyWindow(backend->window);
  }
  backend->window = nullptr;
  winrt::uninit_apartment();
}

void PostApply(SmtcBackend *backend) {
  if (backend->thread_id == 0) return;
  PostThreadMessageW(backend->thread_id, WM_MS_APPLY, 0, 0);
}

}  // namespace

extern "C" {

void ms_platform_set_host_window(void *hwnd) {
  g_host_window_override = static_cast<HWND>(hwnd);
}

int ms_platform_is_supported(void) {
  /* Probed on a THROWAWAY THREAD, never on the caller's.
   *
   * This is called through dart:ffi, and the Dart VM lends its threads out —
   * initialising an apartment on one would permanently change the apartment of
   * a thread the VM will hand to unrelated code later, and would fail outright
   * if that thread is already in a different apartment. miniav_c already had
   * to unpick exactly this bug class (CoInitializeEx at FFI entry points). The
   * probe thread owns its own apartment for its whole lifetime and takes it
   * with it. */
  int supported = 0;
  std::thread probe([&supported] {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      auto interop =
          winrt::get_activation_factory<wm::SystemMediaTransportControls,
                                        ISystemMediaTransportControlsInterop>();
      supported = interop ? 1 : 0;
    } catch (winrt::hresult_error const &) {
      supported = 0;
    }
    winrt::uninit_apartment();
  });
  probe.join();
  return supported;
}

MiniAVMediaSessionResult ms_platform_create(MiniAVMediaSession *session,
                                            const char *app_name) {
  auto *backend = new (std::nothrow) SmtcBackend();
  if (backend == nullptr) {
    ms_set_last_error("out of memory");
    return MINIAV_MS_ERROR_INTERNAL;
  }
  backend->session = session;
  backend->pending.actions = session->actions;
  backend->pending.actions_dirty = true;

  backend->thread =
      std::thread(PumpThread, backend, Widen(app_name));

  std::unique_lock<std::mutex> lock(backend->mutex);
  backend->ready_cv.wait(lock, [backend] { return backend->ready; });
  const bool ok = backend->ok;
  const std::string error = backend->error;
  lock.unlock();

  if (!ok) {
    backend->thread.join();
    delete backend;
    ms_set_last_error(error.empty() ? "SMTC unavailable" : error.c_str());
    return MINIAV_MS_ERROR_UNSUPPORTED;
  }

  session->platform = backend;
  PostApply(backend);
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_destroy(MiniAVMediaSession *session) {
  auto *backend = static_cast<SmtcBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_OK;
  session->platform = nullptr;

  if (backend->thread_id != 0) {
    PostThreadMessageW(backend->thread_id, WM_MS_QUIT, 0, 0);
  }
  if (backend->thread.joinable()) backend->thread.join();
  /* After the join: the pump thread has revoked the handlers and dropped the
   * SMTC reference, so nothing can still be reading the thumbnail. */
  if (!backend->artwork_temp_path.empty()) {
    DeleteFileW(backend->artwork_temp_path.c_str());
  }
  delete backend;
  SetDescribe(std::string());
  return MINIAV_MS_OK;
}

size_t ms_platform_describe(char *buf, size_t buf_len) {
  std::lock_guard<std::mutex> lock(g_describe_mutex);
  const size_t n = g_describe.size();
  if (buf != nullptr && buf_len > 0) {
    const size_t copy = (n < buf_len - 1) ? n : buf_len - 1;
    memcpy(buf, g_describe.data(), copy);
    buf[copy] = '\0';
  }
  return n;
}

MiniAVMediaSessionResult ms_platform_set_metadata(
    MiniAVMediaSession *session, const MiniAVMediaSessionMetadata *metadata) {
  auto *backend = static_cast<SmtcBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;
  /* Resolve artwork to a URI before taking the lock: writing a temp file can
   * block on disk, and the pump thread must never wait behind that. */
  std::wstring artwork_uri;
  if (metadata->artwork_path != nullptr && metadata->artwork_path[0] != '\0') {
    const std::wstring path = Widen(metadata->artwork_path);
    /* An already-absolute URI passes through; a bare path becomes file:///. */
    artwork_uri = (path.find(L"://") != std::wstring::npos)
                      ? path
                      : PathToFileUri(path);
  } else if (metadata->artwork_bytes != nullptr &&
             metadata->artwork_bytes_len > 0) {
    const std::wstring temp = TempArtworkPath(metadata->artwork_mime);
    if (!temp.empty() && WriteFileBytes(temp, metadata->artwork_bytes,
                                        metadata->artwork_bytes_len)) {
      /* Reap the previous track's file. Deferred, not immediate: SMTC may still
       * be reading it to paint the outgoing card, and DeleteFileW on an open
       * handle simply fails — so a miss here costs one stale temp file, not a
       * broken thumbnail. */
      if (!backend->artwork_temp_path.empty()) {
        DeleteFileW(backend->artwork_temp_path.c_str());
      }
      backend->artwork_temp_path = temp;
      artwork_uri = PathToFileUri(temp);
    }
  }

  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    backend->pending.title = Widen(metadata->title);
    backend->pending.artist = Widen(metadata->artist);
    backend->pending.album = Widen(metadata->album);
    backend->pending.track_number = metadata->track_number;
    backend->pending.artwork_uri = artwork_uri;
    backend->pending.metadata_dirty = true;
  }
  PostApply(backend);
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_state(MiniAVMediaSession *session,
                                               MiniAVMediaSessionState state) {
  auto *backend = static_cast<SmtcBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;
  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    backend->pending.state = state;
    backend->pending.state_dirty = true;
  }
  PostApply(backend);
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_position(
    MiniAVMediaSession *session, const MiniAVMediaSessionPosition *position) {
  auto *backend = static_cast<SmtcBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;
  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    backend->pending.position_us = position->position_us;
    backend->pending.duration_us = position->duration_us;
    backend->pending.speed = position->speed;
    backend->pending.position_dirty = true;
  }
  PostApply(backend);
  return MINIAV_MS_OK;
}

MiniAVMediaSessionResult ms_platform_set_actions(MiniAVMediaSession *session,
                                                 uint32_t actions) {
  auto *backend = static_cast<SmtcBackend *>(session->platform);
  if (backend == nullptr) return MINIAV_MS_ERROR_UNSUPPORTED;
  {
    std::lock_guard<std::mutex> lock(backend->mutex);
    backend->pending.actions = actions;
    backend->pending.actions_dirty = true;
  }
  PostApply(backend);
  return MINIAV_MS_OK;
}

}  // extern "C"
