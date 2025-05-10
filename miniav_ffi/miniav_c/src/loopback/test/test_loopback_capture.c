#include "../../../include/miniav.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h> // For Sleep
#include <conio.h> // For _kbhit, _getch
#else
#include <unistd.h> // For usleep
// Basic non-blocking input for non-Windows might be more complex,
// using select/poll on stdin or termios. For simplicity, we'll use getchar or
// timed capture.
#endif

static FILE *g_output_file = NULL;
static uint64_t g_total_bytes_received = 0;
static volatile int g_stop_requested = 0;

// Test application's own sleep function
void test_app_sleep_ms(int milliseconds) {
#ifdef _WIN32
  Sleep(milliseconds);
#else
  usleep(milliseconds * 1000);
#endif
}

// Test application's log callback
void test_app_log_callback(MiniAVLogLevel level, const char *message, void *user_data) {
    (void)user_data; // Unused
    const char *level_str = "UNKNOWN";
    switch (level) {
    case MINIAV_LOG_LEVEL_DEBUG: level_str = "DEBUG"; break;
    case MINIAV_LOG_LEVEL_INFO:  level_str = "INFO";  break;
    case MINIAV_LOG_LEVEL_WARN:  level_str = "WARN";  break;
    case MINIAV_LOG_LEVEL_ERROR: level_str = "ERROR"; break;
    }
    // Print to stderr or stdout as preferred
    fprintf(stderr, "[TestApp MiniAV Log - %s] %s\n", level_str, message);
}


// Audio Buffer Callback
void loopback_audio_buffer_callback(MiniAVLoopbackContextHandle context_handle,
                                    const MiniAVBuffer *buffer,
                                    void *user_data) {
  (void)context_handle; // Replaced MINIAV_UNUSED
  (void)user_data;      // Replaced MINIAV_UNUSED

  if (g_stop_requested) {
    return;
  }

  if (!buffer) {
    // Use printf for test app's direct logging if not using MiniAV_Log
    printf("TestApp: Received NULL buffer in callback.\n");
    return;
  }

  if (buffer->type == MINIAV_BUFFER_TYPE_AUDIO) {
    // IMPORTANT: Replace DUMMYUNIONNAME_BUFFER_PAYLOAD and audio_buffer
    // with the actual names from your public miniav_buffer.h
    const void *audio_data = buffer->data.audio.data;
    size_t data_size = buffer->data_size_bytes; // Assuming size_bytes is the public field for total data size
    const MiniAVAudioInfo *format_info = &buffer->data.audio.info;

    printf("TestApp: Audio buffer received: %zu bytes, Timestamp: %llu us, "
           "Frames: %u, Format: %d, Channels: %u, Rate: %u\n",
           data_size, (unsigned long long)buffer->timestamp_us,
           format_info->num_frames, format_info->format, format_info->channels,
           format_info->sample_rate);

    if (g_output_file && audio_data && data_size > 0) {
      size_t written = fwrite(audio_data, 1, data_size, g_output_file);
      if (written != data_size) {
        printf("TestApp: Error writing to output file.\n");
      }
      g_total_bytes_received += written;
    }
  } else {
    printf("TestApp: Received non-audio buffer type: %d\n", buffer->type);
  }
}

void print_usage() {
  printf("Usage: test_loopback_capture [target_index] [duration_seconds]\n");
  printf("  target_index (optional): Index of the loopback target to use (from "
         "enumerated list).\n");
  printf("                           If not provided or invalid, system "
         "default will be attempted.\n");
  printf("  duration_seconds (optional): How long to capture in seconds. "
         "Default 10.\n");
  printf("                           If 0, captures until Enter is pressed.\n");
}

