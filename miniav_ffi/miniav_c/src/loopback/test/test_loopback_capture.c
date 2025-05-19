#include <inttypes.h> // For PRIu64
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Only include the main public header for MiniAV
#include "../../../include/miniav.h"

#ifdef _WIN32
#include <conio.h>   // For _kbhit, _getch
#include <windows.h> // For Sleep
#else
#include <unistd.h> // For usleep, sleep
#endif

static volatile int g_stop_requested = 0;
static volatile int g_loopback_buffer_count = 0;
const int DEFAULT_CAPTURE_DURATION_SECONDS = 10;

// Test application's own sleep function
void test_app_sleep_ms(int milliseconds) {
#ifdef _WIN32
  Sleep(milliseconds);
#else
  usleep(milliseconds * 1000);
#endif
}

// Test application's log callback
void test_app_log_callback(MiniAVLogLevel level, const char *message,
                           void *user_data) {
  (void)user_data; // Unused
  const char *level_str = "UNKNOWN";
  switch (level) {
  case MINIAV_LOG_LEVEL_DEBUG:
    level_str = "DEBUG";
    break;
  case MINIAV_LOG_LEVEL_INFO:
    level_str = "INFO";
    break;
  case MINIAV_LOG_LEVEL_WARN:
    level_str = "WARN";
    break;
  case MINIAV_LOG_LEVEL_ERROR:
    level_str = "ERROR";
    break;
  }
  fprintf(stderr, "[MiniAV Loopback Test - %s] %s\n", level_str, message);
}

// Audio Buffer Callback
void loopback_audio_buffer_callback(const MiniAVBuffer *buffer,
                                    void *user_data) {
  (void)user_data;

  if (g_stop_requested) {
    return;
  }

  if (!buffer) {
    fprintf(stderr, "LoopbackTestCallback: Received NULL buffer!\n");
    return;
  }

  if (buffer->type == MINIAV_BUFFER_TYPE_AUDIO) {
    g_loopback_buffer_count++;
    size_t data_size = buffer->data_size_bytes;
    const MiniAVAudioInfo *buffer_format_info = &buffer->data.audio.info;

    printf("LoopbackTestCallback: Audio buffer #%d received: %zu bytes, "
           "Timestamp: %" PRIu64 " us, "
           "Frames: %u, Format: %d, Channels: %u, Rate: %u\n",
           g_loopback_buffer_count, data_size, buffer->timestamp_us,
           buffer_format_info->num_frames, buffer_format_info->format,
           buffer_format_info->channels, buffer_format_info->sample_rate);

  } else {
    fprintf(stderr,
            "LoopbackTestCallback: Received non-audio buffer type: %d\n",
            buffer->type);
  }

  // If the buffer has an internal_handle, it implies the library expects the
  // user to release it. This pattern is seen in the screen capture test. Adapt
  // if your loopback API has a different buffer lifecycle. If loopback audio
  // buffers are e.g. pointers to an internal ring buffer and not individually
  // allocated for the user, then this release call would not be needed or
  // appropriate.
  if (buffer->internal_handle) {
    MiniAV_ReleaseBuffer(buffer->internal_handle);
  }
}

void print_usage() {
  printf("Usage: test_loopback_capture [target_index] [duration_seconds]\n");
  printf("  target_index (optional): Index of the loopback target to use (from "
         "enumerated list).\n");
  printf("                           If not provided, an interactive prompt or "
         "default selection will occur.\n");
  printf("  duration_seconds (optional): How long to capture in seconds. "
         "Default %d.\n",
         DEFAULT_CAPTURE_DURATION_SECONDS);
  printf("                           If 0, captures until Enter is pressed.\n");
}

