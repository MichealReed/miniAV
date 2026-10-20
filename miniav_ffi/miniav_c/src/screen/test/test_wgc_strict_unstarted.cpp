// Headless production-provider qualification. Never creates a window, starts
// capture, obtains a frame, or renders pixels. Exit77 is environment refusal.
#include "../../../include/miniav.h"
#include <windows.h>
#include <cstdio>
#include <cstdlib>

static void require(bool value, const char *what) {
  if (!value) { std::fprintf(stderr, "FAIL %s\n", what); std::exit(1); }
}
static void no_frame(const MiniAVBuffer *, void *) {
  require(false, "unstarted provider delivered a frame");
}
static MiniAVWindowsAppAdmissionV1 admitted(HANDLE process, uint64_t end) {
  FILETIME created{}, exited{}, kernel{}, user{};
  require(GetProcessTimes(process, &created, &exited, &kernel, &user) != FALSE,
          "original process creation");
  MiniAVWindowsAppAdmissionV1 result{};
  result.struct_size = sizeof(result);
  result.abi_version = 1;
  result.host_epoch = 11;
  result.grant_generation = 12;
  result.runtime_source_generation = 13;
  result.valid_until_tick_ms = end;
  result.admitted_process_handle = reinterpret_cast<uint64_t>(process);
  result.process_creation_filetime = (uint64_t(created.dwHighDateTime) << 32) |
                                    created.dwLowDateTime;
  result.process_id = GetCurrentProcessId();
  // Synthetic original host attestation for this non-capturing ABI case. It
  // does not qualify installed-provider identity or consent in the SDK bridge.
  result.executable_sha256[0] = 1;
  return result;
}
static MiniAVWindowsStrictRetirementV1 receipt(MiniAVScreenContextHandle ctx) {
  MiniAVWindowsStrictRetirementV1 result{};
  result.struct_size = sizeof(result);
  result.abi_version = 1;
  require(MiniAV_Screen_Windows_GetStrictRetirementV1(ctx, &result) == 0,
          "retirement query");
  return result;
}
static void retire(MiniAVScreenContextHandle ctx, int reason) {
  const auto until = GetTickCount64() + 3000;
  for (;;) {
    const auto value = receipt(ctx);
    require(value.state != 3, "cleanup failed instead of retiring");
    if (value.state == 2) {
      require(value.flags == 31 && value.callbacks_in_flight == 0 &&
          value.buffers_outstanding == 0 && value.frames_posted == 0 &&
          value.frames_released == 0 && value.cleanup_error == 0 &&
          value.terminal_reason == reason && value.capture_id == 0,
          "actual unstarted retirement witness");
      break;
    }
    require(GetTickCount64() < until, "unstarted retirement remained pending");
    Sleep(2);
  }
  require(MiniAV_Screen_DestroyContext(ctx) == 0,
          "exclusive checked destruction after native worker exit");
}
static MiniAVScreenContextHandle context() {
  MiniAVScreenContextHandle result = nullptr;
  require(MiniAV_Screen_CreateContext(&result) == 0 && result,
          "create production screen context");
  return result;
}

