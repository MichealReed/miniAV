// Core type definitions first
#include "../../include/miniav_buffer.h" // Defines MiniAVBuffer, MiniAVBufferType, MiniAVPixelFormat, MiniAVSampleFormat
#include "../../include/miniav_types.h" // Defines MiniAVResultCode, handles, MiniAVDeviceInfo, MiniAVAudioInfo, MiniAVVideoFormatInfo, etc.

// API header using the types
#include "../../include/miniav_capture.h" // Defines MiniAVBufferCallback and the capture functions

// Internal headers for this module
#include "../common/miniav_context_base.h"
#include "../common/miniav_logging.h"
#include "../common/miniav_utils.h"
#include "audio_context.h" // Specific internal header for this file (if any)

// Standard library headers
#include <stdlib.h>
#include <string.h>

// Use miniaudio as the backend
#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#include "../third_party/miniaudio/miniaudio.h"

// --- Helper Functions ---

// Convert MiniAVSampleFormat to ma_format
static ma_format miniav_format_to_ma_format(MiniAVAudioFormat format) {
  switch (format) {
  case MINIAV_AUDIO_FORMAT_U8:
    return ma_format_u8;
  case MINIAV_AUDIO_FORMAT_S16:
    return ma_format_s16;
  case MINIAV_AUDIO_FORMAT_S32:
    return ma_format_s32;
  case MINIAV_AUDIO_FORMAT_F32:
    return ma_format_f32;
  default:
    return ma_format_unknown;
  }
}

// Convert ma_format to MiniAVSampleFormat
static MiniAVAudioFormat ma_format_to_miniav_format(ma_format format) {
  switch (format) {
  case ma_format_u8:
    return MINIAV_AUDIO_FORMAT_U8;
  case ma_format_s16:
    return MINIAV_AUDIO_FORMAT_S16;
  case ma_format_s32:
    return MINIAV_AUDIO_FORMAT_S32;
  case ma_format_f32:
    return MINIAV_AUDIO_FORMAT_F32;
  default:
    return ma_format_unknown;
  }
}

// Internal audio context struct
struct MiniAVAudioContext {
  MiniAVContextBase *base;
  int is_configured;
  int is_running;
  ma_context ma_ctx;
  ma_device ma_device;
  ma_device_id ma_capture_device_id; // Store the actual miniaudio device ID
  MiniAVAudioInfo format_info; // Store the configured format
  MiniAVBufferCallback callback;
  void *callback_user_data;
  int has_ma_context; // Flag to track ma_context initialization
};

// Helper: Convert miniaudio device info to MiniAVDeviceInfo
// Uses the actual miniaudio device ID, converting it to a hex string for
// uniqueness.
static void fill_device_info(const ma_device_info *src, MiniAVDeviceInfo *dst) {
  memset(dst, 0, sizeof(MiniAVDeviceInfo));
  // Use the device name as the primary identifier string for MiniAV
  miniav_strlcpy(dst->device_id, src->name, sizeof(dst->device_id));
  miniav_strlcpy(dst->name, src->name,
                 sizeof(dst->name)); // Also copy to name field
  dst->is_default = src->isDefault;
}

// --- Public API Implementation ---

