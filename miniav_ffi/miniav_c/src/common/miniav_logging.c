// miniav_logging.c
#include "miniav_logging.h"
#include <stdio.h>
#include <stdarg.h>

static MiniAVLogCallback g_log_callback = NULL;
static void* g_log_user_data = NULL;
static MiniAVLogLevel g_log_level = MINIAV_LOG_LEVEL_INFO;

void miniav_log(MiniAVLogLevel level, const char* fmt, ...) {
    if (g_log_callback && level >= g_log_level) {
        char buffer[512];
        va_list args;
        va_start(args, fmt);
        vsnprintf(buffer, sizeof(buffer), fmt, args);
        va_end(args);
        g_log_callback(level, buffer, g_log_user_data);
    }
}

void miniav_set_log_callback(MiniAVLogCallback callback, void* user_data) {
    g_log_callback = callback;
    g_log_user_data = user_data;
}

void miniav_set_log_level(MiniAVLogLevel level) {
    g_log_level = level;
}