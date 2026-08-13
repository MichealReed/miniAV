#include "miniav_logging.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>  // For fprintf, stderr, vsnprintf
#include <stdlib.h> // Not strictly needed if not allocating for callback
#include <string.h> // Not strictly needed if not allocating for callback

#ifdef MINIAV_HAVE_DART_DL
// Vendored Dart SDK dynamic-linking API (third_party/dart_dl).
#include "dart_api_dl.h"
#endif

static MiniAVLogCallback g_log_callback = NULL;
static void *g_log_user_data = NULL;
static MiniAVLogLevel g_log_level = MINIAV_LOG_LEVEL_INFO; // Default log level

// --- Dart native-port delivery ----------------------------------------------
//
// The log registry is PROCESS-GLOBAL. A Dart `NativeCallable` installed here
// belongs to exactly one isolate; once that isolate exits the VM deletes the
// trampoline while this library still holds the pointer, and the next
// miniav_log() from a capture/worker thread — or from inside a leaf FFI call
// such as MiniAV_ReleaseBuffer — aborts the entire process. Posting to a Dart
// port is defined, silent and thread-safe even when the port has closed, so
// the port is the supported Dart delivery path.
//
// The MiniAVLogCallback function-pointer API below is kept for non-Dart
// embedders, which own the lifetime of their own function.
#ifdef MINIAV_HAVE_DART_DL
static Dart_Port g_log_port = ILLEGAL_PORT;
static int g_dart_api_ready = 0;

// Posts {int32 level, Uint8List utf8Message}. Bytes rather than a C string
// because device names can carry non-UTF-8 (Latin-1) and
// Dart_CObject_kString demands valid UTF-8. Dart_PostCObject_DL COPIES the
// typed data, so nothing crosses ownership and Dart frees nothing.
static void miniav_post_log_to_port(Dart_Port port, MiniAVLogLevel level,
                                    const char *msg, size_t len) {
  Dart_CObject c_level;
  c_level.type = Dart_CObject_kInt32;
  c_level.value.as_int32 = (int32_t)level;

  Dart_CObject c_msg;
  c_msg.type = Dart_CObject_kTypedData;
  c_msg.value.as_typed_data.type = Dart_TypedData_kUint8;
  c_msg.value.as_typed_data.length = (intptr_t)len;
  c_msg.value.as_typed_data.values = (uint8_t *)msg;

  Dart_CObject *parts[2];
  parts[0] = &c_level;
  parts[1] = &c_msg;

  Dart_CObject payload;
  payload.type = Dart_CObject_kArray;
  payload.value.as_array.length = 2;
  payload.value.as_array.values = parts;

  // false simply means the port is gone (its isolate exited). That is the
  // entire reason this path exists — ignore it.
  (void)Dart_PostCObject_DL(port, &payload);
}
#endif // MINIAV_HAVE_DART_DL

intptr_t miniav_init_dart_api(void *initialize_api_dl_data) {
#ifdef MINIAV_HAVE_DART_DL
  intptr_t rc = Dart_InitializeApiDL(initialize_api_dl_data);
  if (rc == 0)
    g_dart_api_ready = 1;
  return rc;
#else
  (void)initialize_api_dl_data;
  return -1;
#endif
}

void miniav_set_log_port(int64_t port) {
#ifdef MINIAV_HAVE_DART_DL
  g_log_port = (Dart_Port)port;
#else
  (void)port;
#endif
}

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

#ifdef MINIAV_HAVE_DART_DL
  // Native port wins when registered: it is the only delivery path that
  // survives the registering isolate exiting.
  Dart_Port port = g_log_port;
  if (port != ILLEGAL_PORT && g_dart_api_ready) {
    miniav_post_log_to_port(port, level, temp_buffer, strlen(temp_buffer));
    return;
  }
#endif

  // Snapshot the callback pair so a concurrent re-registration can't tear the
  // (callback, user_data) association mid-call.
  MiniAVLogCallback cb = g_log_callback;
  void *cb_user_data = g_log_user_data;
  if (cb) {
    // An embedder-installed callback is the single delivery path: GUI hosts
    // (e.g. Flutter apps) have no visible stderr, which previously made every
    // native log line disappear in the field.
    //
    // OWNERSHIP: the message is a heap copy the RECEIVER frees with
    // MiniAV_Free once consumed. The callback may be dispatched
    // asynchronously onto another thread (the Dart FFI shim uses
    // NativeCallable.listener, which runs the handler on the event loop
    // after this call returns), so a stack/static buffer would be dangling
    // by the time it is read.
    size_t msg_len = strlen(temp_buffer) + 1;
    char *heap_msg = (char *)malloc(msg_len);
    if (heap_msg) {
      memcpy(heap_msg, temp_buffer, msg_len);
      cb(level, heap_msg, cb_user_data);
      return;
    }
    // OOM: fall through to stderr so the message isn't lost entirely.
  }
  fprintf(stderr, "[MiniAV C - %s]: %s\n", get_log_level_string(level), temp_buffer);
  fflush(stderr); // Ensure it's flushed
}

void miniav_set_log_level(MiniAVLogLevel level) {
  g_log_level = level;
}

void miniav_set_log_callback(MiniAVLogCallback callback, void *user_data) {
  // Best-effort ordering for the unsynchronized snapshot in miniav_log:
  // publish user_data before the callback that consumes it. This is NOT a
  // formal happens-before (no fences) — register the callback before starting
  // any capture, and treat re-registration during active capture as a benign
  // race that may pair one message with the previous user_data.
  g_log_user_data = user_data;
  g_log_callback = callback;
}
