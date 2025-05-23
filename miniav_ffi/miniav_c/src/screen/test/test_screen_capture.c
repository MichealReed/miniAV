#include "../../../include/miniav.h"
#include <inttypes.h> // For PRIu64
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h> // For sleep() and usleep()
#endif

volatile int g_video_frame_count = 0;
volatile int g_audio_packet_count = 0;
// SCREEN_CAPTURE_DURATION_SECONDS removed

// Simple logging callback for the test
void test_screen_log_callback(MiniAVLogLevel level, const char *message,
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
  fprintf(stderr, "[MiniAV Screen Test - %s] %s\n", level_str, message);
}

// Buffer callback to show real-time speed
void test_screen_buffer_callback(const MiniAVBuffer *buffer, void *user_data) {
  (void)user_data;
  static uint64_t last_video_timestamp_us = 0;
  static uint64_t last_audio_timestamp_us = 0;

  if (!buffer) {
    fprintf(stderr, "ScreenTestCallback: Received NULL buffer!\n");
    fflush(stderr);
    return;
  }

  if (buffer->type == MINIAV_BUFFER_TYPE_VIDEO) {
    g_video_frame_count++;
    double delta_ms = 0.0;
    if (last_video_timestamp_us != 0 && buffer->timestamp_us > last_video_timestamp_us) {
      delta_ms = (double)(buffer->timestamp_us - last_video_timestamp_us) / 1000.0;
      printf("Video: +%.3f ms (Frame #%d, %ux%u, TS: %" PRIu64 "us)\n",
             delta_ms, g_video_frame_count, buffer->data.video.info.width, buffer->data.video.info.height, buffer->timestamp_us);
    } else {
      printf("Video: First frame (Frame #%d, %ux%u, TS: %" PRIu64 "us)\n",
             g_video_frame_count, buffer->data.video.info.width, buffer->data.video.info.height, buffer->timestamp_us);
    }
    last_video_timestamp_us = buffer->timestamp_us;

    if (buffer->content_type == MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE) {
      printf("  GPU Buffer: Shared Handle = %p\n", buffer->data.video.planes[0].data_ptr);
    }

    if (buffer->internal_handle) {
      MiniAV_ReleaseBuffer(buffer->internal_handle);
    } else {
      fprintf(stderr, "ScreenTestCallback: Warning - Video buffer->internal_handle is NULL.\n");
      fflush(stderr);
    }

  } else if (buffer->type == MINIAV_BUFFER_TYPE_AUDIO) {
    g_audio_packet_count++;
    double delta_ms = 0.0;
    if (last_audio_timestamp_us != 0 && buffer->timestamp_us > last_audio_timestamp_us) {
      delta_ms = (double)(buffer->timestamp_us - last_audio_timestamp_us) / 1000.0;
      printf("Audio: +%.3f ms (Packet #%d, Size: %zu, TS: %" PRIu64 "us)\n",
             delta_ms, g_audio_packet_count, buffer->data_size_bytes, buffer->timestamp_us);
    } else {
      printf("Audio: First packet (Packet #%d, Size: %zu, TS: %" PRIu64 "us)\n",
             g_audio_packet_count, buffer->data_size_bytes, buffer->timestamp_us);
    }
    last_audio_timestamp_us = buffer->timestamp_us;

    if (buffer->internal_handle) {

      MiniAV_ReleaseBuffer(buffer->internal_handle);
    }
    // else it might be normal for audio buffers not to have an internal_handle needing this specific release path

  } else {
    fprintf(stderr,
            "ScreenTestCallback: Received buffer of unexpected type: %d, TS: %" PRIu64 "us\n",
            buffer->type, buffer->timestamp_us);
    fflush(stderr);
    if (buffer->internal_handle) {
        MiniAV_ReleaseBuffer(buffer->internal_handle);
    }
  }
  fflush(stdout); // Ensure immediate output of printf
}

