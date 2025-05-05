#ifndef MINIAV_BUFFER_H
#define MINIAV_BUFFER_H

#include <stdint.h>
#include <stddef.h>
#include "miniav_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- Buffer Type ---
typedef enum : uint32_t {
    MINIAV_BUFFER_TYPE_UNKNOWN = 0,
    MINIAV_BUFFER_TYPE_VIDEO,
    MINIAV_BUFFER_TYPE_AUDIO
} MiniAVBufferType;

// --- Pixel Formats ---
typedef enum : uint32_t {
    MINIAV_PIXEL_FORMAT_UNKNOWN = 0,
    MINIAV_PIXEL_FORMAT_I420,    // Planar YUV 4:2:0
    MINIAV_PIXEL_FORMAT_NV12,    // Semi-Planar YUV 4:2:0
    MINIAV_PIXEL_FORMAT_NV21,    // Semi-Planar YUV 4:2:0
    MINIAV_PIXEL_FORMAT_YUY2,    // Packed YUV 4:2:2
    MINIAV_PIXEL_FORMAT_UYVY,    // Packed YUV 4:2:2
    MINIAV_PIXEL_FORMAT_RGB24,   // Packed RGB
    MINIAV_PIXEL_FORMAT_BGR24,   // Packed BGR
    MINIAV_PIXEL_FORMAT_RGBA32,  // Packed RGBA
    MINIAV_PIXEL_FORMAT_BGRA32,  // Packed BGRA
    MINIAV_PIXEL_FORMAT_ARGB32,  // Packed ARGB
    MINIAV_PIXEL_FORMAT_ABGR32,  // Packed ABGR
    MINIAV_PIXEL_FORMAT_MJPEG    // Motion JPEG (compressed)
} MiniAVPixelFormat;

// --- Audio Formats ---
typedef enum : uint32_t {
    MINIAV_AUDIO_FORMAT_UNKNOWN = 0,
    MINIAV_AUDIO_FORMAT_U8,      // Unsigned 8-bit integer
    MINIAV_AUDIO_FORMAT_S16,     // Signed 16-bit integer
    MINIAV_AUDIO_FORMAT_S24,     // Signed 24-bit integer (often packed in 32 bits)
    MINIAV_AUDIO_FORMAT_S32,     // Signed 32-bit integer
    MINIAV_AUDIO_FORMAT_F32      // 32-bit floating point
} MiniAVAudioFormat;

// --- Buffer Struct ---
typedef struct {
    MiniAVBufferType type;
    int64_t timestamp_us; // Monotonic timestamp in microseconds

    union {
        struct {
            uint32_t width;
            uint32_t height;
            MiniAVPixelFormat pixel_format;
            uint32_t stride_bytes[4]; // Stride for each plane (up to 4)
            void* planes[4];          // Data pointers for each plane
            // Optionally: camera intrinsics, etc.
        } video;
        struct {
            uint32_t frame_count;
            uint32_t channel_count;
            MiniAVAudioFormat sample_format;
            void* data; // Pointer to audio data
        } audio;
    } data;

    size_t data_size_bytes; // Total size of the raw data
    void* user_data;        // User data pointer for callback
    void* internal_handle;  // Opaque handle for MiniAV_ReleaseBuffer
} MiniAVBuffer;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_BUFFER_H