#include "input_context_win_rawinput.h"
#include "../../../include/miniav_types.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_time.h"
#include "../../common/miniav_utils.h"

#include <windows.h>
#include <xinput.h>

#include <string.h>

// --- Platform-specific context data ---

#define MINIAV_INPUT_MAX_GAMEPADS 4

typedef struct InputPlatformWin {
  // Hook thread
  HANDLE hook_thread;
  DWORD hook_thread_id;
  volatile LONG stop_requested;

  // Low-level hooks (owned by hook thread)
  HHOOK keyboard_hook;
  HHOOK mouse_hook;

  // Gamepad polling thread
  HANDLE gamepad_thread;
  volatile LONG gamepad_stop_requested;

  // Configuration snapshot (read by threads)
  uint32_t input_types;
  uint32_t mouse_throttle_hz;
  uint32_t gamepad_poll_hz;

  // Callbacks + user_data (read by threads)
  MiniAVKeyboardCallback keyboard_cb;
  MiniAVMouseCallback mouse_cb;
  MiniAVGamepadCallback gamepad_cb;
  void *user_data;

  // Mouse throttle state
  LARGE_INTEGER throttle_interval;
  LARGE_INTEGER last_mouse_move_time;

  // Previous gamepad state for change detection
  XINPUT_STATE prev_gamepad_state[MINIAV_INPUT_MAX_GAMEPADS];
  bool gamepad_was_connected[MINIAV_INPUT_MAX_GAMEPADS];
} InputPlatformWin;

// --- Thread-local storage for callback routing ---
// We store the platform pointer in a global so the hook procs can reach it.
// Only one input context can be active at a time per process with this approach.
static InputPlatformWin *g_active_input_platform = NULL;

// --- Helpers ---

static uint64_t win_get_timestamp_us(void) {
  LARGE_INTEGER freq, counter;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&counter);
  return (uint64_t)((double)counter.QuadPart / (double)freq.QuadPart *
                    1000000.0);
}

// --- Keyboard Hook Proc ---

static LRESULT CALLBACK
keyboard_hook_proc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION && g_active_input_platform &&
      g_active_input_platform->keyboard_cb) {
    KBDLLHOOKSTRUCT *kb = (KBDLLHOOKSTRUCT *)lParam;
    MiniAVKeyboardEvent event;
    memset(&event, 0, sizeof(event));
    event.timestamp_us = win_get_timestamp_us();
    event.key_code = kb->vkCode;
    event.scan_code = kb->scanCode;

    if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
      event.action = MINIAV_KEY_ACTION_DOWN;
    } else {
      event.action = MINIAV_KEY_ACTION_UP;
    }

    g_active_input_platform->keyboard_cb(&event,
                                         g_active_input_platform->user_data);
  }
  return CallNextHookEx(NULL, nCode, wParam, lParam);
}

// --- Mouse Hook Proc ---

static LRESULT CALLBACK mouse_hook_proc(int nCode, WPARAM wParam,
                                        LPARAM lParam) {
  if (nCode != HC_ACTION || !g_active_input_platform ||
      !g_active_input_platform->mouse_cb) {
    return CallNextHookEx(NULL, nCode, wParam, lParam);
  }

  MSLLHOOKSTRUCT *ms = (MSLLHOOKSTRUCT *)lParam;
  InputPlatformWin *plat = g_active_input_platform;

  MiniAVMouseEvent event;
  memset(&event, 0, sizeof(event));
  event.timestamp_us = win_get_timestamp_us();
  event.x = ms->pt.x;
  event.y = ms->pt.y;

  switch (wParam) {
  case WM_MOUSEMOVE:
    event.action = MINIAV_MOUSE_ACTION_MOVE;
    // Apply throttle for mouse move events
    if (plat->throttle_interval.QuadPart > 0) {
      LARGE_INTEGER now;
      QueryPerformanceCounter(&now);
      LONGLONG elapsed =
          now.QuadPart - plat->last_mouse_move_time.QuadPart;
      if (elapsed < plat->throttle_interval.QuadPart) {
        return CallNextHookEx(NULL, nCode, wParam, lParam);
      }
      plat->last_mouse_move_time = now;
    }
    break;

  case WM_LBUTTONDOWN:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_DOWN;
    event.button = MINIAV_MOUSE_BUTTON_LEFT;
    break;
  case WM_LBUTTONUP:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_UP;
    event.button = MINIAV_MOUSE_BUTTON_LEFT;
    break;
  case WM_RBUTTONDOWN:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_DOWN;
    event.button = MINIAV_MOUSE_BUTTON_RIGHT;
    break;
  case WM_RBUTTONUP:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_UP;
    event.button = MINIAV_MOUSE_BUTTON_RIGHT;
    break;
  case WM_MBUTTONDOWN:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_DOWN;
    event.button = MINIAV_MOUSE_BUTTON_MIDDLE;
    break;
  case WM_MBUTTONUP:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_UP;
    event.button = MINIAV_MOUSE_BUTTON_MIDDLE;
    break;
  case WM_XBUTTONDOWN:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_DOWN;
    event.button = (HIWORD(ms->mouseData) == XBUTTON1)
                       ? MINIAV_MOUSE_BUTTON_X1
                       : MINIAV_MOUSE_BUTTON_X2;
    break;
  case WM_XBUTTONUP:
    event.action = MINIAV_MOUSE_ACTION_BUTTON_UP;
    event.button = (HIWORD(ms->mouseData) == XBUTTON1)
                       ? MINIAV_MOUSE_BUTTON_X1
                       : MINIAV_MOUSE_BUTTON_X2;
    break;
  case WM_MOUSEWHEEL:
    event.action = MINIAV_MOUSE_ACTION_WHEEL;
    event.wheel_delta = (int32_t)((short)HIWORD(ms->mouseData));
    break;

  default:
    return CallNextHookEx(NULL, nCode, wParam, lParam);
  }

  plat->mouse_cb(&event, plat->user_data);
  return CallNextHookEx(NULL, nCode, wParam, lParam);
}

