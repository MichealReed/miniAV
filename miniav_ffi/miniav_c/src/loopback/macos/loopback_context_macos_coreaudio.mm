#include "loopback_context_macos_coreaudio.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"
#include "../../../include/miniav_buffer.h"

#ifdef __APPLE__

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <AudioUnit/AudioUnit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <mach/mach.h>
#include <pthread.h>

// Audio Tap APIs (macOS 10.10+)
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101000
#include <CoreAudio/AudioHardware.h>
#define HAS_AUDIO_TAP_API 1
#else
#define HAS_AUDIO_TAP_API 0
#endif

// --- Platform Specific Context ---
typedef struct CoreAudioLoopbackPlatformContext {
    MiniAVLoopbackContext* parent_ctx;
    
    // Virtual device capture (primary method for system audio)
    AudioDeviceID virtual_device_id;
    AudioUnit input_unit;
    bool is_capturing;
    
    // Audio Tap for process/system capture
    #if HAS_AUDIO_TAP_API
    AudioHardwareTapRef tap_ref;
    pid_t target_pid;
    #endif
    
    // Audio format info
    AudioStreamBasicDescription stream_format;
    AudioBufferList* audio_buffer_list;
    
    // Capture thread
    pthread_t capture_thread;
    dispatch_queue_t capture_queue;
    
    // Synchronization
    pthread_mutex_t capture_mutex;
    bool should_stop_capture;
    
    // Capture mode
    enum {
        CAPTURE_MODE_NONE,
        CAPTURE_MODE_VIRTUAL_DEVICE,         // Virtual audio device (BlackHole, etc.)
        CAPTURE_MODE_SYSTEM_TAP,             // System-wide audio tap
        CAPTURE_MODE_PROCESS_TAP             // Process-specific audio tap
    } capture_mode;
    
} CoreAudioLoopbackPlatformContext;

// --- Helper Functions ---
static MiniAVAudioFormat CoreAudioFormatToMiniAV(const AudioStreamBasicDescription* asbd) {
    if (asbd->mFormatID == kAudioFormatLinearPCM) {
        if (asbd->mFormatFlags & kAudioFormatFlagIsFloat) {
            if (asbd->mBitsPerChannel == 32) {
                return MINIAV_AUDIO_FORMAT_F32;
            }
            // F64 not supported in MiniAV, fallback to F32
        } else { // Integer PCM
            if (asbd->mBitsPerChannel == 16) {
                return (asbd->mFormatFlags & kAudioFormatFlagIsSignedInteger) ? 
                       MINIAV_AUDIO_FORMAT_S16 : MINIAV_AUDIO_FORMAT_S16; // No U16 in MiniAV
            } else if (asbd->mBitsPerChannel == 32) {
                return MINIAV_AUDIO_FORMAT_S32;
            } else if (asbd->mBitsPerChannel == 8) {
                return MINIAV_AUDIO_FORMAT_U8; // Use U8 for 8-bit
            }
        }
    }
    return MINIAV_AUDIO_FORMAT_UNKNOWN;
}

static void MiniAVFormatToCoreAudio(const MiniAVAudioInfo* miniav_format, AudioStreamBasicDescription* asbd) {
    memset(asbd, 0, sizeof(AudioStreamBasicDescription));
    asbd->mSampleRate = miniav_format->sample_rate;
    asbd->mChannelsPerFrame = miniav_format->channels;
    asbd->mFormatID = kAudioFormatLinearPCM;
    
    switch (miniav_format->format) {
        case MINIAV_AUDIO_FORMAT_F32:
            asbd->mBitsPerChannel = 32;
            asbd->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            break;
        case MINIAV_AUDIO_FORMAT_S16:
            asbd->mBitsPerChannel = 16;
            asbd->mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            break;
        case MINIAV_AUDIO_FORMAT_S32:
            asbd->mBitsPerChannel = 32;
            asbd->mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            break;
        case MINIAV_AUDIO_FORMAT_U8:
            asbd->mBitsPerChannel = 8;
            asbd->mFormatFlags = kAudioFormatFlagIsPacked;
            break;
        default:
            // Default to float32
            asbd->mBitsPerChannel = 32;
            asbd->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            break;
    }
    
    asbd->mBytesPerFrame = (asbd->mBitsPerChannel / 8) * asbd->mChannelsPerFrame;
    asbd->mFramesPerPacket = 1;
    asbd->mBytesPerPacket = asbd->mBytesPerFrame * asbd->mFramesPerPacket;
    
    // Use native endianness
    if (asbd->mFormatFlags & kAudioFormatFlagIsSignedInteger) {
        asbd->mFormatFlags |= kAudioFormatFlagsNativeEndian;
    }
}

