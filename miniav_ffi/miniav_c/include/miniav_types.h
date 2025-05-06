#ifndef MINIAV_TYPES_H
#define MINIAV_TYPES_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Result Codes ---
typedef enum {
  MINIAV_SUCCESS = 0,
  MINIAV_ERROR_UNKNOWN = -1,
  MINIAV_ERROR_INVALID_ARG = -2,
  MINIAV_ERROR_NOT_INITIALIZED = -3,
  MINIAV_ERROR_SYSTEM_CALL_FAILED = -4,
  MINIAV_ERROR_NOT_SUPPORTED = -5,
  MINIAV_ERROR_BUFFER_TOO_SMALL = -6,
  MINIAV_ERROR_INVALID_HANDLE = -7,
  MINIAV_ERROR_DEVICE_NOT_FOUND = -8,
  MINIAV_ERROR_DEVICE_BUSY = -9,
  MINIAV_ERROR_ALREADY_RUNNING = -10,
  MINIAV_ERROR_NOT_RUNNING = -11,
  MINIAV_ERROR_OUT_OF_MEMORY = -12,
  MINIAV_ERROR_TIMEOUT = -13
} MiniAVResultCode;

// --- Device Info ---
#define MINIAV_DEVICE_ID_MAX_LEN 256
#define MINIAV_DEVICE_NAME_MAX_LEN 256

typedef struct {
  char device_id[MINIAV_DEVICE_ID_MAX_LEN]; // Platform-specific unique identifier
  char name[MINIAV_DEVICE_NAME_MAX_LEN];      // Human-readable name (UTF-8)
  bool is_default;     // True if this is the default device
} MiniAVDeviceInfo;


// --- Pixel Formats (Moved Here) ---
typedef enum {
  MINIAV_PIXEL_FORMAT_UNKNOWN = 0,
  MINIAV_PIXEL_FORMAT_I420,   // Planar YUV 4:2:0
  MINIAV_PIXEL_FORMAT_NV12,   // Semi-Planar YUV 4:2:0
  MINIAV_PIXEL_FORMAT_NV21,   // Semi-Planar YUV 4:2:0
  MINIAV_PIXEL_FORMAT_YUY2,   // Packed YUV 4:2:2
  MINIAV_PIXEL_FORMAT_UYVY,   // Packed YUV 4:2:2
  MINIAV_PIXEL_FORMAT_RGB24,  // Packed RGB
  MINIAV_PIXEL_FORMAT_BGR24,  // Packed BGR
  MINIAV_PIXEL_FORMAT_RGBA32, // Packed RGBA
  MINIAV_PIXEL_FORMAT_BGRA32, // Packed BGRA
  MINIAV_PIXEL_FORMAT_ARGB32, // Packed ARGB
  MINIAV_PIXEL_FORMAT_ABGR32, // Packed ABGR
  MINIAV_PIXEL_FORMAT_MJPEG   // Motion JPEG (compressed)
} MiniAVPixelFormat;

// --- Audio Formats (Moved Here) ---
typedef enum {
  MINIAV_AUDIO_FORMAT_UNKNOWN = 0,
  MINIAV_AUDIO_FORMAT_U8,  // Unsigned 8-bit integer
  MINIAV_AUDIO_FORMAT_S16, // Signed 16-bit integer
  MINIAV_AUDIO_FORMAT_S32, // Signed 32-bit integer
  MINIAV_AUDIO_FORMAT_F32  // 32-bit floating point
} MiniAVAudioFormat;


// -- Format Info Structs (Now after enums) ---
typedef struct {
  MiniAVPixelFormat pixel_format;
  uint32_t width;
  uint32_t height;
  uint32_t frame_rate_numerator; // Optional: For specifying desired frame rate
  uint32_t frame_rate_denominator; // Optional: For specifying desired frame rate
} MiniAVVideoFormatInfo;

typedef struct {
  MiniAVAudioFormat sample_format;
  uint32_t sample_rate;
  uint8_t channels;
} MiniAVAudioFormatInfo;


// --- Opaque Handles ---
typedef struct MiniAVCameraContext *MiniAVCameraContextHandle;
typedef struct MiniAVScreenContext *MiniAVScreenContextHandle;
typedef struct MiniAVAudioContext *MiniAVAudioContextHandle;

// --- Logging ---
typedef enum {
  MINIAV_LOG_LEVEL_DEBUG = 0,
  MINIAV_LOG_LEVEL_INFO,
  MINIAV_LOG_LEVEL_WARN,
  MINIAV_LOG_LEVEL_ERROR
} MiniAVLogLevel;

typedef void (*MiniAVLogCallback)(MiniAVLogLevel level, const char *message,
                                  void *user_data);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_TYPES_H