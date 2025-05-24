#ifndef MINIAV_TYPES_H
#define MINIAV_TYPES_H

#include <stdbool.h>
#include <stdint.h>

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
  MINIAV_ERROR_TIMEOUT = -13,
  MINIAV_ERROR_DEVICE_LOST = -14,
  MINIAV_ERROR_FORMAT_NOT_SUPPORTED = -15,
  MINIAV_ERROR_INVALID_OPERATION = -16,
  MINIAV_ERROR_NOT_IMPLEMENTED = -17,
  MINIAV_ERROR_NOT_CONFIGURED = -18,
  MINIAV_ERROR_PORTAL_FAILED = -19,
  MINIAV_ERROR_STREAM_FAILED = -20,
  MINIAV_ERROR_PORTAL_CLOSED = -21,
  MINIAV_ERROR_USER_CANCELLED = -22,
} MiniAVResultCode;

// --- Device Info ---
#define MINIAV_DEVICE_ID_MAX_LEN 256
#define MINIAV_DEVICE_NAME_MAX_LEN 256
#define MINIAV_VIDEO_FORMAT_MAX_PLANES 4

typedef struct {
  char device_id[MINIAV_DEVICE_ID_MAX_LEN]; // Platform-specific unique
                                            // identifier
  char name[MINIAV_DEVICE_NAME_MAX_LEN];    // Human-readable name (UTF-8)
  bool is_default; // True if this is the default device
} MiniAVDeviceInfo;

// --- Pixel Formats
typedef enum {
    MINIAV_PIXEL_FORMAT_UNKNOWN = 0,
    
    // --- Standard RGB Formats (8-bit) ---
    MINIAV_PIXEL_FORMAT_RGB24,          // 24-bit RGB (no alpha)
    MINIAV_PIXEL_FORMAT_BGR24,          // 24-bit BGR (no alpha)
    MINIAV_PIXEL_FORMAT_RGBA32,         // 32-bit RGBA (alpha in MSB)
    MINIAV_PIXEL_FORMAT_BGRA32,         // 32-bit BGRA (alpha in MSB)
    MINIAV_PIXEL_FORMAT_ARGB32,         // 32-bit ARGB (alpha in LSB)
    MINIAV_PIXEL_FORMAT_ABGR32,         // 32-bit ABGR (alpha in LSB)
    MINIAV_PIXEL_FORMAT_RGBX32,         // 32-bit RGB with padding (X = unused)
    MINIAV_PIXEL_FORMAT_BGRX32,         // 32-bit BGR with padding (X = unused)
    MINIAV_PIXEL_FORMAT_XRGB32,         // 32-bit RGB with leading padding
    MINIAV_PIXEL_FORMAT_XBGR32,         // 32-bit BGR with leading padding
    
    // --- Standard YUV Formats (8-bit) ---
    MINIAV_PIXEL_FORMAT_I420,           // Planar YUV 4:2:0 (YYYY... UU... VV...)
    MINIAV_PIXEL_FORMAT_YV12,           // Planar YUV 4:2:0 (YYYY... VV... UU...)
    MINIAV_PIXEL_FORMAT_NV12,           // Semi-planar YUV 4:2:0 (YYYY... UVUV...)
    MINIAV_PIXEL_FORMAT_NV21,           // Semi-planar YUV 4:2:0 (YYYY... VUVU...)
    MINIAV_PIXEL_FORMAT_YUY2,           // Packed YUV 4:2:2 (YUYV YUYV...)
    MINIAV_PIXEL_FORMAT_UYVY,           // Packed YUV 4:2:2 (UYVY UYVY...)
    
    // --- High-End RGB Formats ---
    MINIAV_PIXEL_FORMAT_RGB30,          // 30-bit RGB (10-bit per channel)
    MINIAV_PIXEL_FORMAT_RGB48,          // 48-bit RGB (16-bit per channel)
    MINIAV_PIXEL_FORMAT_RGBA64,         // 64-bit RGBA (16-bit per channel)
    MINIAV_PIXEL_FORMAT_RGBA64_HALF,    // 64-bit RGBA half-precision float
    MINIAV_PIXEL_FORMAT_RGBA128_FLOAT,  // 128-bit RGBA IEEE float
    
    // --- High-End YUV Formats ---
    MINIAV_PIXEL_FORMAT_YUV420_10BIT,   // 10-bit YUV 4:2:0
    MINIAV_PIXEL_FORMAT_YUV422_10BIT,   // 10-bit YUV 4:2:2
    MINIAV_PIXEL_FORMAT_YUV444_10BIT,   // 10-bit YUV 4:4:4
    
    // --- Grayscale Formats ---
    MINIAV_PIXEL_FORMAT_GRAY8,          // 8-bit grayscale
    MINIAV_PIXEL_FORMAT_GRAY16,         // 16-bit grayscale
    
    // --- Raw/Bayer Formats ---
    MINIAV_PIXEL_FORMAT_BAYER_GRBG8,    // 8-bit Bayer GRBG
    MINIAV_PIXEL_FORMAT_BAYER_RGGB8,    // 8-bit Bayer RGGB
    MINIAV_PIXEL_FORMAT_BAYER_BGGR8,    // 8-bit Bayer BGGR
    MINIAV_PIXEL_FORMAT_BAYER_GBRG8,    // 8-bit Bayer GBRG
    MINIAV_PIXEL_FORMAT_BAYER_GRBG16,   // 16-bit Bayer GRBG
    MINIAV_PIXEL_FORMAT_BAYER_RGGB16,   // 16-bit Bayer RGGB
    MINIAV_PIXEL_FORMAT_BAYER_BGGR16,   // 16-bit Bayer BGGR
    MINIAV_PIXEL_FORMAT_BAYER_GBRG16,   // 16-bit Bayer GBRG
    
    MINIAV_PIXEL_FORMAT_COUNT
} MiniAVPixelFormat;