// --- Hook Thread ---

static DWORD WINAPI hook_thread_proc(LPVOID param) {
  InputPlatformWin *plat = (InputPlatformWin *)param;

  // Install hooks on this thread
  if (plat->input_types & MINIAV_INPUT_TYPE_KEYBOARD) {
    plat->keyboard_hook =
        SetWindowsHookExW(WH_KEYBOARD_LL, keyboard_hook_proc, NULL, 0);
    if (!plat->keyboard_hook) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "Failed to install keyboard hook, error: %lu",
                 GetLastError());
    } else {
      miniav_log(MINIAV_LOG_LEVEL_INFO, "Keyboard hook installed.");
    }
  }

  if (plat->input_types & MINIAV_INPUT_TYPE_MOUSE) {
    plat->mouse_hook =
        SetWindowsHookExW(WH_MOUSE_LL, mouse_hook_proc, NULL, 0);
    if (!plat->mouse_hook) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "Failed to install mouse hook, error: %lu", GetLastError());
    } else {
      miniav_log(MINIAV_LOG_LEVEL_INFO, "Mouse hook installed.");
    }
  }

  // Message pump — required for low-level hooks to receive events
  MSG msg;
  while (!InterlockedCompareExchange(&plat->stop_requested, 0, 0)) {
    BOOL ret = PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE);
    if (ret) {
      if (msg.message == WM_QUIT) {
        break;
      }
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    } else {
      // No messages, sleep briefly to avoid busy-wait
      MsgWaitForMultipleObjects(0, NULL, FALSE, 10, QS_ALLINPUT);
    }
  }

  // Remove hooks
  if (plat->keyboard_hook) {
    UnhookWindowsHookEx(plat->keyboard_hook);
    plat->keyboard_hook = NULL;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Keyboard hook removed.");
  }
  if (plat->mouse_hook) {
    UnhookWindowsHookEx(plat->mouse_hook);
    plat->mouse_hook = NULL;
    miniav_log(MINIAV_LOG_LEVEL_INFO, "Mouse hook removed.");
  }

  return 0;
}

// --- Gamepad Polling Thread ---

