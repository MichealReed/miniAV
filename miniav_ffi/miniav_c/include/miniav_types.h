#ifndef MINIAV_TYPES_H
#define MINIAV_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Result Codes ---
typedef enum : uint32_t {
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
typedef struct {
    char device_id[256]; // Platform-specific unique identifier
    char name[256];      // Human-readable name (UTF-8)
    // Optionally: char model[128]; char manufacturer[128];
} MiniAVDeviceInfo;

// --- Opaque Handles ---
typedef struct MiniAVCameraContext* MiniAVCameraContextHandle;
typedef struct MiniAVScreenContext* MiniAVScreenContextHandle;
typedef struct MiniAVAudioContext* MiniAVAudioContextHandle;

// --- Logging ---
typedef enum : uint32_t {
    MINIAV_LOG_LEVEL_DEBUG = 0,
    MINIAV_LOG_LEVEL_INFO,
    MINIAV_LOG_LEVEL_WARN,
    MINIAV_LOG_LEVEL_ERROR
} MiniAVLogLevel;

typedef void (*MiniAVLogCallback)(MiniAVLogLevel level, const char* message, void* user_data);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_TYPES_H