int main(int argc, char *argv[]) {
  MiniAVResultCode res;
  uint32_t major, minor, patch;
  int user_cli_target_idx =
      -2; // -2 indicates no CLI input, -1 would mean default from CLI
  int capture_duration_seconds = DEFAULT_CAPTURE_DURATION_SECONDS;

  MiniAV_GetVersion(&major, &minor, &patch);
  printf("MiniAV Version: %u.%u.%u (String: %s)\n", major, minor, patch,
         MiniAV_GetVersionString());

  MiniAV_SetLogCallback(test_app_log_callback, NULL);
  MiniAV_SetLogLevel(MINIAV_LOG_LEVEL_DEBUG);

  if (argc > 1) {
    if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
      print_usage();
      return 0;
    }
    user_cli_target_idx = atoi(argv[1]);
  }
  if (argc > 2) {
    capture_duration_seconds = atoi(argv[2]);
  }

  MiniAVLoopbackContextHandle loopback_ctx = NULL;
  MiniAVDeviceInfo *targets = NULL;
  uint32_t target_count = 0;
  const char *selected_target_id = NULL;
  char user_input_buffer[16];

  printf("\nEnumerating loopback targets...\n");
  res = MiniAV_Loopback_EnumerateTargets(MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO,
                                         &targets, &target_count);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to enumerate loopback targets: %s\n",
            MiniAV_GetErrorString(res));
    return 1;
  }

  if (target_count == 0) {
    printf("No loopback targets found. Will attempt system default.\n");
    selected_target_id = NULL;
  } else {
    printf("Found %u loopback target(s):\n", target_count);
    for (uint32_t i = 0; i < target_count; ++i) {
      printf("  [%u] ID: %s, Name: %s, Default: %s\n", i, targets[i].device_id,
             targets[i].name, targets[i].is_default ? "Yes" : "No");
    }

    int final_selected_idx = -1;
    if (user_cli_target_idx > -2) { // User provided a target index via CLI
      if (user_cli_target_idx >= 0 &&
          (uint32_t)user_cli_target_idx < target_count) {
        final_selected_idx = user_cli_target_idx;
        printf("\nUsing target index %d from command line: %s\n",
               final_selected_idx, targets[final_selected_idx].name);
      } else {
        fprintf(stderr,
                "\nInvalid target index %d from command line. Will attempt "
                "system default.\n",
                user_cli_target_idx);
        selected_target_id = NULL; // Fallback to system default
      }
    } else { // No CLI index, try interactive or auto-select
      if (target_count == 1) {
        final_selected_idx = 0;
        printf("\nAutomatically selecting the only available target [0]: %s\n",
               targets[final_selected_idx].name);
      } else if (target_count > 1) {
        printf("\nEnter the index of the loopback target to capture (0-%u, or "
               "'d' for system default): ",
               target_count - 1);
        if (fgets(user_input_buffer, sizeof(user_input_buffer), stdin)) {
          if (user_input_buffer[0] == 'd' || user_input_buffer[0] == 'D') {
            printf("\nUser selected system default target.\n");
            selected_target_id = NULL;
          } else if (sscanf(user_input_buffer, "%d", &final_selected_idx) ==
                         1 &&
                     final_selected_idx >= 0 &&
                     (uint32_t)final_selected_idx < target_count) {
            printf("\nUser selected target [%d]: %s\n", final_selected_idx,
                   targets[final_selected_idx].name);
          } else {
            fprintf(
                stderr,
                "\nInvalid selection. Will attempt system default target.\n");
            selected_target_id = NULL;
          }
        } else {
          fprintf(stderr, "\nFailed to read selection. Will attempt system "
                          "default target.\n");
          selected_target_id = NULL;
        }
      }
    }
    if (final_selected_idx != -1) { // A valid index was determined either by
                                    // CLI, auto-selection, or interactive
      selected_target_id = targets[final_selected_idx].device_id;
    }
    // If selected_target_id is still NULL here, it means system default is
    // intended.
  }
  if (!selected_target_id && target_count > 0 &&
      user_cli_target_idx <=
          -2) { // Check if default was chosen explicitly or by lack of choice
    printf("\nAttempting system default loopback target.\n");
  } else if (!selected_target_id && target_count == 0) {
    printf("\nNo specific target available. Attempting system default loopback "
           "target.\n");
  }

  printf("\nCreating loopback context...\n");
  res = MiniAV_Loopback_CreateContext(&loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to create loopback context: %s\n",
            MiniAV_GetErrorString(res));
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count);
    return 1;
  }
  printf("Loopback context created.\n");

  MiniAVAudioInfo desired_format;
  memset(&desired_format, 0, sizeof(MiniAVAudioInfo));
  desired_format.format = MINIAV_AUDIO_FORMAT_F32;
  desired_format.channels = 2;
  desired_format.sample_rate = 48000;

  printf("\nConfiguring loopback capture for target_id: %s (NULL means system "
         "default)\n",
         selected_target_id ? selected_target_id : "SYSTEM_DEFAULT");
  printf("  Desired format - Channels: %u, Rate: %u, Format: %d\n",
         desired_format.channels, desired_format.sample_rate,
         desired_format.format);

  res = MiniAV_Loopback_Configure(loopback_ctx, selected_target_id,
                                  &desired_format);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to configure loopback context: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Loopback_DestroyContext(loopback_ctx);
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count);
    return 1;
  }

  MiniAVAudioInfo configured_video_format;
  res = MiniAV_Loopback_GetConfiguredFormat(loopback_ctx, &configured_video_format);
  if (res == MINIAV_SUCCESS) {
    printf("Loopback capture configured successfully.\n");
    printf("  Actual Configured Format - Channels: %u, Rate: %u, Format: %d\n",
           configured_video_format.channels, configured_video_format.sample_rate,
           configured_video_format.format);
  } else {
    fprintf(stderr, "Warning: Failed to get configured format: %s\n",
            MiniAV_GetErrorString(res));
  }

  printf("\nStarting loopback capture for %d seconds (or press Enter if "
         "duration is 0)...\n",
         capture_duration_seconds);
  g_loopback_buffer_count = 0;
  g_stop_requested = 0;
  res = MiniAV_Loopback_StartCapture(loopback_ctx,
                                     loopback_audio_buffer_callback, NULL);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to start loopback capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Loopback_DestroyContext(loopback_ctx);
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count);
    return 1;
  }
  printf("Loopback capture started. Waiting for audio buffers...\n");

  if (capture_duration_seconds > 0) {
    for (int i = 0; i < capture_duration_seconds; ++i) {
      printf("LoopbackTest main: Capturing... (%d/%d s), Buffers received so "
             "far: %d\n",
             i + 1, capture_duration_seconds, g_loopback_buffer_count);
      test_app_sleep_ms(1000);
#ifdef _WIN32
      if (_kbhit()) {
        if (_getch() == '\r') {
          printf("\nLoopbackTest main: Enter pressed, stopping capture.\n");
          g_stop_requested = 1;
          break;
        }
      }
#endif
      if (g_stop_requested)
        break;
    }
  } else {
    printf("LoopbackTest main: Capturing indefinitely. Press Enter to stop.\n");
    getchar(); // Wait for Enter key
    g_stop_requested = 1;
    printf("\nLoopbackTest main: Enter pressed, stopping capture.\n");
  }
  if (!g_stop_requested) { // If loop finished due to duration, not Enter key
    g_stop_requested = 1;  // Ensure callback stops processing
    printf("\nLoopbackTest main: Capture duration ended.\n");
  }

  printf("\nStopping loopback capture...\n");
  res = MiniAV_Loopback_StopCapture(loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to stop loopback capture: %s\n",
            MiniAV_GetErrorString(res));
  }
  printf("Loopback capture stopped. Total audio buffers received: %d\n",
         g_loopback_buffer_count);

  printf("\nDestroying loopback context...\n");
  res = MiniAV_Loopback_DestroyContext(loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to destroy loopback context: %s\n",
            MiniAV_GetErrorString(res));
  }
  printf("Loopback context destroyed.\n");

  if (targets) {
    MiniAV_FreeDeviceList(targets, target_count);
    targets = NULL;
  }
  printf("\nResources cleaned up.\n");
  printf("\nLoopback capture test finished.\n");
  return 0;
}