// Helper to sleep cross-platform
void screen_sleep_ms(int milliseconds) {
#ifdef _WIN32
  Sleep(milliseconds);
#else
  usleep(milliseconds * 1000);
#endif
}

const char *screen_pixel_format_to_string(MiniAVPixelFormat format) {
  switch (format) {
  case MINIAV_PIXEL_FORMAT_UNKNOWN:
    return "UNKNOWN";
  case MINIAV_PIXEL_FORMAT_I420:
    return "I420";
  case MINIAV_PIXEL_FORMAT_NV12:
    return "NV12";
  case MINIAV_PIXEL_FORMAT_NV21:
    return "NV21";
  case MINIAV_PIXEL_FORMAT_YUY2:
    return "YUY2";
  case MINIAV_PIXEL_FORMAT_UYVY:
    return "UYVY";
  case MINIAV_PIXEL_FORMAT_RGB24:
    return "RGB24";
  case MINIAV_PIXEL_FORMAT_BGR24:
    return "BGR24";
  case MINIAV_PIXEL_FORMAT_RGBA32:
    return "RGBA32";
  case MINIAV_PIXEL_FORMAT_BGRA32:
    return "BGRA32";
  case MINIAV_PIXEL_FORMAT_ARGB32:
    return "ARGB32";
  case MINIAV_PIXEL_FORMAT_ABGR32:
    return "ABGR32";
  case MINIAV_PIXEL_FORMAT_MJPEG:
    return "MJPEG";
  default:
    return "UNHANDLED_FORMAT";
  }
}

