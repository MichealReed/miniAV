#ifndef SCREEN_CONTEXT_MACOS_CG_H
#define SCREEN_CONTEXT_MACOS_CG_H

#include "../screen_context.h"
#include "../../../include/miniav_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// Platform-specific initialization function
MiniAVResultCode miniav_screen_context_platform_init_macos_cg(MiniAVScreenContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // SCREEN_CONTEXT_MACOS_CG_H