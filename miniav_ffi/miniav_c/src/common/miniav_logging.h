// miniav_logging.h
#ifndef MINIAV_LOGGING_H
#define MINIAV_LOGGING_H

#include "miniav_types.h"
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

void miniav_log(MiniAVLogLevel level, const char* fmt, ...);
void miniav_set_log_callback(MiniAVLogCallback callback, void* user_data);
void miniav_set_log_level(MiniAVLogLevel level);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_LOGGING_H