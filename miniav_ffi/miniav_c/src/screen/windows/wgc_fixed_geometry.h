#pragma once
// Pure production admission around allocation boundaries. No device creation,
// rendering or fallback. Tests substitute only the allocation continuation.
#include "../../../include/miniav_screen_windows_strict.h"
#include <cstdint>
#include <utility>

namespace miniav::wgc_strict {
constexpr uint32_t pool_slots = 2;
constexpr uint32_t outstanding_snapshots = 3;
constexpr uint64_t max_frame_bytes = 128ull * 1024 * 1024;

inline bool frame_bytes(uint32_t width, uint32_t height, uint64_t &bytes) {
  bytes = 0;
  if (!width || !height || width > max_frame_bytes / 4 ||
      height > max_frame_bytes / (uint64_t(width) * 4)) return false;
  bytes = uint64_t(width) * height * 4;
  return true;
}

template<class Allocate>
MiniAVResultCode fixed_pool(const MiniAVVideoInfo &admitted,
    int32_t current_width, int32_t current_height, Allocate &&allocate) {
  uint64_t bytes = 0;
  if (admitted.pixel_format != MINIAV_PIXEL_FORMAT_BGRA32 ||
      admitted.output_preference != MINIAV_OUTPUT_PREFERENCE_GPU ||
      !frame_bytes(admitted.width, admitted.height, bytes) ||
      current_width <= 0 || current_height <= 0 ||
      uint32_t(current_width) != admitted.width ||
      uint32_t(current_height) != admitted.height)
    return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
  return std::forward<Allocate>(allocate)(admitted.width, admitted.height, pool_slots);
}

template<class Allocate>
MiniAVResultCode fixed_snapshot(const MiniAVVideoInfo &admitted,
    int32_t content_width, int32_t content_height,
    uint32_t backing_width, uint32_t backing_height, bool bgra,
    uint32_t mip_levels, uint32_t array_size, uint32_t sample_count,
    uint32_t sample_quality, Allocate &&allocate) {
  if (!bgra || backing_width != admitted.width || backing_height != admitted.height ||
      mip_levels != 1 || array_size != 1 || sample_count != 1 || sample_quality != 0)
    return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
  return fixed_pool(admitted, content_width, content_height,
      [&](uint32_t width, uint32_t height, uint32_t) {
        return std::forward<Allocate>(allocate)(width, height);
      });
}
} // namespace miniav::wgc_strict
