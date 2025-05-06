#include "miniav_context_base.h"
#include <stdlib.h>
#include <string.h>

// Base context struct for all MiniAV contexts (camera, screen, audio)
struct MiniAVContextBase {
    int initialized;
    void* user_data;
};

MiniAVContextBase* miniav_context_base_create(void* user_data) {
    MiniAVContextBase* ctx = (MiniAVContextBase*)calloc(1, sizeof(MiniAVContextBase));
    if (ctx) {
        ctx->initialized = 1;
        ctx->user_data = user_data;
    }
    return ctx;
}

void miniav_context_base_destroy(MiniAVContextBase* ctx) {
    if (ctx) {
        // Clean up any additional resources here
        free(ctx);
    }
}

int miniav_context_base_is_initialized(const MiniAVContextBase* ctx) {
    return ctx && ctx->initialized;
}

void* miniav_context_base_get_user_data(const MiniAVContextBase* ctx) {
    return ctx ? ctx->user_data : NULL;
}