MiniAVResultCode MiniAV_Audio_EnumerateDevices(MiniAVDeviceInfo **devices,
                                               uint32_t *count) {
  if (!devices || !count) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Invalid arguments for enumeration.");
    return MINIAV_ERROR_INVALID_ARG;
  }
  *devices = NULL;
  *count = 0;

  ma_context ma_ctx;
  ma_result res = ma_context_init(NULL, 0, NULL, &ma_ctx);
  if (res != MA_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to initialize miniaudio context: %s",
               ma_result_description(res));
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  ma_device_info *playbackInfos;
  ma_uint32 playbackCount;
  ma_device_info *captureInfos;
  ma_uint32 captureCount;
  res = ma_context_get_devices(&ma_ctx, &playbackInfos, &playbackCount,
                               &captureInfos, &captureCount);
  if (res != MA_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to get miniaudio devices: %s",
               ma_result_description(res));
    ma_context_uninit(&ma_ctx);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (captureCount == 0) {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "No audio capture devices found.");
    ma_context_uninit(&ma_ctx);
    return MINIAV_SUCCESS;
  }

  *devices =
      (MiniAVDeviceInfo *)miniav_calloc(captureCount, sizeof(MiniAVDeviceInfo));
  if (!*devices) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Out of memory allocating device list.");
    ma_context_uninit(&ma_ctx); // Use the temporary context
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  for (ma_uint32 i = 0; i < captureCount; ++i) {
    fill_device_info(&captureInfos[i],
                     &(*devices)[i]); // Use updated fill_device_info
  }
  *count = captureCount;

  ma_context_uninit(&ma_ctx); // Use the temporary context
  miniav_log(MINIAV_LOG_LEVEL_DEBUG, "Enumerated %u audio capture devices.",
             *count);
  return MINIAV_SUCCESS;
}

