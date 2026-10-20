// CPU production allocation boundary only. No context/device/window/frame is
// created; only the foreign allocation continuation is replaced by a counter.
#include "../windows/wgc_fixed_geometry.h"
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <limits>

static void require(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "FAIL %s\n", message); std::exit(1); }
}
int main() {
  static_assert(sizeof(MiniAVWindowsStrictResourceProfileV1) == 64);
  static_assert(offsetof(MiniAVWindowsStrictResourceProfileV1, frame_bytes) == 48);
  using namespace miniav::wgc_strict;
  MiniAVVideoInfo format{10, 9, MINIAV_PIXEL_FORMAT_BGRA32, 60, 1, MINIAV_OUTPUT_PREFERENCE_GPU};
  unsigned pools = 0, snapshots = 0;
  const auto pool = [&](uint32_t w, uint32_t h, uint32_t slots) {
    require(w == 10 && h == 9 && slots == 2, "pool uses original admitted dimensions");
    ++pools; return MINIAV_SUCCESS;
  };
  const auto snapshot = [&](uint32_t w, uint32_t h) {
    require(w == 10 && h == 9, "snapshot uses original admitted dimensions");
    ++snapshots; return MINIAV_SUCCESS;
  };
  require(fixed_pool(format, 10, 9, pool) == 0 && pools == 1, "exact pool admission");
  for (const auto size : {std::pair<int32_t,int32_t>{11,9}, {9,9}, {10,10}, {10,8}, {0,9}, {-1,9}}) {
    require(fixed_pool(format, size.first, size.second, pool) == MINIAV_ERROR_FORMAT_NOT_SUPPORTED && pools == 1,
            "item resize refuses before pool allocation");
  }
  require(fixed_snapshot(format, 10, 9, 10, 9, true, 1, 1, 1, 0, snapshot) == 0 && snapshots == 1,
          "exact snapshot admission");
  for (int fault = 0; fault < 10; ++fault) {
    require(fixed_snapshot(format, fault == 0 ? 11 : 10, fault == 1 ? 8 : 9,
        fault == 2 ? 11 : 10, fault == 3 ? 8 : 9, fault != 4,
        fault == 5 ? 2 : 1, fault == 6 ? 2 : 1, fault == 7 ? 2 : fault == 8 ? 0 : 1,
        fault == 9 ? 1 : 0, snapshot) == MINIAV_ERROR_FORMAT_NOT_SUPPORTED && snapshots == 1,
        "changed content/backing refuses before snapshot allocation");
  }
  for (int fault = 0; fault < 4; ++fault) {
    auto invalid = format;
    if (fault == 0) invalid.width = 0;
    if (fault == 1) invalid.width = std::numeric_limits<uint32_t>::max();
    if (fault == 2) invalid.pixel_format = MINIAV_PIXEL_FORMAT_UNKNOWN;
    if (fault == 3) invalid.output_preference = MINIAV_OUTPUT_PREFERENCE_CPU;
    require(fixed_pool(invalid, 10, 9, pool) == MINIAV_ERROR_FORMAT_NOT_SUPPORTED && pools == 1,
            "invalid/oversize admitted geometry refuses before allocation");
  }
  uint64_t bytes = 7;
  require(frame_bytes(10, 9, bytes) && bytes == 360, "checked BGRA payload");
  require(!frame_bytes(UINT32_MAX, UINT32_MAX, bytes) && bytes == 0, "overflow never admits a payload");
  std::puts("PASS fixed strict WGC allocation continuations: pool/snapshot dimensions, descriptor profile and overflow; CPU only");
}
