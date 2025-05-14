#include "miniav_utils.h"
#include "miniav_logging.h"
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

void *miniav_malloc(size_t size) { return malloc(size); }

void *miniav_calloc(size_t count, size_t size) { return calloc(count, size); }

void *miniav_realloc(void *ptr, size_t size) { return realloc(ptr, size); }

void miniav_free(void *ptr) {
  if (!ptr) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "miniav_free: NULL pointer detected.");
    return;
  }

  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "miniav_free: Freeing pointer: %p", ptr);
  free(ptr);
  ptr = NULL; // Mark as freed
}

char *miniav_strdup(const char *src) {
  if (!src)
    return NULL;
  size_t len = strlen(src) + 1;
  char *dst = (char *)malloc(len);
  if (dst)
    memcpy(dst, src, len);
  return dst;
}

int miniav_stricmp(const char *a, const char *b) {
  if (!a || !b)
    return (a == b) ? 0 : (a ? 1 : -1);
  while (*a && *b) {
    int ca = tolower((unsigned char)*a);
    int cb = tolower((unsigned char)*b);
    if (ca != cb)
      return ca - cb;
    ++a;
    ++b;
  }
  return (unsigned char)*a - (unsigned char)*b;
}

size_t miniav_strlcpy(char *dst, const char *src, size_t dst_size) {
  size_t src_len = strlen(src);
  if (dst_size) {
    size_t copy_len = (src_len >= dst_size) ? dst_size - 1 : src_len;
    memcpy(dst, src, copy_len);
    dst[copy_len] = '\0';
  }
  return src_len;
}