// TODO: Implement MiniAV_Audio_GetSupportedFormats properly by querying
// miniaudio
MiniAVResultCode
MiniAV_Audio_GetSupportedFormats(const char *device_id_str,
                                 MiniAVAudioInfo **formats,
                                 uint32_t *count) {
  if (!device_id_str || !formats || !count)
    return MINIAV_ERROR_INVALID_ARG;

  // --- Placeholder Implementation ---
  // This should ideally query the specific device using
  // ma_context_get_device_info and ma_device_info_get_supported_formats. For
  // now, return a common set.
  miniav_log(MINIAV_LOG_LEVEL_WARN,
             "MiniAV_Audio_GetSupportedFormats is using a placeholder "
             "implementation.");

  *count = 4; // Number of formats we'll return
  *formats = (MiniAVAudioInfo *)miniav_calloc(
      *count, sizeof(MiniAVAudioInfo));
  if (!*formats) {
    *count = 0;
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  (*formats)[0] =
      (MiniAVAudioInfo){.format = MINIAV_AUDIO_FORMAT_F32,
                              .sample_rate = 48000,
                              .channels = 2};
  (*formats)[1] =
      (MiniAVAudioInfo){.format = MINIAV_AUDIO_FORMAT_S16,
                              .sample_rate = 48000,
                              .channels = 2};
  (*formats)[2] =
      (MiniAVAudioInfo){.format = MINIAV_AUDIO_FORMAT_F32,
                              .sample_rate = 44100,
                              .channels = 2};
  (*formats)[3] =
      (MiniAVAudioInfo){.format = MINIAV_AUDIO_FORMAT_S16,
                              .sample_rate = 44100,
                              .channels = 2};
  // Add more common formats or query properly later

  return MINIAV_SUCCESS;
  // --- End Placeholder ---
}

MiniAVResultCode MiniAV_Audio_CreateContext(MiniAVAudioContextHandle *context) {
  if (!context)
    return MINIAV_ERROR_INVALID_ARG;

  MiniAVAudioContext *ctx =
      (MiniAVAudioContext *)miniav_calloc(1, sizeof(MiniAVAudioContext));
  if (!ctx) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to allocate audio context.");
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ctx->base =
      miniav_context_base_create(NULL); // User data can be set later if needed
  if (!ctx->base) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to allocate base context.");
    miniav_free(ctx);
    return MINIAV_ERROR_OUT_OF_MEMORY;
  }

  ma_result res = ma_context_init(NULL, 0, NULL, &ctx->ma_ctx);
  if (res != MA_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to initialize miniaudio context: %s",
               ma_result_description(res));
    miniav_context_base_destroy(ctx->base);
    miniav_free(ctx);
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  ctx->has_ma_context = 1;

  *context = (MiniAVAudioContextHandle)ctx;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Audio context created.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Audio_DestroyContext(MiniAVAudioContextHandle context) {
  MiniAVAudioContext *ctx = (MiniAVAudioContext *)context;
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG; // Or SUCCESS?

  if (ctx->is_running) {
    MiniAV_Audio_StopCapture(context);
  }

  if (ctx->has_ma_context) {
    ma_context_uninit(&ctx->ma_ctx);
    ctx->has_ma_context = 0;
  }

  if (ctx->base) {
    miniav_context_base_destroy(ctx->base);
  }
  miniav_free(ctx);
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Audio context destroyed.");
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Audio_Configure(
    MiniAVAudioContextHandle context,
    const char *device_name_str, // Parameter renamed for clarity
    const MiniAVAudioInfo *format) {
  MiniAVAudioContext *ctx = (MiniAVAudioContext *)context;
  if (!ctx || !format || !ctx->has_ma_context)
    return MINIAV_ERROR_INVALID_ARG;
  if (ctx->is_running)
    return MINIAV_ERROR_ALREADY_RUNNING;

  ma_device_id *p_capture_device_id_to_use = NULL; // Use pointer for config
  ma_device_id default_device_id; // Temporary storage if default is found

  // Enumerate devices within the context to find the matching ID
  ma_device_info *playbackInfos, *captureInfos;
  ma_uint32 playbackCount, captureCount;
  ma_result res =
      ma_context_get_devices(&ctx->ma_ctx, &playbackInfos, &playbackCount,
                             &captureInfos, &captureCount);
  if (res != MA_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to get devices during configuration: %s",
               ma_result_description(res));

    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  if (captureCount == 0) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "No capture devices found during configuration.");
    return MINIAV_ERROR_DEVICE_NOT_FOUND; // No devices available at all
  }

  int found_device = 0;
  if (device_name_str == NULL || strlen(device_name_str) == 0) {
    // --- Find Default Device ---
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "Attempting to use default audio capture device.");
    for (ma_uint32 i = 0; i < captureCount; ++i) {
      if (captureInfos[i].isDefault) {
        default_device_id = captureInfos[i].id; // Store the ID
        p_capture_device_id_to_use = &default_device_id;
        found_device = 1;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "Found default audio capture device: %s",
                   captureInfos[i].name);
        break;
      }
    }
    // Fallback if no default marked: use the first capture device
    if (!found_device) {
      default_device_id = captureInfos[0].id;
      p_capture_device_id_to_use = &default_device_id;
      found_device = 1; // Treat the first one as found
      miniav_log(MINIAV_LOG_LEVEL_WARN,
                 "No default capture device marked, using first device: %s",
                 captureInfos[0].name);
    }
  } else {
    // --- Find Device By Name ---
    miniav_log(MINIAV_LOG_LEVEL_DEBUG,
               "Attempting to find audio capture device by name: %s",
               device_name_str);
    for (ma_uint32 i = 0; i < captureCount; ++i) {
      // Compare the provided name with the enumerated device name
      if (strcmp(device_name_str, captureInfos[i].name) == 0) {
        default_device_id = captureInfos[i].id; // Store the ID
        p_capture_device_id_to_use = &default_device_id;
        found_device = 1;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG,
                   "Found specified audio capture device: %s",
                   captureInfos[i].name);
        break;
      }
    }
  }

  if (!found_device) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Failed to find specified audio device: %s",
               device_name_str ? device_name_str : "(Default)");
    return MINIAV_ERROR_DEVICE_NOT_FOUND;
  }

  ctx->ma_capture_device_id = *p_capture_device_id_to_use; // Copy the ID value

  ctx->format_info = *format; // Copy format info
  ctx->is_configured = 1;

  miniav_log(MINIAV_LOG_LEVEL_INFO,
             "Audio context configured: Format=%d, Rate=%u, Channels=%u",
             format->format, format->sample_rate, format->channels);
  return MINIAV_SUCCESS;
}