static DWORD WINAPI gamepad_poll_thread_proc(LPVOID param) {
  InputPlatformWin *plat = (InputPlatformWin *)param;
  DWORD poll_interval_ms =
      (plat->gamepad_poll_hz > 0) ? (1000 / plat->gamepad_poll_hz) : 16;

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "Gamepad polling started at ~%u Hz (interval %lu ms).",
             plat->gamepad_poll_hz ? plat->gamepad_poll_hz : 60,
             poll_interval_ms);

  while (!InterlockedCompareExchange(&plat->gamepad_stop_requested, 0, 0)) {
    uint64_t ts = win_get_timestamp_us();

    for (DWORD i = 0; i < MINIAV_INPUT_MAX_GAMEPADS; i++) {
      XINPUT_STATE state;
      memset(&state, 0, sizeof(state));
      DWORD result = XInputGetState(i, &state);

      bool connected = (result == ERROR_SUCCESS);
      bool was_connected = plat->gamepad_was_connected[i];

      // Report if connection state changed or if state differs
      if (connected != was_connected ||
          (connected &&
           state.dwPacketNumber !=
               plat->prev_gamepad_state[i].dwPacketNumber)) {
        MiniAVGamepadEvent event;
        memset(&event, 0, sizeof(event));
        event.timestamp_us = ts;
        event.gamepad_index = i;
        event.connected = connected;

        if (connected) {
          event.buttons = state.Gamepad.wButtons;
          event.left_stick_x = state.Gamepad.sThumbLX;
          event.left_stick_y = state.Gamepad.sThumbLY;
          event.right_stick_x = state.Gamepad.sThumbRX;
          event.right_stick_y = state.Gamepad.sThumbRY;
          event.left_trigger = state.Gamepad.bLeftTrigger;
          event.right_trigger = state.Gamepad.bRightTrigger;
        }

        plat->gamepad_cb(&event, plat->user_data);
        plat->prev_gamepad_state[i] = state;
        plat->gamepad_was_connected[i] = connected;
      }
    }

    Sleep(poll_interval_ms);
  }

  miniav_log(MINIAV_LOG_LEVEL_INFO, "Gamepad polling stopped.");
  return 0;
}

// --- InputContextInternalOps Implementation ---

static MiniAVResultCode input_win_init_platform(MiniAVInputContext *ctx) {
  // Platform context was already allocated in platform_init_for_selection
  return MINIAV_SUCCESS;
}

static MiniAVResultCode input_win_destroy_platform(MiniAVInputContext *ctx) {
  if (ctx->platform_ctx) {
    InputPlatformWin *plat = (InputPlatformWin *)ctx->platform_ctx;

    // Clear global pointer if it matches
    if (g_active_input_platform == plat) {
      g_active_input_platform = NULL;
    }

    miniav_free(plat);
    ctx->platform_ctx = NULL;
  }
  return MINIAV_SUCCESS;
}

