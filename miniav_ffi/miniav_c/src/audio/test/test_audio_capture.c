#include "../../../include/miniav_capture.h"
#include "../../../include/miniav_types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h> // For sleep()
#endif

// Simple logging callback for the test
void test_log_callback(MiniAVLogLevel level, const char *message, void *user_data) {
    (void)user_data; // Unused
    const char *level_str = "UNKNOWN";
    switch (level) {
    case MINIAV_LOG_LEVEL_DEBUG: level_str = "DEBUG"; break;
    case MINIAV_LOG_LEVEL_INFO: level_str = "INFO"; break;
    case MINIAV_LOG_LEVEL_WARN: level_str = "WARN"; break;
    case MINIAV_LOG_LEVEL_ERROR: level_str = "ERROR"; break;
    }
    fprintf(stderr, "[MiniAV Test - %s] %s\n", level_str, message);
}

// Simple buffer callback for the test
void test_audio_buffer_callback(const MiniAVBuffer *buffer, void *user_data) {
    (void)user_data; // Unused
    if (!buffer || buffer->type != MINIAV_BUFFER_TYPE_AUDIO) {
        fprintf(stderr, "Received invalid buffer in callback.\n");
        return;
    }

    // Print basic info about the received audio buffer
    printf("Received Audio Buffer: Timestamp=%" PRIu64 "us, Format=%d, Channels=%u, Frames=%u, Size=%zu bytes\n",
           buffer->timestamp_us,
           buffer->data.audio.sample_format,
           buffer->data.audio.channel_count,
           buffer->data.audio.frame_count,
           buffer->data_size_bytes);
}

// Helper to sleep cross-platform
void sleep_ms(int milliseconds) {
#ifdef _WIN32
    Sleep(milliseconds);
#else
    usleep(milliseconds * 1000);
#endif
}

int main() {
    MiniAVResultCode res;
    uint32_t major, minor, patch;

    // 1. Initialize Logging
    MiniAV_SetLogCallback(test_log_callback, NULL);
    MiniAV_SetLogLevel(MINIAV_LOG_LEVEL_DEBUG);

    MiniAV_GetVersion(&major, &minor, &patch);
    printf("MiniAV Version: %u.%u.%u (%s)\n", major, minor, patch, MiniAV_GetVersionString());

    // 2. Enumerate Devices
    MiniAVDeviceInfo *devices = NULL;
    uint32_t device_count = 0;
    printf("\nEnumerating Audio Input Devices...\n");
    res = MiniAV_Audio_EnumerateDevices(&devices, &device_count);
    if (res != MINIAV_SUCCESS) {
        fprintf(stderr, "Failed to enumerate audio devices: %s\n", MiniAV_GetErrorString(res));
        return 1;
    }

    if (device_count == 0) {
        printf("No audio input devices found.\n");
        // Decide if this is an error or just exit cleanly
        return 0;
    }

    printf("Found %u audio input device(s):\n", device_count);
    const char *default_device_id = NULL;
    for (uint32_t i = 0; i < device_count; ++i) {
        printf("  [%u] ID: %s, Name: %s %s\n",
               i,
               devices[i].device_id,
               devices[i].name,
               devices[i].is_default ? "(Default)" : "");
        if (devices[i].is_default) {
            default_device_id = devices[i].device_id;
        }
    }
     // If no device explicitly marked default, use the first one for the test
    if (!default_device_id && device_count > 0) {
        default_device_id = devices[0].device_id;
        printf("No default device marked, will use the first device for testing: %s\n", devices[0].name);
    }


    // 3. Create Context
    printf("\nCreating Audio Context...\n");
    MiniAVAudioContextHandle context = NULL;
    res = MiniAV_Audio_CreateContext(&context);
    if (res != MINIAV_SUCCESS) {
        fprintf(stderr, "Failed to create audio context: %s\n", MiniAV_GetErrorString(res));
        MiniAV_FreeDeviceList(devices, device_count); // Free device list
        return 1;
    }

    // 4. Configure Context (Using default device and a common format)
    printf("Configuring Audio Context for default device...\n");
    MiniAVAudioFormatInfo config_format = {
        .sample_format = MINIAV_AUDIO_FORMAT_F32, // Request 32-bit float
        .sample_rate = 48000,                      // Request 48kHz
        .channels = 2                              // Request stereo
    };
    // Pass NULL for device_id_str to use the default device found by Configure
    res = MiniAV_Audio_Configure(context, NULL, &config_format);
    if (res != MINIAV_SUCCESS) {
        fprintf(stderr, "Failed to configure audio context: %s\n", MiniAV_GetErrorString(res));
        MiniAV_Audio_DestroyContext(context);
        MiniAV_FreeDeviceList(devices, device_count);
        return 1;
    }

    // 5. Start Capture
    printf("\nStarting Audio Capture for 5 seconds...\n");
    res = MiniAV_Audio_StartCapture(context, test_audio_buffer_callback, NULL);
    if (res != MINIAV_SUCCESS) {
        fprintf(stderr, "Failed to start audio capture: %s\n", MiniAV_GetErrorString(res));
        MiniAV_Audio_DestroyContext(context);
        MiniAV_FreeDeviceList(devices, device_count);
        return 1;
    }

    // 6. Run for a duration
    sleep_ms(5000); // Capture for 5 seconds

    // 7. Stop Capture
    printf("\nStopping Audio Capture...\n");
    res = MiniAV_Audio_StopCapture(context);
    if (res != MINIAV_SUCCESS) {
        // Log error but continue cleanup
        fprintf(stderr, "Failed to stop audio capture cleanly: %s\n", MiniAV_GetErrorString(res));
    }

    // 8. Clean up
    printf("Destroying Audio Context...\n");
    MiniAV_Audio_DestroyContext(context);

    printf("Freeing device list...\n");
    MiniAV_FreeDeviceList(devices, device_count); // Free the enumerated list

    printf("\nAudio capture test finished.\n");
    return 0;
}