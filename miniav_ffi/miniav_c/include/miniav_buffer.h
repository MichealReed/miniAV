#ifndef MINIAV_BUFFER_H
#define MINIAV_BUFFER_H

#include "miniav_types.h" // Includes the format enums now
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Buffer Type ---
typedef enum {
  MINIAV_BUFFER_TYPE_UNKNOWN = 0,
  MINIAV_BUFFER_TYPE_VIDEO,
  MINIAV_BUFFER_TYPE_AUDIO
} MiniAVBufferType;

// --- Pixel Formats --- (Removed from here)
// --- Audio Formats --- (Removed from here)

// --- Buffer Struct ---
typedef struct {
  MiniAVBufferType type;
  int64_t timestamp_us; // Monotonic timestamp in microseconds

  union {
    struct {
      uint32_t width;
      uint32_t height;
      MiniAVPixelFormat pixel_format; // Now defined via miniav_types.h
      uint32_t stride_bytes[4]; // Stride for each plane (up to 4)
      void *planes[4];          // Data pointers for each plane
    } video;
    struct {
      uint32_t frame_count;
      uint32_t channel_count;
      MiniAVAudioFormat sample_format; // Now defined via miniav_types.h
      void *data; // Pointer to audio data
    } audio;
  } data;

  size_t data_size_bytes; // Total size of the raw data
  void *user_data;        // User data pointer for callback
  void *internal_handle;  // Opaque handle for MiniAV_ReleaseBuffer
} MiniAVBuffer;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_BUFFER_H