static MiniAVResultCode
input_win_enumerate_gamepads(MiniAVDeviceInfo **devices_out,
                             uint32_t *count_out) {
  // Count connected gamepads
  uint32_t connected = 0;
  bool pad_connected[MINIAV_INPUT_MAX_GAMEPADS] = {false};

  for (DWORD i = 0; i < MINIAV_INPUT_MAX_GAMEPADS; i++) {
    XINPUT_STATE state;
    memset(&state, 0, sizeof(state));
    if (XInputGetState(i, &state) == ERROR_SUCCESS) {
      pad_connected[i] = true;
      connected++;
    }
  }

  if (connected == 0) {
    *devices_out = NULL;
    *count_out = 0;
    return MINIAV_SUCCESS;
  }

  MiniAVDeviceInfo *devices =
      (MiniAVDeviceInfo *)miniav_calloc(connected, sizeof(MiniAVDeviceInfo));
  if (!devices) {
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  uint32_t idx = 0;
  for (DWORD i = 0; i < MINIAV_INPUT_MAX_GAMEPADS && idx < connected; i++) {
    if (pad_connected[i]) {
      snprintf(devices[idx].device_id, MINIAV_DEVICE_ID_MAX_LEN, "xinput_%u",
               (unsigned)i);
      snprintf(devices[idx].name, MINIAV_DEVICE_NAME_MAX_LEN,
               "XInput Gamepad %u", (unsigned)i);
      devices[idx].is_default = (i == 0);
      idx++;
    }
  }

  *devices_out = devices;
  *count_out = connected;
  return MINIAV_SUCCESS;
}

static MiniAVResultCode input_win_configure(MiniAVInputContext *ctx,
                                            const MiniAVInputConfig *config) {
  InputPlatformWin *plat = (InputPlatformWin *)ctx->platform_ctx;
  if (!plat) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  // Store configuration
  plat->input_types = config->input_types;
  plat->keyboard_cb = config->keyboard_callback;
  plat->mouse_cb = config->mouse_callback;
  plat->gamepad_cb = config->gamepad_callback;
  plat->user_data = config->user_data;

  // Set mouse throttle
  plat->mouse_throttle_hz = config->mouse_throttle_hz;
  if (plat->mouse_throttle_hz > 0) {
    LARGE_INTEGER freq;
    QueryPerformanceFrequency(&freq);
    plat->throttle_interval.QuadPart =
        freq.QuadPart / plat->mouse_throttle_hz;
  } else {
    plat->throttle_interval.QuadPart = 0;
  }

  // Set gamepad poll rate
  plat->gamepad_poll_hz =
      (config->gamepad_poll_hz > 0) ? config->gamepad_poll_hz : 60;

  return MINIAV_SUCCESS;
}

static MiniAVResultCode input_win_start_capture(MiniAVInputContext *ctx) {
  InputPlatformWin *plat = (InputPlatformWin *)ctx->platform_ctx;
  if (!plat) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  // Set as the active platform for hook procs
  g_active_input_platform = plat;

  InterlockedExchange(&plat->stop_requested, 0);
  InterlockedExchange(&plat->gamepad_stop_requested, 0);

  // Start hook thread for keyboard/mouse if needed
  if (plat->input_types & (MINIAV_INPUT_TYPE_KEYBOARD | MINIAV_INPUT_TYPE_MOUSE)) {
    plat->hook_thread = CreateThread(NULL, 0, hook_thread_proc, plat, 0,
                                     &plat->hook_thread_id);
    if (!plat->hook_thread) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "Failed to create hook thread, error: %lu", GetLastError());
      g_active_input_platform = NULL;
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }

  // Start gamepad polling thread if needed
  if ((plat->input_types & MINIAV_INPUT_TYPE_GAMEPAD) && plat->gamepad_cb) {
    memset(plat->prev_gamepad_state, 0, sizeof(plat->prev_gamepad_state));
    memset(plat->gamepad_was_connected, 0,
           sizeof(plat->gamepad_was_connected));

    plat->gamepad_thread =
        CreateThread(NULL, 0, gamepad_poll_thread_proc, plat, 0, NULL);
    if (!plat->gamepad_thread) {
      miniav_log(MINIAV_LOG_LEVEL_ERROR,
                 "Failed to create gamepad polling thread, error: %lu",
                 GetLastError());
      // Stop the hook thread if it was started
      if (plat->hook_thread) {
        InterlockedExchange(&plat->stop_requested, 1);
        PostThreadMessageW(plat->hook_thread_id, WM_QUIT, 0, 0);
        WaitForSingleObject(plat->hook_thread, 3000);
        CloseHandle(plat->hook_thread);
        plat->hook_thread = NULL;
      }
      g_active_input_platform = NULL;
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
  }

  return MINIAV_SUCCESS;
}

static MiniAVResultCode input_win_stop_capture(MiniAVInputContext *ctx) {
  InputPlatformWin *plat = (InputPlatformWin *)ctx->platform_ctx;
  if (!plat) {
    return MINIAV_ERROR_NOT_INITIALIZED;
  }

  // Signal hook thread to stop
  if (plat->hook_thread) {
    InterlockedExchange(&plat->stop_requested, 1);
    PostThreadMessageW(plat->hook_thread_id, WM_QUIT, 0, 0);
    DWORD wait_result = WaitForSingleObject(plat->hook_thread, 5000);
    if (wait_result == WAIT_TIMEOUT) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "Hook thread did not exit in time, terminating.");
      TerminateThread(plat->hook_thread, 1);
    }
    CloseHandle(plat->hook_thread);
    plat->hook_thread = NULL;
    plat->hook_thread_id = 0;
  }

  // Signal gamepad thread to stop
  if (plat->gamepad_thread) {
    InterlockedExchange(&plat->gamepad_stop_requested, 1);
    DWORD wait_result = WaitForSingleObject(plat->gamepad_thread, 5000);
    if (wait_result == WAIT_TIMEOUT) {
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "Gamepad thread did not exit in time, terminating.");
      TerminateThread(plat->gamepad_thread, 1);
    }
    CloseHandle(plat->gamepad_thread);
    plat->gamepad_thread = NULL;
  }

  // Clear global pointer
  if (g_active_input_platform == plat) {
    g_active_input_platform = NULL;
  }

  return MINIAV_SUCCESS;
}

// --- Ops table and init ---

const InputContextInternalOps g_input_ops_win = {
    .init_platform = input_win_init_platform,
    .destroy_platform = input_win_destroy_platform,
    .enumerate_gamepads = input_win_enumerate_gamepads,
    .configure = input_win_configure,
    .start_capture = input_win_start_capture,
    .stop_capture = input_win_stop_capture,
};

MiniAVResultCode
miniav_input_context_platform_init_windows(MiniAVInputContext *ctx) {
  InputPlatformWin *plat =
      (InputPlatformWin *)miniav_calloc(1, sizeof(InputPlatformWin));
  if (!plat) {
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->platform_ctx = plat;
  ctx->ops = &g_input_ops_win;
  return MINIAV_SUCCESS;
}
