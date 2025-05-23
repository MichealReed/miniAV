#ifndef LOOPBACK_CONTEXT_MACOS_COREAUDIO_H
#define LOOPBACK_CONTEXT_MACOS_COREAUDIO_H

#include "../loopback_context.h"
#include "../../../include/miniav_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// Platform-specific initialization function
MiniAVResultCode miniav_loopback_context_platform_init_macos_coreaudio(MiniAVLoopbackContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // LOOPBACK_CONTEXT_MACOS_COREAUDIO_H