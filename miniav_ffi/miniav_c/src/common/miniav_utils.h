#ifndef MINIAV_UTILS_H
#define MINIAV_UTILS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void* miniav_malloc(size_t size);
void* miniav_calloc(size_t count, size_t size);
void* miniav_realloc(void* ptr, size_t size);
void  miniav_free(void* ptr);

char* miniav_strdup(const char* src);
int   miniav_stricmp(const char* a, const char* b);

size_t miniav_strlcpy(char* dst, const char* src, size_t dst_size);

#ifndef MINIAV_UNUSED
#define MINIAV_UNUSED(x) (void)(x)
#endif

#ifdef __cplusplus
}
#endif

#endif // MINIAV_UTILS_H