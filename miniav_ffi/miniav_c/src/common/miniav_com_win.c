#if defined(_WIN32)

#include "miniav_com_win.h"
#include "miniav_logging.h"

#include <windows.h>

#include <mfapi.h>
#include <objbase.h>
#include <stdlib.h>

#pragma comment(lib, "ole32")
#pragma comment(lib, "mfplat")

// CoIncrementMTAUsage is Win8+. Resolve it dynamically so the DLL still loads
// on older systems, where a dedicated holder thread provides the same
// guarantee (a thread that joins the MTA and never leaves).
// Cookie typed as void* rather than CO_MTA_USAGE_COOKIE: the SDK gates that
// typedef behind NTDDI_WIN8 and this file must build against older targets.
typedef HRESULT(WINAPI *PFN_CoIncrementMTAUsage)(void **cookie);

static INIT_ONCE g_mta_once = INIT_ONCE_STATIC_INIT;
static INIT_ONCE g_mf_once = INIT_ONCE_STATIC_INIT;
static volatile LONG g_mf_ok = 0;

static volatile LONG g_legacy_cached = -1; // -1 = unread, 0 = off, 1 = on
static volatile LONG g_trace_cached = -1;

static int env_flag_is_one(const char *name) {
  char buf[8];
  DWORD n = GetEnvironmentVariableA(name, buf, (DWORD)sizeof(buf));
  return (n == 1 && buf[0] == '1') ? 1 : 0;
}

int miniav_com_legacy_percall(void) {
  LONG cached = InterlockedCompareExchange(&g_legacy_cached, -1, -1);
  if (cached < 0) {
    cached = env_flag_is_one("MINIAV_LEGACY_COM");
    InterlockedExchange(&g_legacy_cached, cached);
  }
  return (int)cached;
}

static volatile LONG g_legacy_mfcb_cached = -1;

int miniav_mf_legacy_callback_free(void) {
  LONG cached = InterlockedCompareExchange(&g_legacy_mfcb_cached, -1, -1);
  if (cached < 0) {
    cached = env_flag_is_one("MINIAV_LEGACY_MFCB");
    InterlockedExchange(&g_legacy_mfcb_cached, cached);
  }
  return (int)cached;
}

static int com_trace_enabled(void) {
  LONG cached = InterlockedCompareExchange(&g_trace_cached, -1, -1);
  if (cached < 0) {
    cached = env_flag_is_one("MINIAV_COM_TRACE");
    InterlockedExchange(&g_trace_cached, cached);
  }
  return (int)cached;
}

void miniav_com_trace(const char *where, unsigned long hr) {
  if (!com_trace_enabled())
    return;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "COMTRACE %s tid=%lu hr=0x%lx",
             where ? where : "?", GetCurrentThreadId(), hr);
}

// Pre-Win8 fallback: a thread that joins the MTA and parks forever.
static DWORD WINAPI mta_holder_thread(LPVOID param) {
  (void)param;
  HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(hr) && hr != S_FALSE) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "COM: MTA holder thread CoInitializeEx failed: 0x%lx",
               (unsigned long)hr);
    return 1;
  }
  for (;;) {
    Sleep(INFINITE);
  }
}

static BOOL CALLBACK mta_init_once(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  (void)once;
  (void)param;
  (void)ctx;

  HMODULE ole32 = GetModuleHandleW(L"ole32.dll");
  if (!ole32)
    ole32 = LoadLibraryW(L"ole32.dll");

  PFN_CoIncrementMTAUsage inc =
      ole32 ? (PFN_CoIncrementMTAUsage)(void *)GetProcAddress(
                  ole32, "CoIncrementMTAUsage")
            : NULL;

  if (inc) {
    // Deliberately never paired with CoDecrementMTAUsage: this is the
    // process-lifetime reference that keeps the MTA (and every COM object in
    // it) alive across isolate churn. See miniav_com_win.h.
    void *cookie = NULL;
    HRESULT hr = inc(&cookie);
    miniav_com_trace("CoIncrementMTAUsage", (unsigned long)hr);
    if (SUCCEEDED(hr)) {
      miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                 "COM: process MTA reference acquired (CoIncrementMTAUsage).");
      return TRUE;
    }
    miniav_log(MINIAV_LOG_LEVEL_WARN,
               "COM: CoIncrementMTAUsage failed: 0x%lx — falling back to a "
               "holder thread.",
               (unsigned long)hr);
  }

  HANDLE t = CreateThread(NULL, 0, mta_holder_thread, NULL, 0, NULL);
  if (t) {
    CloseHandle(t); // the thread outlives the process, nothing to join
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "COM: process MTA reference acquired (holder thread).");
  } else {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "COM: failed to create MTA holder thread: %lu", GetLastError());
  }
  return TRUE;
}

void miniav_com_ensure_mta(void) {
  InitOnceExecuteOnce(&g_mta_once, mta_init_once, NULL, NULL);
}

static BOOL CALLBACK mf_init_once(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  (void)once;
  (void)param;
  (void)ctx;
  HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
  miniav_com_trace("MFStartup", (unsigned long)hr);
  if (FAILED(hr)) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "MF: MFStartup failed: 0x%lx",
               (unsigned long)hr);
    return TRUE; // do not retry-storm; g_mf_ok stays 0
  }
  // Deliberately never paired with MFShutdown: MF's Startup/Shutdown count is
  // process-global, and any isolate driving it to zero invalidates every live
  // MF object in every other isolate. See miniav_com_win.h.
  InterlockedExchange(&g_mf_ok, 1);
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "MF: platform started (process-lifetime).");
  return TRUE;
}

MINIAV_API int MiniAV_Win_ComOwnershipMode(void) {
  return miniav_com_legacy_percall() ? 0 : 1;
}

int miniav_mf_ensure(void) {
  miniav_com_ensure_mta();
  InitOnceExecuteOnce(&g_mf_once, mf_init_once, NULL, NULL);
  return (int)InterlockedCompareExchange(&g_mf_ok, 0, 0);
}

#else

// ISO C requires a translation unit to contain at least one declaration; this
// file is globbed into every platform build but is Windows-only in substance.
typedef int miniav_com_win_not_used_on_this_platform_t;

#endif // _WIN32
