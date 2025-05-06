#ifndef MINIAV_CONTEXT_BASE_H
#define MINIAV_CONTEXT_BASE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MiniAVContextBase MiniAVContextBase;

MiniAVContextBase *miniav_context_base_create(void *user_data);
void miniav_context_base_destroy(MiniAVContextBase *ctx);
int miniav_context_base_is_initialized(const MiniAVContextBase *ctx);
void *miniav_context_base_get_user_data(const MiniAVContextBase *ctx);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_CONTEXT_BASE_H