int main() {
  MiniAVResultCode res;
  uint32_t major, minor, patch;

  MiniAV_GetVersion(&major, &minor, &patch);
  printf("MiniAV Version: %u.%u.%u\n", major, minor, patch);
  printf("MiniAV Version String: %s\n", MiniAV_GetVersionString());

  MiniAV_SetLogCallback(test_screen_log_callback, NULL);
  MiniAV_SetLogLevel(
      MINIAV_LOG_LEVEL_DEBUG);

  MiniAVDeviceInfo *displays = NULL;
  uint32_t display_count = 0;

  MiniAVScreenContextHandle screen_ctx = NULL;
  printf("\nCreating screen context...\n");
  res = MiniAV_Screen_CreateContext(&screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to create screen context: %s\n",
            MiniAV_GetErrorString(res));
    return 1;
  }
  printf("Screen context created.\n");

  printf("\nEnumerating displays...\n");
  res = MiniAV_Screen_EnumerateDisplays(&displays, &display_count);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to enumerate displays: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Screen_DestroyContext(screen_ctx); // Clean up context
    return 1;
  }

  if (display_count == 0) {
    printf("No displays found.\n");
    MiniAV_Screen_DestroyContext(screen_ctx); // Clean up context
    return 0;
  }

  printf("Found %u display(s):\n", display_count);
  for (uint32_t i = 0; i < display_count; ++i) {
    printf("  Display %u: ID='%s', Name='%s', Default=%s\n", i,
           displays[i].device_id, displays[i].name,
           displays[i].is_default ? "Yes" : "No");
  }

  uint32_t selected_display_index = 0;
  if (display_count > 1) {
    printf("\nEnter the index of the display to capture (0-%u): ",
           display_count - 1);
    if (scanf("%u", &selected_display_index) != 1 ||
        selected_display_index >= display_count) {
      fprintf(stderr, "Invalid display index. Exiting.\n");
      MiniAV_FreeDeviceList(displays, display_count);
      MiniAV_Screen_DestroyContext(screen_ctx);
      return 1;
    }
  } else {
    printf("\nAutomatically selecting the only display (index 0).\n");
    selected_display_index = 0;
  }

  MiniAVDeviceInfo selected_display = displays[selected_display_index];
  printf("\nSelected display for testing: '%s' (ID: '%s')\n",
         selected_display.name, selected_display.device_id);

  MiniAVVideoInfo capture_format;
  memset(&capture_format, 0, sizeof(MiniAVVideoInfo));
  capture_format.width = 1920;
  capture_format.height = 1080;
  capture_format.output_preference = MINIAV_OUTPUT_PREFERENCE_GPU;
  capture_format.frame_rate_numerator = 240;
  capture_format.frame_rate_denominator = 1;

  printf("\nConfiguring screen capture for display '%s'...\n",
         selected_display.device_id);
  printf("  Requested FPS: %u/%u\n", capture_format.frame_rate_numerator,
         capture_format.frame_rate_denominator);
  printf("  Requested Output Preference: %s\n",
         capture_format.output_preference ==
                 MINIAV_OUTPUT_PREFERENCE_GPU
             ? "GPU_IF_AVAILABLE"
             : "CPU_ONLY");

  // Enable audio capture by passing 'true'
  res = MiniAV_Screen_ConfigureDisplay(screen_ctx, selected_display.device_id,
                                       &capture_format, true);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to configure screen capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Screen_DestroyContext(screen_ctx);
    MiniAV_FreeDeviceList(displays, display_count);
    return 1;
  }

  MiniAVVideoInfo actual_format;
  MiniAVAudioInfo actual_audio_format;
  MiniAV_Screen_GetConfiguredFormats(screen_ctx, &actual_format, &actual_audio_format);
  printf("Screen capture configured successfully.\n");
  printf("  Actual Capture Resolution: %ux%u\n", actual_format.width,
         actual_format.height);
  printf("  Actual Pixel Format: %s (%d)\n",
         screen_pixel_format_to_string(actual_format.pixel_format),
         actual_format.pixel_format);
  printf("  Actual FPS: %u/%u\n", actual_format.frame_rate_numerator,
         actual_format.frame_rate_denominator);
  printf("  Actual Output Preference: %s\n",
         actual_format.output_preference ==
                 MINIAV_OUTPUT_PREFERENCE_GPU
             ? "GPU_IF_AVAILABLE"
         : actual_format.output_preference == MINIAV_OUTPUT_PREFERENCE_CPU
             ? "CPU_ONLY"
             : "UNKNOWN");

  printf("\nStarting screen capture indefinitely...\n");
  printf("Press Ctrl+C to stop.\n");
  g_video_frame_count = 0;
  g_audio_packet_count = 0;

  res =
      MiniAV_Screen_StartCapture(screen_ctx, test_screen_buffer_callback, NULL);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to start screen capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Screen_DestroyContext(screen_ctx);
    MiniAV_FreeDeviceList(displays, display_count);
    return 1;
  }
  printf("Screen capture started. Monitoring frame/packet deltas...\n");

  // Loop indefinitely to keep the capture running
  // The callback will print real-time information
  // Use Ctrl+C to terminate the program
  while (1) {
    screen_sleep_ms(1000); // Keep main thread alive, sleep for 1 second
                           // Actual work happens in the callback thread(s)
  }

  // The following cleanup code will not be reached if Ctrl+C is used to exit.
  printf("\nStopping screen capture...\n");
  res = MiniAV_Screen_StopCapture(screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to stop screen capture: %s\n",
            MiniAV_GetErrorString(res));
  }
  printf("Screen capture stopped. Total video frames: %d, Total audio packets: %d\n",
         g_video_frame_count, g_audio_packet_count);

  printf("\nDestroying screen context...\n");
  res = MiniAV_Screen_DestroyContext(screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to destroy screen context: %s\n",
            MiniAV_GetErrorString(res));
  }
  printf("Screen context destroyed.\n");

  printf("\nCleaning up resources...\n");
  MiniAV_FreeDeviceList(displays, display_count);
  printf("Resources cleaned up.\n");
  printf("\nScreen capture test finished.\n");
  return 0; // Should not be reached in the while(1) scenario without break
}