// Get process name by PID
static bool GetProcessNameByPID(pid_t pid, char* name_buffer, size_t buffer_size) {
    struct proc_bsdinfo proc_info;
    int result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc_info, sizeof(proc_info));
    if (result == sizeof(proc_info)) {
        strncpy(name_buffer, proc_info.pbi_name, buffer_size - 1);
        name_buffer[buffer_size - 1] = '\0';
        return true;
    }
    return false;
}

static AudioObjectPropertyAddress GetPropertyAddress(AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        .mSelector = selector,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain
    };
    return address;
}

// Check if a device is a virtual audio device (like BlackHole)
static bool IsVirtualAudioDevice(AudioDeviceID deviceID) {
    // Get device manufacturer
    AudioObjectPropertyAddress prop_addr = GetPropertyAddress(kAudioObjectPropertyManufacturer);
    CFStringRef manufacturer = NULL;
    UInt32 data_size = sizeof(CFStringRef);
    OSStatus status = AudioObjectGetPropertyData(deviceID, &prop_addr, 0, NULL, &data_size, &manufacturer);
    
    if (status == noErr && manufacturer) {
        // Check for known virtual audio device manufacturers
        bool is_virtual = false;
        
        // BlackHole
        if (CFStringCompare(manufacturer, CFSTR("ExistentialAudio Inc."), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        // Loopback by Rogue Amoeba
        else if (CFStringCompare(manufacturer, CFSTR("Rogue Amoeba"), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        // SoundFlower (deprecated but might still be around)
        else if (CFStringCompare(manufacturer, CFSTR("ma++ ingalls"), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        
        CFRelease(manufacturer);
        return is_virtual;
    }
    
    return false;
}

#if HAS_AUDIO_TAP_API
// Audio Tap callback for system/process audio capture
static OSStatus AudioTapCallback(void* inRefCon, 
                                AudioHardwareTapRef inTap,
                                const AudioTimeStamp* inTimeStamp,
                                const AudioBufferList* inBufferList) {
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)inRefCon;
    MiniAVLoopbackContext* ctx = platCtx->parent_ctx;
    
    if (!ctx || !ctx->app_callback || !platCtx->is_capturing) {
        return noErr;
    }
    
    // Process the captured audio
    if (inBufferList && inBufferList->mNumberBuffers > 0) {
        MiniAVNativeBufferInternalPayload* payload = 
            (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
        MiniAVBuffer* mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
        
        if (!payload || !mavBuffer_ptr) {
            miniav_free(payload);
            miniav_free(mavBuffer_ptr);
            return noErr;
        }
        
        payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO;
        payload->context_owner = ctx;
        payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
        mavBuffer_ptr->internal_handle = payload;
        
        // Copy audio data from the first buffer
        const AudioBuffer* sourceBuffer = &inBufferList->mBuffers[0];
        void* audioCopy = miniav_calloc(sourceBuffer->mDataByteSize, 1);
        if (audioCopy) {
            memcpy(audioCopy, sourceBuffer->mData, sourceBuffer->mDataByteSize);
            payload->native_singular_resource_ptr = audioCopy;
            
            mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_AUDIO;
            mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
            mavBuffer_ptr->timestamp_us = AudioConvertHostTimeToNanos(inTimeStamp->mHostTime) / 1000;
            
            // Calculate frame count from buffer size and format
            uint32_t frame_count = sourceBuffer->mDataByteSize / platCtx->stream_format.mBytesPerFrame;
            
            mavBuffer_ptr->data.audio.frame_count = frame_count;
            mavBuffer_ptr->data.audio.info.sample_rate = (uint32_t)platCtx->stream_format.mSampleRate;
            mavBuffer_ptr->data.audio.info.channels = platCtx->stream_format.mChannelsPerFrame;
            mavBuffer_ptr->data.audio.info.format = CoreAudioFormatToMiniAV(&platCtx->stream_format);
            mavBuffer_ptr->data.audio.info.num_frames = frame_count;
            mavBuffer_ptr->data.audio.data = audioCopy;
            
            mavBuffer_ptr->data_size_bytes = sourceBuffer->mDataByteSize;
            mavBuffer_ptr->user_data = ctx->app_callback_user_data;
            
            ctx->app_callback(mavBuffer_ptr, ctx->app_callback_user_data);
        } else {
            miniav_free(payload);
            miniav_free(mavBuffer_ptr);
        }
    }
    
    return noErr;
}
#endif

// AudioUnit input callback for virtual device capture
static OSStatus AudioInputCallback(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                                 const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                                 UInt32 inNumberFrames, AudioBufferList* ioData) {
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)inRefCon;
    MiniAVLoopbackContext* ctx = platCtx->parent_ctx;
    
    if (!ctx || !ctx->app_callback || !platCtx->is_capturing) {
        return noErr;
    }
    
    // Render audio from the input unit
    OSStatus status = AudioUnitRender(platCtx->input_unit, ioActionFlags, inTimeStamp, 
                                     inBusNumber, inNumberFrames, platCtx->audio_buffer_list);
    if (status != noErr) {
        miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: AudioUnitRender failed: %d", status);
        return status;
    }
    
    // Process the captured audio
    if (platCtx->audio_buffer_list && platCtx->audio_buffer_list->mNumberBuffers > 0) {
        MiniAVNativeBufferInternalPayload* payload = 
            (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
        MiniAVBuffer* mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
        
        if (!payload || !mavBuffer_ptr) {
            miniav_free(payload);
            miniav_free(mavBuffer_ptr);
            return noErr;
        }
        
        payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO;
        payload->context_owner = ctx;
        payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
        mavBuffer_ptr->internal_handle = payload;
        
        // Copy audio data
        AudioBuffer* sourceBuffer = &platCtx->audio_buffer_list->mBuffers[0];
        void* audioCopy = miniav_calloc(sourceBuffer->mDataByteSize, 1);
        if (audioCopy) {
            memcpy(audioCopy, sourceBuffer->mData, sourceBuffer->mDataByteSize);
            payload->native_singular_resource_ptr = audioCopy;
            
            mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_AUDIO;
            mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
            mavBuffer_ptr->timestamp_us = AudioConvertHostTimeToNanos(inTimeStamp->mHostTime) / 1000;
            
            mavBuffer_ptr->data.audio.frame_count = inNumberFrames;
            mavBuffer_ptr->data.audio.info.sample_rate = (uint32_t)platCtx->stream_format.mSampleRate;
            mavBuffer_ptr->data.audio.info.channels = platCtx->stream_format.mChannelsPerFrame;
            mavBuffer_ptr->data.audio.info.format = CoreAudioFormatToMiniAV(&platCtx->stream_format);
            mavBuffer_ptr->data.audio.info.num_frames = inNumberFrames;
            mavBuffer_ptr->data.audio.data = audioCopy;
            
            mavBuffer_ptr->data_size_bytes = sourceBuffer->mDataByteSize;
            mavBuffer_ptr->user_data = ctx->app_callback_user_data;
            
            ctx->app_callback(mavBuffer_ptr, ctx->app_callback_user_data);
        } else {
            miniav_free(payload);
            miniav_free(mavBuffer_ptr);
        }
    }
    
    return noErr;
}

// Find the best virtual audio device for system capture
static AudioDeviceID FindVirtualAudioDevice(void) {
    AudioObjectPropertyAddress prop_addr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 data_size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &prop_addr, 0, NULL, &data_size);
    if (status != noErr || data_size == 0) {
        return kAudioObjectUnknown;
    }
    
    UInt32 device_count = data_size / sizeof(AudioDeviceID);
    AudioDeviceID* devices = (AudioDeviceID*)miniav_calloc(device_count, sizeof(AudioDeviceID));
    if (!devices) {
        return kAudioObjectUnknown;
    }
    
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &prop_addr, 0, NULL, &data_size, devices);
    if (status != noErr) {
        miniav_free(devices);
        return kAudioObjectUnknown;
    }
    
    AudioDeviceID virtual_device = kAudioObjectUnknown;
    
    for (UInt32 i = 0; i < device_count; i++) {
        // Check if device has input streams
        prop_addr.mSelector = kAudioDevicePropertyStreams;
        prop_addr.mScope = kAudioDevicePropertyScopeInput;
        data_size = 0;
        status = AudioObjectGetPropertyDataSize(devices[i], &prop_addr, 0, NULL, &data_size);
        if (status != noErr || data_size == 0) {
            continue; // No input streams
        }
        
        // Check if it's a virtual device
        if (IsVirtualAudioDevice(devices[i])) {
            virtual_device = devices[i];
            break; // Use the first virtual device we find
        }
    }
    
    miniav_free(devices);
    return virtual_device;
}

// --- Platform Ops Implementation ---

static MiniAVResultCode coreaudio_init_platform(MiniAVLoopbackContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    platCtx->parent_ctx = ctx;
    platCtx->is_capturing = false;
    platCtx->should_stop_capture = false;
    platCtx->capture_mode = CAPTURE_MODE_NONE;
    platCtx->virtual_device_id = kAudioObjectUnknown;
    
    #if HAS_AUDIO_TAP_API
    platCtx->tap_ref = NULL;
    platCtx->target_pid = 0;
    #endif
    
    // Initialize mutex
    if (pthread_mutex_init(&platCtx->capture_mutex, NULL) != 0) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to initialize mutex");
        return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    
    // Create capture queue
    platCtx->capture_queue = dispatch_queue_create("com.miniav.loopback.capture", DISPATCH_QUEUE_SERIAL);
    if (!platCtx->capture_queue) {
        pthread_mutex_destroy(&platCtx->capture_mutex);
        return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Platform context initialized.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_destroy_platform(MiniAVLoopbackContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_SUCCESS;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    
    // Stop capture if running
    if (platCtx->is_capturing) {
        coreaudio_stop_capture(ctx);
    }
    
    // Clean up AudioUnit
    if (platCtx->input_unit) {
        AudioUnitUninitialize(platCtx->input_unit);
        AudioComponentInstanceDispose(platCtx->input_unit);
        platCtx->input_unit = NULL;
    }
    
    #if HAS_AUDIO_TAP_API
    // Clean up Audio Tap
    if (platCtx->tap_ref) {
        AudioHardwareTapDestroy(platCtx->tap_ref);
        platCtx->tap_ref = NULL;
    }
    #endif
    
    // Clean up audio buffer
    if (platCtx->audio_buffer_list) {
        if (platCtx->audio_buffer_list->mBuffers[0].mData) {
            miniav_free(platCtx->audio_buffer_list->mBuffers[0].mData);
        }
        miniav_free(platCtx->audio_buffer_list);
        platCtx->audio_buffer_list = NULL;
    }
    
    // Clean up dispatch queue
    if (platCtx->capture_queue) {
        dispatch_release(platCtx->capture_queue);
        platCtx->capture_queue = NULL;
    }
    
    // Destroy mutex
    pthread_mutex_destroy(&platCtx->capture_mutex);
    
    miniav_free(platCtx);
    ctx->platform_ctx = NULL;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Platform context destroyed.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_enumerate_targets(MiniAVLoopbackTargetType target_type_filter,
                                                   MiniAVDeviceInfo** targets_out, uint32_t* count_out) {
    if (!targets_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
    *targets_out = NULL;
    *count_out = 0;
    
    const uint32_t MAX_TARGETS = 256;
    MiniAVDeviceInfo* temp_devices = (MiniAVDeviceInfo*)miniav_calloc(MAX_TARGETS, sizeof(MiniAVDeviceInfo));
    if (!temp_devices) {
        return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    
    uint32_t found_count = 0;
    
    // System audio capture options
    if (target_type_filter == MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO || target_type_filter == MINIAV_LOOPBACK_TARGET_NONE) {
        #if HAS_AUDIO_TAP_API
        // System-wide audio tap (preferred method)
        MiniAVDeviceInfo* info = &temp_devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "system_tap");
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "System Audio (Audio Tap)");
        info->is_default = true;
        found_count++;
        #endif
        
        // Virtual audio devices as fallback method
        AudioDeviceID virtual_device = FindVirtualAudioDevice();
        if (virtual_device != kAudioObjectUnknown) {
            // Get device name
            AudioObjectPropertyAddress prop_addr = GetPropertyAddress(kAudioObjectPropertyName);
            CFStringRef device_name = NULL;
            UInt32 data_size = sizeof(CFStringRef);
            OSStatus status = AudioObjectGetPropertyData(virtual_device, &prop_addr, 0, NULL, &data_size, &device_name);
            
            if (status == noErr && device_name) {
                MiniAVDeviceInfo* info = &temp_devices[found_count];
                snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "virtual_device:%u", virtual_device);
                
                char device_name_str[256];
                CFStringGetCString(device_name, device_name_str, sizeof(device_name_str), kCFStringEncodingUTF8);
                snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "%s (Virtual Device)", device_name_str);
                #if !HAS_AUDIO_TAP_API
                info->is_default = true;
                #else
                info->is_default = false; // Audio Tap is preferred
                #endif
                
                CFRelease(device_name);
                found_count++;
            }
        } else if (!HAS_AUDIO_TAP_API) {
            // No virtual device available and no Audio Tap support
            MiniAVDeviceInfo* info = &temp_devices[found_count];
            snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "no_virtual_device");
            snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "Install BlackHole or similar virtual audio device");
            info->is_default = false;
            found_count++;
        }
    }
    
    // Process-specific capture
    if (target_type_filter == MINIAV_LOOPBACK_TARGET_PROCESS) {
        #if HAS_AUDIO_TAP_API
        // Add running audio processes (simplified - just show it's supported)
        MiniAVDeviceInfo* info = &temp_devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "process_tap");
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "Process Audio Capture (Audio Tap)");
        info->is_default = true;
        found_count++;
        #else
        MiniAVDeviceInfo* info = &temp_devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "process_not_supported");
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "Process capture requires macOS 10.10+ and Audio Tap API");
        info->is_default = false;
        found_count++;
        #endif
    }
    
    // Copy results
    if (found_count > 0) {
        *targets_out = (MiniAVDeviceInfo*)miniav_calloc(found_count, sizeof(MiniAVDeviceInfo));
        if (*targets_out) {
            memcpy(*targets_out, temp_devices, found_count * sizeof(MiniAVDeviceInfo));
            *count_out = found_count;
        } else {
            miniav_free(temp_devices);
            return MINIAV_ERROR_OUT_OF_MEMORY;
        }
    }
    
    miniav_free(temp_devices);
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Enumerated %u loopback targets", found_count);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_get_default_format(const char* target_device_id, MiniAVAudioInfo* format_out) {
    if (!format_out) return MINIAV_ERROR_INVALID_ARG;
    memset(format_out, 0, sizeof(MiniAVAudioInfo));
    
    // Default format for loopback audio
    format_out->sample_rate = 44100;
    format_out->channels = 2;
    format_out->format = MINIAV_AUDIO_FORMAT_F32;
    format_out->num_frames = 1024;
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Default format: 44.1kHz, 2 channels, float32");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_configure_loopback(MiniAVLoopbackContext* ctx,
                                                     const MiniAVLoopbackTargetInfo* target_info,
                                                     const char* target_device_id,
                                                     const MiniAVAudioInfo* requested_format) {
    if (!ctx || !ctx->platform_ctx || !requested_format) return MINIAV_ERROR_INVALID_ARG;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    
    // Store requested format
    MiniAVFormatToCoreAudio(requested_format, &platCtx->stream_format);
    
    // Determine capture method based on target
    if (target_info && target_info->type == MINIAV_LOOPBACK_TARGET_PROCESS) {
        #if HAS_AUDIO_TAP_API
        platCtx->target_pid = target_info->process.pid;
        platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for process audio capture (PID: %d)", platCtx->target_pid);
        #else
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Process capture not supported in this build");
        return MINIAV_ERROR_NOT_SUPPORTED;
        #endif
    } else if (target_info && target_info->type == MINIAV_LOOPBACK_TARGET_SYSTEM_AUDIO) {
        #if HAS_AUDIO_TAP_API
        platCtx->capture_mode = CAPTURE_MODE_SYSTEM_TAP;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for system audio capture (Audio Tap)");
        #else
        // Fallback to virtual device
        platCtx->virtual_device_id = FindVirtualAudioDevice();
        if (platCtx->virtual_device_id != kAudioObjectUnknown) {
            platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for system audio capture (Virtual Device)");
        } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: No system audio capture method available");
            return MINIAV_ERROR_NOT_SUPPORTED;
        }
        #endif
    } else if (target_device_id) {
        if (strncmp(target_device_id, "pid:", 4) == 0) {
            #if HAS_AUDIO_TAP_API
            sscanf(target_device_id + 4, "%d", &platCtx->target_pid);
            platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for process capture (PID: %d)", platCtx->target_pid);
            #else
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Process capture not supported in this build");
            return MINIAV_ERROR_NOT_SUPPORTED;
            #endif
        } else if (strcmp(target_device_id, "system_tap") == 0) {
            #if HAS_AUDIO_TAP_API
            platCtx->capture_mode = CAPTURE_MODE_SYSTEM_TAP;
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for system audio tap");
            #else
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: System tap not supported in this build");
            return MINIAV_ERROR_NOT_SUPPORTED;
            #endif
        } else if (strcmp(target_device_id, "process_tap") == 0) {
            #if HAS_AUDIO_TAP_API
            platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
            platCtx->target_pid = 0; // Will need to be set later
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for process audio tap");
            #else
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Process tap not supported in this build");
            return MINIAV_ERROR_NOT_SUPPORTED;
            #endif
        } else if (strncmp(target_device_id, "virtual_device:", 15) == 0) {
            sscanf(target_device_id + 15, "%u", &platCtx->virtual_device_id);
            platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for virtual device capture (ID: %u)", 
                       platCtx->virtual_device_id);
        } else if (strcmp(target_device_id, "no_virtual_device") == 0) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: No virtual audio device available");
            return MINIAV_ERROR_DEVICE_NOT_FOUND;
        } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Unknown device target: %s", target_device_id);
            return MINIAV_ERROR_DEVICE_NOT_FOUND;
        }
    } else {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: No target specified");
        return MINIAV_ERROR_INVALID_ARG;
    }
    
    ctx->is_configured = true;
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_start_capture(MiniAVLoopbackContext* ctx, MiniAVBufferCallback callback, void* user_data) {
    if (!ctx || !ctx->platform_ctx || !callback) return MINIAV_ERROR_INVALID_ARG;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    
    if (platCtx->is_capturing) {
        miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: Capture already running");
        return MINIAV_ERROR_ALREADY_RUNNING;
    }
    
    if (platCtx->capture_mode == CAPTURE_MODE_NONE) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Not configured");
        return MINIAV_ERROR_NOT_INITIALIZED;
    }
    
    pthread_mutex_lock(&platCtx->capture_mutex);
    platCtx->should_stop_capture = false;
    
    OSStatus status = noErr;
    
    #if HAS_AUDIO_TAP_API
    if (platCtx->capture_mode == CAPTURE_MODE_SYSTEM_TAP || platCtx->capture_mode == CAPTURE_MODE_PROCESS_TAP) {
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Starting Audio Tap capture");
        
        // Create Audio Tap
        AudioHardwareTapDescription tapDesc = {0};
        tapDesc.format = platCtx->stream_format;
        tapDesc.callback = AudioTapCallback;
        tapDesc.callbackRefCon = platCtx;
        
        if (platCtx->capture_mode == CAPTURE_MODE_PROCESS_TAP && platCtx->target_pid > 0) {
            status = AudioHardwareTapCreateForProcess(platCtx->target_pid, &tapDesc, &platCtx->tap_ref);
        } else {
            status = AudioHardwareTapCreateForSystemOutput(&tapDesc, &platCtx->tap_ref);
        }
        
        if (status != noErr || !platCtx->tap_ref) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to create Audio Tap: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        status = AudioHardwareTapStart(platCtx->tap_ref);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to start Audio Tap: %d", status);
            AudioHardwareTapDestroy(platCtx->tap_ref);
            platCtx->tap_ref = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        platCtx->is_capturing = true;
        ctx->is_running = true;
        pthread_mutex_unlock(&platCtx->capture_mutex);
        
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Audio Tap capture started successfully");
        return MINIAV_SUCCESS;
    }
    #endif
    
    // Virtual device capture (fallback)
    if (platCtx->capture_mode == CAPTURE_MODE_VIRTUAL_DEVICE) {
        AudioDeviceID input_device_id = platCtx->virtual_device_id;
        
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Starting virtual device capture (ID: %u)", input_device_id);
        
        // Create and configure AudioUnit for input
        AudioComponentDescription desc = {
            .componentType = kAudioUnitType_Output,
            .componentSubType = kAudioUnitSubType_HALOutput,
            .componentManufacturer = kAudioUnitManufacturer_Apple,
            .componentFlags = 0,
            .componentFlagsMask = 0
        };
        
        AudioComponent component = AudioComponentFindNext(NULL, &desc);
        if (!component) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to find AUHAL component");
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        status = AudioComponentInstanceNew(component, &platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to create AudioUnit: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Enable input on the AUHAL
        UInt32 enable_input = 1;
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Input, 1, &enable_input, sizeof(enable_input));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to enable input: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Disable output on the AUHAL
        UInt32 disable_output = 0;
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output, 0, &disable_output, sizeof(disable_output));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to disable output: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Set input device
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_CurrentDevice,
                                     kAudioUnitScope_Global, 0, &input_device_id, sizeof(AudioDeviceID));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set input device: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Set stream format
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output, 1, &platCtx->stream_format, sizeof(AudioStreamBasicDescription));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set stream format: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Set input callback
        AURenderCallbackStruct callback_struct = {
            .inputProc = AudioInputCallback,
            .inputProcRefCon = platCtx
        };
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_SetInputCallback,
                                     kAudioUnitScope_Global, 0, &callback_struct, sizeof(AURenderCallbackStruct));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set input callback: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        // Allocate audio buffer
        UInt32 buffer_size = 4096; // Frame count
        UInt32 bytes_per_frame = platCtx->stream_format.mBytesPerFrame;
        platCtx->audio_buffer_list = (AudioBufferList*)miniav_calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer));
        platCtx->audio_buffer_list->mNumberBuffers = 1;
        platCtx->audio_buffer_list->mBuffers[0].mNumberChannels = platCtx->stream_format.mChannelsPerFrame;
        platCtx->audio_buffer_list->mBuffers[0].mDataByteSize = buffer_size * bytes_per_frame;
        platCtx->audio_buffer_list->mBuffers[0].mData = miniav_calloc(platCtx->audio_buffer_list->mBuffers[0].mDataByteSize, 1);
        
        // Initialize and start AudioUnit
        status = AudioUnitInitialize(platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to initialize AudioUnit: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        status = AudioOutputUnitStart(platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to start AudioUnit: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        platCtx->is_capturing = true;
        ctx->is_running = true;
        pthread_mutex_unlock(&platCtx->capture_mutex);
        
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Virtual device capture started successfully");
        return MINIAV_SUCCESS;
    }
    
    pthread_mutex_unlock(&platCtx->capture_mutex);
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Unknown capture mode");
    return MINIAV_ERROR_NOT_SUPPORTED;
}

