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

volatile int g_frame_count = 0;
const int CAPTURE_DURATION_SECONDS = 10;

// Simple logging callback for the test
void test_log_callback(MiniAVLogLevel level, const char *message,
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
  fprintf(stderr, "[MiniAV Camera Test - %s] %s\n", level_str, message);
}

// Simple buffer callback for the test
void test_camera_buffer_callback(const MiniAVBuffer *buffer, void *user_data) {
  (void)user_data;
  if (!buffer) {
    fprintf(stderr, "TestCallback: Received NULL buffer!\n");
    return;
  }

  if (buffer->type == MINIAV_BUFFER_TYPE_VIDEO) {
    g_frame_count++;
    printf(
        "TestCallback: Received Video Buffer: Timestamp=%" PRIu64
        "us, %ux%u, Format=%d, Size=%zu bytes, Plane0 Stride=%u, Frame #%d\n",
        buffer->timestamp_us, buffer->data.video.info.width,
        buffer->data.video.info.height, buffer->data.video.info.pixel_format,
        buffer->data_size_bytes, buffer->data.video.stride_bytes[0],
        g_frame_count);

    if (buffer->internal_handle) {
      MiniAV_ReleaseBuffer(buffer->internal_handle); // Release the buffer
    } else {
      fprintf(stderr, "TestCallback: Warning - buffer->internal_handle is "
                      "NULL, cannot release.\n");
    }

  } else {
    fprintf(stderr, "TestCallback: Received buffer of unexpected type: %d\n",
            buffer->type);
  }
}

// Helper to sleep cross-platform
void sleep_ms(int milliseconds) {
#ifdef _WIN32
  Sleep(milliseconds);
#else
  usleep(milliseconds * 1000);
#endif
}

const char *pixel_format_to_string(MiniAVPixelFormat format) {
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

  MiniAV_SetLogCallback(test_log_callback, NULL);
  MiniAV_SetLogLevel(
      MINIAV_LOG_LEVEL_DEBUG); // Set to DEBUG for more verbose output

  MiniAVDeviceInfo *devices = NULL;
  uint32_t device_count = 0;

  printf("\nEnumerating camera devices...\n");
  res = MiniAV_Camera_EnumerateDevices(&devices, &device_count);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to enumerate camera devices: %s\n",
            MiniAV_GetErrorString(res));
    return 1;
  }

  if (device_count == 0) {
    printf("No camera devices found.\n");
    return 0;
  }

  printf("Found %u camera device(s):\n", device_count);
  for (uint32_t i = 0; i < device_count; ++i) {
    printf("  Device %u: ID='%s', Name='%s', Default=%s\n", i,
           devices[i].device_id, devices[i].name,
           devices[i].is_default ? "Yes" : "No");
  }

  // Prompt the user to select a device
  uint32_t selected_device_index = 0;
  printf("\nEnter the index of the device to use (0-%u): ", device_count - 1);
  if (scanf("%u", &selected_device_index) != 1 ||
      selected_device_index >= device_count) {
    fprintf(stderr, "Invalid device index. Exiting.\n");
    MiniAV_FreeDeviceList(devices, device_count);
    return 1;
  }

  MiniAVDeviceInfo selected_device = devices[selected_device_index];
  printf("\nSelected device for testing: '%s'\n", selected_device.name);

  MiniAVVideoInfo *formats = NULL;
  uint32_t format_count = 0;

  printf("\nGetting supported formats for device '%s'...\n",
         selected_device.device_id);
  res = MiniAV_Camera_GetSupportedFormats(selected_device.device_id, &formats,
                                          &format_count);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to get supported formats: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_FreeDeviceList(devices, device_count);
    return 1;
  }

  if (format_count == 0) {
    printf("No supported formats found for device '%s'.\n",
           selected_device.name);
    MiniAV_FreeDeviceList(devices, device_count);
    return 0;
  }

  printf("Found %u supported format(s) for '%s':\n", format_count,
         selected_device.name);
  for (uint32_t i = 0; i < format_count; ++i) {
    float fps_approx = (formats[i].frame_rate_denominator == 0)
                           ? 0.0f
                           : (float)formats[i].frame_rate_numerator /
                                 formats[i].frame_rate_denominator;
    printf("  Format %u: %ux%u @ %u/%u (%.2f) FPS, PixelFormat: %s (%d)\n", i,
           formats[i].width, formats[i].height, formats[i].frame_rate_numerator,
           formats[i].frame_rate_denominator, fps_approx,
           pixel_format_to_string(formats[i].pixel_format),
           formats[i].pixel_format);
  }

  // Select the first format for testing
  MiniAVVideoInfo selected_format = formats[0];
  printf("\nSelected format for testing: %ux%u @ %u/%u FPS, %s\n",
         selected_format.width, selected_format.height,
         selected_format.frame_rate_numerator,
         selected_format.frame_rate_denominator,
         pixel_format_to_string(selected_format.pixel_format));

  MiniAVCameraContextHandle cam_ctx = NULL;
  printf("\nCreating camera context...\n");
  res = MiniAV_Camera_CreateContext(&cam_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to create camera context: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_FreeFormatList(formats, format_count);
    MiniAV_FreeDeviceList(devices, device_count);
    return 1;
  }
  printf("Camera context created.\n");

  selected_format.output_preference = MINIAV_OUTPUT_PREFERENCE_GPU_IF_AVAILABLE;
  printf("\nConfiguring camera...\n");
  res = MiniAV_Camera_Configure(cam_ctx, selected_device.device_id,
                                &selected_format);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to configure camera: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Camera_DestroyContext(cam_ctx);
    MiniAV_FreeFormatList(formats, format_count);
    MiniAV_FreeDeviceList(devices, device_count);
    return 1;
  }
  printf("Camera configured.\n");

  printf("\nStarting camera capture for %d seconds...\n",
         CAPTURE_DURATION_SECONDS);
  g_frame_count = 0;
  res = MiniAV_Camera_StartCapture(cam_ctx, test_camera_buffer_callback, NULL);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to start camera capture: %s\n",
            MiniAV_GetErrorString(res));
    MiniAV_Camera_DestroyContext(cam_ctx);
    MiniAV_FreeFormatList(formats, format_count);
    MiniAV_FreeDeviceList(devices, device_count);
    return 1;
  }
  printf("Camera capture started. Waiting for frames...\n");

  for (int i = 0; i < CAPTURE_DURATION_SECONDS; ++i) {
    printf("Test main: Sleeping... (%d/%d s), Frames received so far: %d\n",
           i + 1, CAPTURE_DURATION_SECONDS, g_frame_count);
    sleep_ms(1000);
  }

  printf("\nStopping camera capture...\n");
  res = MiniAV_Camera_StopCapture(cam_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to stop camera capture: %s\n",
            MiniAV_GetErrorString(res));
    // Continue with cleanup
  }
  printf("Camera capture stopped. Total frames received: %d\n", g_frame_count);

  printf("\nDestroying camera context...\n");
  res = MiniAV_Camera_DestroyContext(cam_ctx);
  if (res != MINIAV_SUCCESS) {
    fprintf(stderr, "Failed to destroy camera context: %s\n",
            MiniAV_GetErrorString(res));
    // Continue with cleanup
  }
  printf("Camera context destroyed.\n");

  printf("\nCleaning up resources...\n");
  MiniAV_FreeFormatList(formats, format_count);
  MiniAV_FreeDeviceList(devices, device_count);
  printf("Resources cleaned up.\n");

  printf("\nCamera test finished.\n");
  return 0;
}
