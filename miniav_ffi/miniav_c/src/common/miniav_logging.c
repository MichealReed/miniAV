#include "miniav_logging.h"

#include <stdarg.h>
#include <stdio.h>  // For fprintf, stderr, vsnprintf
#include <stdlib.h> // Not strictly needed if not allocating for callback
#include <string.h> // Not strictly needed if not allocating for callback

static MiniAVLogCallback g_log_callback = NULL;
static void *g_log_user_data = NULL;
static MiniAVLogLevel g_log_level = MINIAV_LOG_LEVEL_INFO; // Default log level

// Helper to get string representation of log level
static const char* get_log_level_string(MiniAVLogLevel level) {
    switch (level) {
        case MINIAV_LOG_LEVEL_TRACE: return "TRACE";
        case MINIAV_LOG_LEVEL_DEBUG: return "DEBUG";
        case MINIAV_LOG_LEVEL_INFO:  return "INFO";
        case MINIAV_LOG_LEVEL_WARN:  return "WARN";
        case MINIAV_LOG_LEVEL_ERROR: return "ERROR";
        case MINIAV_LOG_LEVEL_NONE:  return "NONE"; // No logging
        default: return "UNKNOWN";
    }
}

void miniav_log(MiniAVLogLevel level, const char *fmt, ...) {
  // Check if the message's level is sufficient to be logged
  if (level < g_log_level) { // Adjust this condition based on your enum's ordering and desired behavior
    return;                  // Example: if higher enum value means higher severity
  }


  char temp_buffer[1024]; // Temporary buffer for formatting
  va_list args;

  va_start(args, fmt);
  vsnprintf(temp_buffer, sizeof(temp_buffer), fmt, args);
  va_end(args);

  temp_buffer[sizeof(temp_buffer) - 1] = '\0'; // Ensure null termination

  fprintf(stderr, "[MiniAV C - %s]: %s\n", get_log_level_string(level), temp_buffer);
  fflush(stderr); // Ensure it's flushed
}

void miniav_set_log_level(MiniAVLogLevel level) {
  g_log_level = level;
}

void miniav_set_log_callback(MiniAVLogCallback callback, void *user_data) {
  g_log_callback = callback; // Store it, but miniav_log won't use it directly
  g_log_user_data = user_data;
}
