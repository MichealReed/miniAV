#ifndef INPUT_CONTEXT_H
#define INPUT_CONTEXT_H

#include "../../include/miniav_types.h"
#include "../../include/miniav_capture.h"
#include "../common/miniav_context_base.h"

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration of the main context structure
typedef struct MiniAVInputContext MiniAVInputContext;

// Defines the operations for a platform-specific input implementation
typedef struct InputContextInternalOps {
    MiniAVResultCode (*init_platform)(MiniAVInputContext *ctx);
    MiniAVResultCode (*destroy_platform)(MiniAVInputContext *ctx);
    MiniAVResultCode (*enumerate_gamepads)(MiniAVDeviceInfo **devices_out, uint32_t *count_out);
    MiniAVResultCode (*configure)(MiniAVInputContext *ctx, const MiniAVInputConfig *config);
    MiniAVResultCode (*start_capture)(MiniAVInputContext *ctx);
    MiniAVResultCode (*stop_capture)(MiniAVInputContext *ctx);
} InputContextInternalOps;

// --- Input Backend Entry Structure ---
typedef struct MiniAVInputBackend {
    const char *name;
    const InputContextInternalOps *ops;
    MiniAVResultCode (*platform_init_for_selection)(MiniAVInputContext *ctx);
} MiniAVInputBackend;

// Main input context structure
struct MiniAVInputContext {
    MiniAVContextBase *base;
    const InputContextInternalOps *ops;
    void *platform_ctx;

    MiniAVInputConfig config;

    int is_configured;
    int is_running;
};

// Platform-specific initialization functions
#if defined(_WIN32)
#include "windows/input_context_win_rawinput.h"
extern MiniAVResultCode miniav_input_context_platform_init_windows(MiniAVInputContext *ctx);
extern const InputContextInternalOps g_input_ops_win;
#elif defined(__linux__)
// Future: Linux libinput backend
#elif defined(__APPLE__)
// Future: macOS IOKit/CGEventTap backend
#endif

#ifdef __cplusplus
}
#endif

#endif // INPUT_CONTEXT_H