// --- Audio Formats (Moved Here) ---
typedef enum {
  MINIAV_AUDIO_FORMAT_UNKNOWN = 0,
  MINIAV_AUDIO_FORMAT_U8,  // Unsigned 8-bit integer
  MINIAV_AUDIO_FORMAT_S16, // Signed 16-bit integer
  MINIAV_AUDIO_FORMAT_S32, // Signed 32-bit integer
  MINIAV_AUDIO_FORMAT_F32  // 32-bit floating point
} MiniAVAudioFormat;

// --- Capture Target Type (for Screen Capture) ---
typedef enum {
  MINIAV_CAPTURE_TYPE_DISPLAY, // Capture an entire display/monitor
  MINIAV_CAPTURE_TYPE_WINDOW,  // Capture a specific window
  MINIAV_CAPTURE_TYPE_REGION // Capture a specific region of a display or window
} MiniAVCaptureType;

typedef enum {
  MINIAV_OUTPUT_PREFERENCE_CPU,
  MINIAV_OUTPUT_PREFERENCE_GPU
} MiniAVOutputPreference;

// -- Format Info Structs (Now after enums) ---
typedef struct {
  uint32_t width;
  uint32_t height;
  MiniAVPixelFormat pixel_format;
  uint32_t frame_rate_numerator;
  uint32_t frame_rate_denominator;
  MiniAVOutputPreference output_preference;
} MiniAVVideoInfo;

typedef struct {
  MiniAVAudioFormat format;
  uint32_t sample_rate;
  uint8_t channels;
  uint32_t num_frames;
} MiniAVAudioInfo;

typedef enum MiniAVLoopbackTargetType {
  MINIAV_LOOPBACK_TARGET_NONE,
  MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO,
  MINIAV_LOOPBACK_TARGET_PROCESS,
  MINIAV_LOOPBACK_TARGET_WINDOW
} MiniAVLoopbackTargetType;

typedef struct MiniAVLoopbackTargetInfo {
  MiniAVLoopbackTargetType type;
  union {
    uint32_t process_id;
    void *window_handle; // Platform-specific: HWND, NSWindow*, XID, etc.
    // char internal_target_id[256]; // Could be used if resolving from a
    // device_id
  } TARGETHANDLE;
} MiniAVLoopbackTargetInfo;

// --- Opaque Handles ---
typedef struct MiniAVCameraContext *MiniAVCameraContextHandle;
typedef struct MiniAVScreenContext *MiniAVScreenContextHandle;
typedef struct MiniAVAudioContext *MiniAVAudioContextHandle;
typedef struct MiniAVLoopbackContext *MiniAVLoopbackContextHandle;

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