int main(int argc, char *argv[]) {
  MiniAVResultCode res;
  MiniAVLoopbackContextHandle loopback_ctx = NULL;
  MiniAVDeviceInfo *targets = NULL;
  uint32_t target_count = 0;
  const char *selected_target_id = NULL; // NULL for system default
  int selected_target_idx = -1;
  int capture_duration_seconds = 10; // Default capture duration

  // Set the public log callback for the MiniAV library
  MiniAV_SetLogCallback(test_app_log_callback, NULL);
  // Optionally, set the library's internal log level if exposed, e.g., MiniAV_SetLogLevel(MINIAV_LOG_LEVEL_DEBUG);
  // If MiniAV_SetLogLevel is not public, the library's verbosity is controlled by its compile-time settings
  // or a default. For test app messages, we'll use printf directly.

  printf("TestApp: MiniAV Loopback Capture Test Started.\n");

  if (argc > 1) {
    if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
      print_usage();
      return 0;
    }
    selected_target_idx = atoi(argv[1]);
  }
  if (argc > 2) {
    capture_duration_seconds = atoi(argv[2]);
  }

  // 1. Enumerate Loopback Targets
  printf("TestApp: Enumerating loopback targets...\n");
  res = MiniAV_Loopback_EnumerateTargets(MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO,
                                         &targets, &target_count);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to enumerate loopback targets: %d\n", res);
  } else {
    printf("TestApp: Found %u loopback target(s):\n", target_count);
    for (uint32_t i = 0; i < target_count; ++i) {
      printf("  [%u] ID: %s, Name: %s\n", i, targets[i].device_id,
             targets[i].name);
    }

    if (selected_target_idx >= 0 &&
        (uint32_t)selected_target_idx < target_count) {
      selected_target_id = targets[selected_target_idx].device_id;
      printf("TestApp: User selected target [%d]: %s\n", selected_target_idx,
                 selected_target_id);
    } else if (target_count > 0 && selected_target_idx != -1) {
      printf("TestApp: Invalid target index %d. Will attempt system default.\n",
          selected_target_idx);
    } else if (target_count == 0) {
      printf("TestApp: No specific loopback targets enumerated. Will attempt system default.\n");
    }
  }
  if (!selected_target_id && selected_target_idx == -1) {
    printf("TestApp: No specific target selected. Attempting system default loopback.\n");
  }

  // 2. Create Loopback Context
  printf("TestApp: Creating loopback context...\n");
  res = MiniAV_Loopback_CreateContext(&loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to create loopback context: %d\n", res);
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count); // Assuming MiniAV_FreeDeviceList is public
    return 1;
  }

  // 3. Configure Loopback Context
  // Use MiniAVAudioInfo as per the public API
  MiniAVAudioInfo desired_format;
  memset(&desired_format, 0, sizeof(MiniAVAudioInfo)); // Good practice to zero-initialize
  desired_format.format = MINIAV_AUDIO_FORMAT_S16; // Signed 16-bit PCM
  desired_format.channels = 2;                     // Stereo
  desired_format.sample_rate = 48000;              // 48 kHz
  // num_frames is typically an output for configured format or buffer, not input for desired format.

  printf("TestApp: Configuring loopback context for target_id: %s (NULL means system default)\n",
             selected_target_id ? selected_target_id : "SYSTEM_DEFAULT");
  printf("TestApp: Desired format - Channels: %u, Rate: %u, Format: %d\n",
             desired_format.channels, desired_format.sample_rate,
             desired_format.format);

  res = MiniAV_Loopback_Configure(loopback_ctx, selected_target_id,
                                  &desired_format);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to configure loopback context: %d\n", res);
    MiniAV_Loopback_DestroyContext(loopback_ctx);
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count);
    return 1;
  }

  MiniAVAudioInfo configured_format;
  res = MiniAV_Loopback_GetConfiguredFormat(loopback_ctx, &configured_format);
  if (res == MINIAV_SUCCESS) {
    printf("TestApp: Actually configured format - Channels: %u, Rate: %u, Format: %d\n",
               configured_format.channels, configured_format.sample_rate,
               configured_format.format);
  } else {
    printf("TestApp: Failed to get configured format: %d\n", res);
  }

  // 4. Open Output File
  const char *output_filename = "loopback_capture.raw";
  g_output_file = fopen(output_filename, "wb");
  if (!g_output_file) {
    printf("TestApp: Failed to open output file: %s\n", output_filename);
  } else {
    printf("TestApp: Opened output file: %s\n", output_filename);
  }

  // 5. Start Capture
  printf("TestApp: Starting loopback capture...\n");
  res = MiniAV_Loopback_StartCapture(loopback_ctx,
                                     loopback_audio_buffer_callback, NULL);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to start loopback capture: %d\n", res);
    if (g_output_file)
      fclose(g_output_file);
    MiniAV_Loopback_DestroyContext(loopback_ctx);
    if (targets)
      MiniAV_FreeDeviceList(targets, target_count);
    return 1;
  }

  // 6. Capture Loop
  if (capture_duration_seconds > 0) {
    printf("TestApp: Capturing for %d seconds...\n", capture_duration_seconds);
    for (int i = 0; i < capture_duration_seconds; ++i) {
      test_app_sleep_ms(1000); // Sleep for 1 second
#ifdef _WIN32
      if (_kbhit()) {
        if (_getch() == '\r') {
          printf("TestApp: Enter pressed, stopping capture.\n");
          g_stop_requested = 1;
          break;
        }
      }
#endif
      if (g_stop_requested)
        break;
    }
  } else {
    printf("TestApp: Capturing indefinitely. Press Enter to stop.\n");
    getchar(); // Wait for Enter key
    g_stop_requested = 1;
  }
  printf("TestApp: Stopping capture as requested or duration ended.\n");

  // 7. Stop Capture
  printf("TestApp: Stopping loopback capture...\n");
  res = MiniAV_Loopback_StopCapture(loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to stop loopback capture cleanly: %d\n", res);
  }

  // 8. Close Output File
  if (g_output_file) {
    fclose(g_output_file);
    g_output_file = NULL;
    printf("TestApp: Closed output file. Total bytes received: %llu\n",
               (unsigned long long)g_total_bytes_received);
  }

  // 9. Destroy Context
  printf("TestApp: Destroying loopback context...\n");
  res = MiniAV_Loopback_DestroyContext(loopback_ctx);
  if (res != MINIAV_SUCCESS) {
    printf("TestApp: Failed to destroy loopback context cleanly: %d\n", res);
  }

  // 10. Free Enumerated Devices
  if (targets) {
    MiniAV_FreeDeviceList(targets, target_count); // Assuming this is public
    targets = NULL;
  }

  printf("TestApp: MiniAV Loopback Capture Test Finished.\n");
  return 0;
}