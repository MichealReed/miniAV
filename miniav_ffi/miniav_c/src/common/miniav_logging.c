// miniav_logging.c
#include "miniav_logging.h"
// #include "miniav_time.h" // No longer needed for self-cleanup delay

#include <stdarg.h>
#include <stdio.h>  // For fprintf, stderr, vsnprintf
#include <stdlib.h> // Not strictly needed if not allocating for callback
#include <string.h> // Not strictly needed if not allocating for callback

// g_log_callback and g_log_user_data are no longer used for C-side printing.
// They can be kept if you might re-introduce a Dart callback later, or removed.
static MiniAVLogCallback g_log_callback = NULL;
static void *g_log_user_data = NULL;
static MiniAVLogLevel g_log_level = MINIAV_LOG_LEVEL_INFO; // Default log level

// Helper to get string representation of log level
static const char* get_log_level_string(MiniAVLogLevel level) {
    switch (level) {
        case MINIAV_LOG_LEVEL_DEBUG: return "DEBUG";
        case MINIAV_LOG_LEVEL_INFO:  return "INFO";
        case MINIAV_LOG_LEVEL_WARN:  return "WARN";
        case MINIAV_LOG_LEVEL_ERROR: return "ERROR";
        default: return "UNKNOWN";
    }
}

void miniav_log(MiniAVLogLevel level, const char *fmt, ...) {
  // Check if the message's level is sufficient to be logged
  // Assuming g_log_level is the minimum level to log.
  // For example, if g_log_level is INFO, then INFO, WARN, ERROR, FATAL will be logged.
  // If g_log_level is DEBUG, then DEBUG, INFO, WARN, ERROR, FATAL will be logged.
  if (level < g_log_level) { // Adjust this condition based on your enum's ordering and desired behavior
    return;                  // Example: if higher enum value means higher severity
  }
  // If lower enum value means higher severity (e.g. TRACE=0, FATAL=5)
  // and g_log_level is the minimum severity to show:
  // if (level < g_log_level) return; // This is typical if 0 is most verbose

  char temp_buffer[1024]; // Temporary buffer for formatting
  va_list args;

  va_start(args, fmt);
  vsnprintf(temp_buffer, sizeof(temp_buffer), fmt, args);
  va_end(args);

  temp_buffer[sizeof(temp_buffer) - 1] = '\0'; // Ensure null termination

  // Print to stderr, prepending the log level
  // You might want to add timestamps or other context here as well.
  fprintf(stderr, "[MiniAV C - %s]: %s\n", get_log_level_string(level), temp_buffer);
  fflush(stderr); // Ensure it's flushed, especially important for debugging crashes
}

// This function now only affects C-side printing if miniav_log checks g_log_level.
void miniav_set_log_level(MiniAVLogLevel level) {
  g_log_level = level;
  // Optional: Log that the log level has changed, using the new level's rule
  // miniav_log(MINIAV_LOG_LEVEL_INFO, "Log level set to %s", get_log_level_string(level));
}

// This function becomes mostly a no-op for C-side printing,
// but Dart might still call it.
void miniav_set_log_callback(MiniAVLogCallback callback, void *user_data) {
  g_log_callback = callback; // Store it, but miniav_log won't use it directly
  g_log_user_data = user_data;
  // miniav_log(MINIAV_LOG_LEVEL_DEBUG, "C: Log callback function pointer %s.", callback ? "set" : "cleared");
}