static MiniAVResultCode coreaudio_stop_capture(MiniAVLoopbackContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    
    if (!platCtx->is_capturing) {
        return MINIAV_SUCCESS;
    }
    
    pthread_mutex_lock(&platCtx->capture_mutex);
    platCtx->should_stop_capture = true;
    platCtx->is_capturing = false;
    ctx->is_running = false;
    
    #if HAS_AUDIO_TAP_API
    // Stop Audio Tap
    if (platCtx->tap_ref) {
        AudioHardwareTapStop(platCtx->tap_ref);
        AudioHardwareTapDestroy(platCtx->tap_ref);
        platCtx->tap_ref = NULL;
    }
    #endif
    
    // Stop AudioUnit
    if (platCtx->input_unit) {
        AudioOutputUnitStop(platCtx->input_unit);
        AudioUnitUninitialize(platCtx->input_unit);
    }
    
    pthread_mutex_unlock(&platCtx->capture_mutex);
    
    miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Loopback capture stopped");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_release_buffer(MiniAVLoopbackContext* ctx, void* native_buffer_payload_ptr) {
    MINIAV_UNUSED(ctx);
    if (!native_buffer_payload_ptr) return MINIAV_ERROR_INVALID_ARG;
    
    MiniAVNativeBufferInternalPayload* payload = (MiniAVNativeBufferInternalPayload*)native_buffer_payload_ptr;
    
    if (payload->native_singular_resource_ptr) {
        miniav_free(payload->native_singular_resource_ptr);
        payload->native_singular_resource_ptr = NULL;
    }
    
    if (payload->parent_miniav_buffer_ptr) {
        miniav_free(payload->parent_miniav_buffer_ptr);
        payload->parent_miniav_buffer_ptr = NULL;
    }
    
    miniav_free(payload);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode coreaudio_get_configured_format(MiniAVLoopbackContext* ctx, MiniAVAudioInfo* format_out) {
    if (!ctx || !ctx->platform_ctx || !format_out) return MINIAV_ERROR_INVALID_ARG;
    
    if (!ctx->is_configured) {
        return MINIAV_ERROR_NOT_INITIALIZED;
    }
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;
    
    format_out->sample_rate = (uint32_t)platCtx->stream_format.mSampleRate;
    format_out->channels = platCtx->stream_format.mChannelsPerFrame;
    format_out->format = CoreAudioFormatToMiniAV(&platCtx->stream_format);
    format_out->num_frames = 1024; // Default frame count
    
    return MINIAV_SUCCESS;
}

// --- Global Ops Table ---
const LoopbackContextInternalOps g_loopback_ops_macos_coreaudio = {
    .init_platform = coreaudio_init_platform,
    .destroy_platform = coreaudio_destroy_platform,
    .enumerate_targets_platform = coreaudio_enumerate_targets,
    .get_supported_formats = NULL, // Not implemented for now
    .get_default_format = coreaudio_get_default_format,
    .get_default_format_platform = coreaudio_get_default_format,
    .configure_loopback = coreaudio_configure_loopback,
    .start_capture = coreaudio_start_capture,
    .stop_capture = coreaudio_stop_capture,
    .release_buffer_platform = coreaudio_release_buffer,
    .get_configured_video_format = coreaudio_get_configured_format,
};

// --- Platform Init for Selection ---
MiniAVResultCode miniav_loopback_context_platform_init_macos_coreaudio(MiniAVLoopbackContext* ctx) {
    if (!ctx) return MINIAV_ERROR_INVALID_ARG;
    
    ctx->ops = &g_loopback_ops_macos_coreaudio;
    ctx->platform_ctx = miniav_calloc(1, sizeof(CoreAudioLoopbackPlatformContext));
    if (!ctx->platform_ctx) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to allocate platform context");
        ctx->ops = NULL;
        return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Loopback platform selected");
    return MINIAV_SUCCESS;
}

#endif // __APPLE__