int main() {
  uint32_t maximum = 99;
  require(MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1(nullptr) ==
              MINIAV_ERROR_INVALID_ARG, "null producer-bound output refused");
  require(MiniAV_Screen_Windows_StrictMaxOutstandingBuffersV1(&maximum) == 0 &&
              maximum == 3, "native fixed producer-buffer bound before context");
  uint32_t bits = 0;
  uint64_t now = 0;
  const auto support = MiniAV_Screen_Windows_StrictCapabilitiesV1(&bits, &now);
  if (support != 0 || bits != 15 || !now) {
    std::printf("UNAVAILABLE strict WGC code=%d bits=%u tick=%llu\n",
                support, bits, static_cast<unsigned long long>(now));
    return 77;
  }
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                                FALSE, GetCurrentProcessId());
  require(process != nullptr, "original query/wait process handle");
  auto original = admitted(process, GetTickCount64() + 10000);
  MiniAVVideoInfo format{0, 0, MINIAV_PIXEL_FORMAT_BGRA32, 60, 1,
                         MINIAV_OUTPUT_PREFERENCE_GPU};
  {
    auto ctx = context();
    require(MiniAV_Screen_SetCaptureCursor(ctx, false) == 0,
            "pre-claim cursor setter");
    require(MiniAV_Screen_Windows_RequestStrictStopV1(ctx, 0) == 0,
            "stop before Begin");
    MiniAVWindowsSelectionNonceV1 nonce{sizeof(nonce), 1};
    MiniAVWindowsScreenCandidateV1 *candidates = nullptr;
    uint32_t count = 99;
    require(MiniAV_Screen_Windows_BeginStrictSelectionV1(ctx, &original,
        &nonce, &candidates, &count) == MINIAV_ERROR_INVALID_OPERATION,
        "stopped context cannot Begin");
    require(!candidates && !count && !nonce.struct_size,
            "late Begin publishes no candidates or nonce");
    require(MiniAV_Screen_StartCapture(ctx, no_frame, nullptr) ==
                MINIAV_ERROR_INVALID_OPERATION,
            "generic Start cannot revive strict stop");
    require(MiniAV_Screen_ConfigureWindow(ctx, "HWND:0", &format, false) ==
                MINIAV_ERROR_INVALID_OPERATION,
            "generic configure cannot replace strict owner");
    require(MiniAV_Screen_SetCaptureCursor(ctx, true) ==
                MINIAV_ERROR_INVALID_OPERATION,
            "stopped strict cursor mutation refused");
    retire(ctx, 0);
    std::puts("PASS permanent stop-before-Begin and actual unstarted retirement");
  }
  {
    auto ctx = context();
    MiniAVWindowsSelectionNonceV1 nonce{sizeof(nonce), 1};
    MiniAVWindowsScreenCandidateV1 *candidates = nullptr;
    uint32_t count = 0;
    require(MiniAV_Screen_Windows_BeginStrictSelectionV1(ctx, &original,
        &nonce, &candidates, &count) == 0, "original live process Begin");
    require(count == 0 && nonce.struct_size == sizeof(nonce),
            "headless process has no selected capture windows");
    MiniAV_Free(candidates);
    require(receipt(ctx).state == 0, "unstarted selection is active");
    require(MiniAV_Screen_DestroyContext(ctx) == MINIAV_ERROR_TIMEOUT,
            "Destroy fences active owner and retains parent until retirement");
    retire(ctx, 0);
    std::puts("PASS admitted process selection, pending destruction and join");
  }
  {
    auto ctx = context();
    MiniAVWindowsSelectionNonceV1 nonce{sizeof(nonce), 1};
    MiniAVWindowsScreenCandidateV1 *candidates = nullptr;
    uint32_t count = 0;
    auto expiring = admitted(process, GetTickCount64() + 150);
    require(MiniAV_Screen_Windows_BeginStrictSelectionV1(ctx, &expiring,
        &nonce, &candidates, &count) == 0, "short original authority Begin");
    require(!count, "headless expiry case selected no windows");
    MiniAV_Free(candidates);
    Sleep(200); // The native watchdog expires without Dart or status polling.
    const auto expired = receipt(ctx);
    require(expired.state != 0 && expired.terminal_reason ==
                MINIAV_ERROR_PERMISSION_DENIED,
            "original deadline cannot be renewed by idle selection");
    retire(ctx, MINIAV_ERROR_PERMISSION_DENIED);
    std::puts("PASS independent original-deadline expiry");
  }
  {
    auto ctx = context();
    require(MiniAV_Screen_ConfigureWindow(ctx, "invalid", &format, false) != 0,
            "generic configuration fails");
    MiniAVWindowsSelectionNonceV1 nonce{sizeof(nonce), 1};
    MiniAVWindowsScreenCandidateV1 *candidates = nullptr;
    uint32_t count = 0;
    require(MiniAV_Screen_Windows_BeginStrictSelectionV1(ctx, &original,
        &nonce, &candidates, &count) == MINIAV_ERROR_INVALID_OPERATION,
        "failed generic configuration permanently spends strict freshness");
    require(MiniAV_Screen_DestroyContext(ctx) == 0,
            "generic teardown still works after failed configuration");
    std::puts("PASS generic claim cannot be upgraded after failure");
  }
  require(CloseHandle(process) != FALSE, "release original process handle");
  std::puts("PASS4 strict unstarted provider; no Start/window/pixels executed");
  return 0;
}
