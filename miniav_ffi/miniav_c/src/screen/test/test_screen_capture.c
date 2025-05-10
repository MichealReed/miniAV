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

volatile int g_screen_frame_count = 0;
const int SCREEN_CAPTURE_DURATION_SECONDS = 10;

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

// Simple buffer callback for the test
void test_screen_buffer_callback(const MiniAVBuffer *buffer, void *user_data) {
  (void)user_data;
  if (!buffer) {
    fprintf(stderr, "ScreenTestCallback: Received NULL buffer!\n");
    return;
  }

  if (buffer->type == MINIAV_BUFFER_TYPE_VIDEO) {
    g_screen_frame_count++;
    printf("ScreenTestCallback: Received Video Buffer: Timestamp=%" PRIu64
           "us, %ux%u, Format=%d (ContentType: %d), Size=%zu bytes, Plane0 "
           "Stride=%u, Frame #%d\n",
           buffer->timestamp_us, buffer->data.video.width,
           buffer->data.video.height, buffer->data.video.pixel_format,
           buffer->content_type, buffer->data_size_bytes,
           buffer->data.video.stride_bytes[0], g_screen_frame_count);

    if (buffer->content_type == MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE) {
      printf("  GPU Buffer: Shared Handle = %p, Texture Ptr = %p\n",
             buffer->data.video.native_gpu_shared_handle,
             buffer->data.video.native_gpu_texture_ptr);
      // For GPU buffers, the application would typically use the shared handle
      // and then call CloseHandle on it when done.
      // The native_gpu_texture_ptr is for internal tracking by MiniAV for
      // release.
    }

    if (buffer->internal_handle) {
      MiniAV_ReleaseBuffer(buffer->internal_handle); // Release the buffer
    } else {
      fprintf(stderr, "ScreenTestCallback: Warning - buffer->internal_handle "
                      "is NULL, cannot release.\n");
    }

  } else {
    fprintf(stderr,
            "ScreenTestCallback: Received buffer of unexpected type: %d\n",
            buffer->type);
  }
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
      MINIAV_LOG_LEVEL_DEBUG); // Set to DEBUG for more verbose output

  MiniAVDeviceInfo *displays = NULL;
  uint32_t display_count = 0;

  MiniAVScreenContextHandle screen_ctx = NULL;
  printf("\nCreating screen context...\n");
  res = MiniAV_Screen_CreateContext(&screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to create screen context: %s\n",
            MiniAV_GetErrorString(res));
    // MiniAV_FreeDeviceList(displays, display_count);
    return 1;
  }
  printf("Screen context created.\n");

  printf("\nEnumerating displays...\n");
  res = MiniAV_Screen_EnumerateDisplays(&displays, &display_count);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to enumerate displays: %s\n",
            MiniAV_GetErrorString(res));
    return 1;
  }

  if (display_count == 0) {
    printf("No displays found.\n");
    return 0;
  }

  printf("Found %u display(s):\n", display_count);
  for (uint32_t i = 0; i < display_count; ++i) {
    printf("  Display %u: ID='%s', Name='%s', Default=%s\n", i,
           displays[i].device_id, displays[i].name,
           displays[i].is_default ? "Yes" : "No");
  }

  // Prompt the user to select a display
  uint32_t selected_display_index = 0;
  if (display_count > 1) {
    printf("\nEnter the index of the display to capture (0-%u): ",
           display_count - 1);
    if (scanf("%u", &selected_display_index) != 1 ||
        selected_display_index >= display_count) {
      fprintf(stderr, "Invalid display index. Exiting.\n");
      MiniAV_FreeDeviceList(displays, display_count);
      return 1;
    }
  } else {
    printf("\nAutomatically selecting the only display (index 0).\n");
    selected_display_index = 0;
  }

  MiniAVDeviceInfo selected_display = displays[selected_display_index];
  printf("\nSelected display for testing: '%s' (ID: '%s')\n",
         selected_display.name, selected_display.device_id);

  // Prepare format for configuration
  // For screen capture, width, height, and pixel_format are usually determined
  // by the display itself. We can suggest FPS and output preference.
  MiniAVVideoFormatInfo capture_format;
  memset(&capture_format, 0, sizeof(MiniAVVideoFormatInfo));
  capture_format.output_preference = MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE;
  capture_format.frame_rate_numerator = 30; // Request 30 FPS
  capture_format.frame_rate_denominator = 1;
  // capture_format.output_preference = MINIAV_OUTPUT_PREFERENCE_CPU_ONLY;

  printf("\nConfiguring screen capture for display '%s'...\n",
         selected_display.device_id);
  printf("  Requested FPS: %u/%u\n", capture_format.frame_rate_numerator,
         capture_format.frame_rate_denominator);
  printf("  Requested Output Preference: %s\n",
         capture_format.output_preference ==
                 MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE
             ? "GPU_IF_AVAILABLE"
             : "CPU_ONLY");

  res = MiniAV_Screen_ConfigureDisplay(screen_ctx, selected_display.device_id,
                                       &capture_format, NULL);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to configure screen capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Screen_DestroyContext(screen_ctx);
    MiniAV_FreeDeviceList(displays, display_count);
    return 1;
  }

  // After configuration, the context should have the actual capture parameters
  MiniAVVideoFormatInfo actual_format;
  MiniAV_Screen_GetConfiguredFormat(screen_ctx, &actual_format);
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
                 MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE
             ? "GPU_IF_AVAILABLE"
         : actual_format.output_preference == MINIAV_OUTPUT_PREFERENCE_CPU
             ? "CPU_ONLY"
             : "UNKNOWN");

  printf("\nStarting screen capture for %d seconds...\n",
         SCREEN_CAPTURE_DURATION_SECONDS);
  g_screen_frame_count = 0;
  res =
      MiniAV_Screen_StartCapture(screen_ctx, test_screen_buffer_callback, NULL);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to start screen capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Screen_DestroyContext(screen_ctx);
    MiniAV_FreeDeviceList(displays, display_count);
    return 1;
  }
  printf("Screen capture started. Waiting for frames...\n");

  for (int i = 0; i < SCREEN_CAPTURE_DURATION_SECONDS; ++i) {
    printf(
        "ScreenTest main: Sleeping... (%d/%d s), Frames received so far: %d\n",
        i + 1, SCREEN_CAPTURE_DURATION_SECONDS, g_screen_frame_count);
    screen_sleep_ms(1000);
  }

  printf("\nStopping screen capture...\n");
  res = MiniAV_Screen_StopCapture(screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to stop screen capture: %s\n",
            MiniAV_GetErrorString(res));
    // Continue with cleanup
  }
  printf("Screen capture stopped. Total frames received: %d\n",
         g_screen_frame_count);

  printf("\nDestroying screen context...\n");
  res = MiniAV_Screen_DestroyContext(screen_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to destroy screen context: %s\n",
            MiniAV_GetErrorString(res));
    // Continue with cleanup
  }
  printf("Screen context destroyed.\n");

  printf("\nCleaning up resources...\n");
  MiniAV_FreeDeviceList(displays, display_count);
  printf("Resources cleaned up.\n");

  printf("\nScreen capture test finished.\n");
  return 0;
}