// Miniaudio data callback (called on high-priority thread)
static void ma_data_callback(ma_device *pDevice, void *pOutput,
                             const void *pInput, ma_uint32 frameCount) {
  MINIAV_UNUSED(pOutput); // We are only capturing

  MiniAVAudioContext *ctx = (MiniAVAudioContext *)pDevice->pUserData;
  if (!ctx || !ctx->callback || !pInput || frameCount == 0) {
    return; // Nothing to do
  }

  MiniAVBuffer buffer;
  memset(&buffer, 0, sizeof(buffer)); // Important: Zero out buffer struct

  buffer.type = MINIAV_BUFFER_TYPE_AUDIO;
  buffer.timestamp_us = miniav_get_time_us(); // Use utility for timestamp
  buffer.internal_handle =
      NULL; // Not used directly by miniaudio capture this way
  buffer.user_data = ctx->callback_user_data; // Pass user data along

  // --- Populate audio specific data ---
  // Use the field names defined in miniav_buffer.h
  buffer.data.audio.info.channels =
      ma_format_to_miniav_format(pDevice->capture.format);
  // sample_rate is not part of the buffer struct itself
  buffer.data.audio.info.channels =
      pDevice->capture.channels; // Use channel_count
  buffer.data.audio.frame_count = frameCount;
  buffer.data.audio.data =
      (void *)pInput; // Point directly to miniaudio's buffer

  // Calculate and store total size in the top-level field
  buffer.data_size_bytes =
      frameCount * ma_get_bytes_per_frame(pDevice->capture.format,
                                          pDevice->capture.channels);

  // Call the user's callback
  ctx->callback(&buffer, ctx->callback_user_data);
}

MiniAVResultCode MiniAV_Audio_StartCapture(MiniAVAudioContextHandle context,
                                           MiniAVBufferCallback callback,
                                           void *user_data) {
  MiniAVAudioContext *ctx = (MiniAVAudioContext *)context;
  if (!ctx || !callback)
    return MINIAV_ERROR_INVALID_ARG;
  if (!ctx->is_configured) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR,
               "Audio context not configured before start.");
    return MINIAV_ERROR_NOT_INITIALIZED;
  }
  if (ctx->is_running)
    return MINIAV_ERROR_ALREADY_RUNNING;

  ctx->callback = callback;
  ctx->callback_user_data = user_data;

  ma_device_config deviceConfig = ma_device_config_init(ma_device_type_capture);
  deviceConfig.capture.pDeviceID = &ctx->ma_capture_device_id;
  deviceConfig.capture.format =
      miniav_format_to_ma_format(ctx->format_info.format);
  deviceConfig.capture.channels = ctx->format_info.channels;
  deviceConfig.sampleRate = ctx->format_info.sample_rate;
  deviceConfig.dataCallback = ma_data_callback;
  deviceConfig.pUserData = ctx;
  deviceConfig.playback.format = ma_format_unknown;
  deviceConfig.playback.channels = 0;

  // Initialize the device
  ma_result res = ma_device_init(&ctx->ma_ctx, &deviceConfig, &ctx->ma_device);
  if (res != MA_SUCCESS) {
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to initialize audio device: %s",
               ma_result_description(res));
    // Maybe try to get more detailed error info if available
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  // Start the device
  res = ma_device_start(&ctx->ma_device);
  if (res != MA_SUCCESS) {
    ma_device_uninit(&ctx->ma_device); // Clean up initialized device
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "Failed to start audio device: %s",
               ma_result_description(res));
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }

  ctx->is_running = 1;
  miniav_log(MINIAV_LOG_LEVEL_INFO, "Audio capture started on device %s.",
             ctx->ma_device.capture.name); // Log the actual device name used
  return MINIAV_SUCCESS;
}

MiniAVResultCode MiniAV_Audio_StopCapture(MiniAVAudioContextHandle context) {
  MiniAVAudioContext *ctx = (MiniAVAudioContext *)context;
  if (!ctx)
    return MINIAV_ERROR_INVALID_ARG;
  if (!ctx->is_running)
    return MINIAV_ERROR_NOT_RUNNING; // Or SUCCESS?

  ma_device_uninit(&ctx->ma_device);             // Stops and uninitializes
  memset(&ctx->ma_device, 0, sizeof(ma_device)); // Clear device struct

  ctx->is_running = 0;
  ctx->callback = NULL; // Clear callback info
  ctx->callback_user_data = NULL;

  miniav_log(MINIAV_LOG_LEVEL_INFO, "Audio capture stopped.");
  return MINIAV_SUCCESS;
}
