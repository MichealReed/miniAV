// miniav_logging.h
#ifndef MINIAV_LOGGING_H
#define MINIAV_LOGGING_H

#include "miniav_types.h"
#include <stdarg.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void miniav_log(MiniAVLogLevel level, const char* fmt, ...);
void miniav_set_log_callback(MiniAVLogCallback callback, void* user_data);
void miniav_set_log_level(MiniAVLogLevel level);

// Dart native-port log delivery. See MiniAV_InitDartApi / MiniAV_SetLogPort
// in miniav_capture.h — a port survives the isolate that registered it,
// a MiniAVLogCallback function pointer does not.
intptr_t miniav_init_dart_api(void* initialize_api_dl_data);
void miniav_set_log_port(int64_t port);

#ifdef __cplusplus
}
#endif

#endif // MINIAV_LOGGING_H