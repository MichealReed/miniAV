#include "loopback_context_macos_coreaudio.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"
#include "../../../include/miniav_buffer.h"

#ifdef __APPLE__

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AudioUnit/AudioUnit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <mach/mach.h>
#include <pthread.h>
#include <Foundation/Foundation.h>
#include <sys/sysctl.h>

// Audio Tap APIs (macOS 10.10+) - use the correct headers
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101000
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <AppKit/NSRunningApplication.h>
#define HAS_AUDIO_TAP_API 1
#else
#define HAS_AUDIO_TAP_API 0
#endif

// --- Forward Declarations ---
static MiniAVResultCode coreaudio_stop_capture(MiniAVLoopbackContext* ctx);

// --- Capture Mode Enum ---
typedef enum {
    CAPTURE_MODE_NONE,
    CAPTURE_MODE_VIRTUAL_DEVICE,         // Virtual audio device (BlackHole, etc.)
    CAPTURE_MODE_SYSTEM_TAP,             // System-wide audio tap
    CAPTURE_MODE_PROCESS_TAP             // Process-specific audio tap
} CoreAudioCaptureMode;

// --- Platform Specific Context ---
typedef struct CoreAudioLoopbackPlatformContext {
    MiniAVLoopbackContext* parent_ctx;
    
    // Virtual device capture (primary method for system audio)
    AudioDeviceID virtual_device_id;
    AudioUnit input_unit;
    bool is_capturing;
    
    // Audio Tap for process/system capture
    #if HAS_AUDIO_TAP_API
    AudioObjectID tap_id;
    AudioDeviceID aggregated_id;
    AudioDeviceIOProcID io_proc_id;
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
    CoreAudioCaptureMode capture_mode;
    
} CoreAudioLoopbackPlatformContext;

// --- Helper Functions ---
static MiniAVAudioFormat CoreAudioFormatToMiniAV(const AudioStreamBasicDescription* asbd) {
    if (asbd->mFormatID == kAudioFormatLinearPCM) {
        if (asbd->mFormatFlags & kAudioFormatFlagIsFloat) {
            if (asbd->mBitsPerChannel == 32) {
                return MINIAV_AUDIO_FORMAT_F32;
            }
        } else { // Integer PCM
            if (asbd->mBitsPerChannel == 16) {
                return MINIAV_AUDIO_FORMAT_S16;
            } else if (asbd->mBitsPerChannel == 32) {
                return MINIAV_AUDIO_FORMAT_S32;
            } else if (asbd->mBitsPerChannel == 8) {
                return MINIAV_AUDIO_FORMAT_U8;
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
            asbd->mBitsPerChannel = 32;
            asbd->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            break;
    }
    
    asbd->mBytesPerFrame = (asbd->mBitsPerChannel / 8) * asbd->mChannelsPerFrame;
    asbd->mFramesPerPacket = 1;
    asbd->mBytesPerPacket = asbd->mBytesPerFrame * asbd->mFramesPerPacket;
    
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
    AudioObjectPropertyAddress prop_addr = GetPropertyAddress(kAudioObjectPropertyManufacturer);
    CFStringRef manufacturer = NULL;
    UInt32 data_size = sizeof(CFStringRef);
    OSStatus status = AudioObjectGetPropertyData(deviceID, &prop_addr, 0, NULL, &data_size, &manufacturer);
    
    if (status == noErr && manufacturer) {
        bool is_virtual = false;
        
        if (CFStringCompare(manufacturer, CFSTR("ExistentialAudio Inc."), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        else if (CFStringCompare(manufacturer, CFSTR("Rogue Amoeba"), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        else if (CFStringCompare(manufacturer, CFSTR("ma++ ingalls"), 0) == kCFCompareEqualTo) {
            is_virtual = true;
        }
        
        CFRelease(manufacturer);
        return is_virtual;
    }
    
    return false;
}

#if HAS_AUDIO_TAP_API
// Audio IOProc callback for process audio tap
static OSStatus AudioTapIOProc(AudioObjectID          objID,
                               const AudioTimeStamp*  inNow,
                               const AudioBufferList* inInputData,
                               const AudioTimeStamp*  inInputTime,
                               AudioBufferList*       outOutputData,
                               const AudioTimeStamp*  outOutputTime,
                               void*                  inClientData) {
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)inClientData;
    MiniAVLoopbackContext* ctx = platCtx->parent_ctx;
    
    if (!ctx || !ctx->app_callback || !platCtx->is_capturing || !inInputData) {
        return kAudioHardwareNoError;
    }
    
    // Process the captured audio
    if (inInputData->mNumberBuffers > 0) {
        MiniAVNativeBufferInternalPayload* payload = 
            (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
        MiniAVBuffer* mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
        
        if (!payload || !mavBuffer_ptr) {
            miniav_free(payload);
            miniav_free(mavBuffer_ptr);
            return kAudioHardwareNoError;
        }
        
        payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO;
        payload->context_owner = ctx;
        payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
        mavBuffer_ptr->internal_handle = payload;
        
        // Copy audio data from the first buffer
        const AudioBuffer* sourceBuffer = &inInputData->mBuffers[0];
        void* audioCopy = miniav_calloc(sourceBuffer->mDataByteSize, 1);
        if (audioCopy) {
            memcpy(audioCopy, sourceBuffer->mData, sourceBuffer->mDataByteSize);
            payload->native_singular_resource_ptr = audioCopy;
            
            mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_AUDIO;
            mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
            mavBuffer_ptr->timestamp_us = AudioConvertHostTimeToNanos(inNow->mHostTime) / 1000;
            
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
    
    return kAudioHardwareNoError;
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
    platCtx->tap_id = kAudioObjectUnknown;
    platCtx->aggregated_id = kAudioObjectUnknown;
    platCtx->io_proc_id = NULL;
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
    if (platCtx->io_proc_id && platCtx->aggregated_id != kAudioObjectUnknown) {
        AudioDeviceDestroyIOProcID(platCtx->aggregated_id, platCtx->io_proc_id);
        platCtx->io_proc_id = NULL;
    }
    
    if (platCtx->aggregated_id != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(platCtx->aggregated_id);
        platCtx->aggregated_id = kAudioObjectUnknown;
    }
    
    if (platCtx->tap_id != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(platCtx->tap_id);
        platCtx->tap_id = kAudioObjectUnknown;
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

// ...existing includes...
#include <sys/sysctl.h>

// Helper function to enumerate running processes
static uint32_t EnumerateRunningProcesses(MiniAVDeviceInfo* devices, uint32_t max_devices) {
    uint32_t found_count = 0;
    
    // Get list of all processes
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    
    // Get size needed
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) {
        return 0;
    }
    
    struct kinfo_proc* processes = (struct kinfo_proc*)miniav_calloc(size, 1);
    if (!processes) {
        return 0;
    }
    
    // Get actual process list
    if (sysctl(mib, 4, processes, &size, NULL, 0) != 0) {
        miniav_free(processes);
        return 0;
    }
    
    size_t process_count = size / sizeof(struct kinfo_proc);
    
    for (size_t i = 0; i < process_count && found_count < max_devices; i++) {
        struct kinfo_proc* proc = &processes[i];
        
        // Skip kernel processes and system processes
        if (proc->kp_proc.p_pid <= 1) continue;
        if (strlen(proc->kp_proc.p_comm) == 0) continue;
        
        // Skip obvious system processes
        if (strncmp(proc->kp_proc.p_comm, "kernel", 6) == 0) continue;
        if (strncmp(proc->kp_proc.p_comm, "launchd", 7) == 0) continue;
        
        // Get more detailed process info
        char process_name[256] = {0};
        if (GetProcessNameByPID(proc->kp_proc.p_pid, process_name, sizeof(process_name))) {
            MiniAVDeviceInfo* info = &devices[found_count];
            snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "pid:%d", proc->kp_proc.p_pid);
            snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "%s (PID: %d)", 
                     process_name, proc->kp_proc.p_pid);
            info->is_default = false;
            found_count++;
        } else {
            // Fallback to comm name
            MiniAVDeviceInfo* info = &devices[found_count];
            snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "pid:%d", proc->kp_proc.p_pid);
            snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "%s (PID: %d)", 
                     proc->kp_proc.p_comm, proc->kp_proc.p_pid);
            info->is_default = false;
            found_count++;
        }
    }
    
    miniav_free(processes);
    return found_count;
}

// Helper function to enumerate windows
static uint32_t EnumerateWindows(MiniAVDeviceInfo* devices, uint32_t max_devices) {
    uint32_t found_count = 0;
    
    // Get list of all windows
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    
    if (!windowList) {
        return 0;
    }
    
    CFIndex windowCount = CFArrayGetCount(windowList);
    
    for (CFIndex i = 0; i < windowCount && found_count < max_devices; i++) {
        CFDictionaryRef windowInfo = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, i);
        
        // Get window ID
        CFNumberRef windowNumber = (CFNumberRef)CFDictionaryGetValue(windowInfo, kCGWindowNumber);
        if (!windowNumber) continue;
        
        CGWindowID windowID;
        CFNumberGetValue(windowNumber, kCFNumberSInt32Type, &windowID);
        
        // Get window name
        CFStringRef windowName = (CFStringRef)CFDictionaryGetValue(windowInfo, kCGWindowName);
        char windowNameStr[256] = "Unnamed Window";
        if (windowName) {
            CFStringGetCString(windowName, windowNameStr, sizeof(windowNameStr), kCFStringEncodingUTF8);
        }
        
        // Get owner name
        CFStringRef ownerName = (CFStringRef)CFDictionaryGetValue(windowInfo, kCGWindowOwnerName);
        char ownerNameStr[256] = "Unknown";
        if (ownerName) {
            CFStringGetCString(ownerName, ownerNameStr, sizeof(ownerNameStr), kCFStringEncodingUTF8);
        }
        
        // Get PID
        CFNumberRef pidNumber = (CFNumberRef)CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID);
        pid_t pid = 0;
        if (pidNumber) {
            CFNumberGetValue(pidNumber, kCFNumberIntType, &pid);
        }
        
        // Skip windows without proper names or from system processes
        if (strlen(windowNameStr) == 0 || strcmp(windowNameStr, "Unnamed Window") == 0) {
            continue;
        }
        
        // Skip system windows
        if (strcmp(ownerNameStr, "Window Server") == 0 || 
            strcmp(ownerNameStr, "Dock") == 0 ||
            strcmp(ownerNameStr, "SystemUIServer") == 0) {
            continue;
        }
        
        MiniAVDeviceInfo* info = &devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "window:%u", windowID);
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "%s - %s (Window ID: %u, PID: %d)", 
                 windowNameStr, ownerNameStr, windowID, pid);
        info->is_default = false;
        found_count++;
    }
    
    CFRelease(windowList);
    return found_count;
}

static MiniAVResultCode coreaudio_enumerate_targets(MiniAVLoopbackTargetType target_type_filter,
                                                   MiniAVDeviceInfo** targets_out, uint32_t* count_out) {
    if (!targets_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
    *targets_out = NULL;
    *count_out = 0;
    
    const uint32_t MAX_TARGETS = 512; // Increased for process/window enumeration
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
        }
    }
    
    // Process-specific capture - enumerate all running processes
    if (target_type_filter == MINIAV_LOOPBACK_TARGET_PROCESS || target_type_filter == MINIAV_LOOPBACK_TARGET_NONE) {
        #if HAS_AUDIO_TAP_API
        uint32_t process_count = EnumerateRunningProcesses(&temp_devices[found_count], MAX_TARGETS - found_count);
        found_count += process_count;
        #else
        MiniAVDeviceInfo* info = &temp_devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "process_not_supported");
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "Process capture requires macOS 10.10+ and Audio Tap API");
        info->is_default = false;
        found_count++;
        #endif
    }

    // Window-specific capture - enumerate all visible windows
    if (target_type_filter == MINIAV_LOOPBACK_TARGET_WINDOW || target_type_filter == MINIAV_LOOPBACK_TARGET_NONE) {
        #if HAS_AUDIO_TAP_API
        uint32_t window_count = EnumerateWindows(&temp_devices[found_count], MAX_TARGETS - found_count);
        found_count += window_count;
        #else
        MiniAVDeviceInfo* info = &temp_devices[found_count];
        snprintf(info->device_id, MINIAV_DEVICE_ID_MAX_LEN, "window_not_supported");
        snprintf(info->name, MINIAV_DEVICE_NAME_MAX_LEN, "Window capture requires macOS 10.10+ and Audio Tap API");
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
        platCtx->target_pid = target_info->TARGETHANDLE.process_id;
        platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for process audio capture (PID: %d)", platCtx->target_pid);
        #else
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Process capture not supported in this build");
        return MINIAV_ERROR_NOT_SUPPORTED;
        #endif
    } else if (target_info && target_info->type == MINIAV_LOOPBACK_TARGET_WINDOW) {
        #if HAS_AUDIO_TAP_API
        // For window targets, we need to get the process ID from the window handle
        // On macOS, window handles are typically CGWindowID
        CGWindowID windowID = (CGWindowID)(uintptr_t)target_info->TARGETHANDLE.window_handle;
        
        // Get window info to find the owning process
        CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID);
        if (windowList && CFArrayGetCount(windowList) > 0) {
            CFDictionaryRef windowInfo = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, 0);
            CFNumberRef pidNumber = (CFNumberRef)CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID);
            
            if (pidNumber) {
                CFNumberGetValue(pidNumber, kCFNumberIntType, &platCtx->target_pid);
                platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for window audio capture (Window ID: %u, PID: %d)", 
                           windowID, platCtx->target_pid);
            } else {
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to get process ID for window %u", windowID);
                if (windowList) CFRelease(windowList);
                return MINIAV_ERROR_INVALID_ARG;
            }
            CFRelease(windowList);
        } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to get info for window %u", windowID);
            if (windowList) CFRelease(windowList);
            return MINIAV_ERROR_INVALID_ARG;
        }
        #else
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Window capture not supported in this build");
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
        } else if (strncmp(target_device_id, "window:", 7) == 0) {
            #if HAS_AUDIO_TAP_API
            CGWindowID windowID;
            sscanf(target_device_id + 7, "%u", &windowID);
            
            // Get window info to find the owning process
            CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID);
            if (windowList && CFArrayGetCount(windowList) > 0) {
                CFDictionaryRef windowInfo = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, 0);
                CFNumberRef pidNumber = (CFNumberRef)CFDictionaryGetValue(windowInfo, kCGWindowOwnerPID);
                
                if (pidNumber) {
                    CFNumberGetValue(pidNumber, kCFNumberIntType, &platCtx->target_pid);
                    platCtx->capture_mode = CAPTURE_MODE_PROCESS_TAP;
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Configured for window capture (Window ID: %u, PID: %d)", 
                               windowID, platCtx->target_pid);
                } else {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to get process ID for window %u", windowID);
                    if (windowList) CFRelease(windowList);
                    return MINIAV_ERROR_INVALID_ARG;
                }
                CFRelease(windowList);
            } else {
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to get info for window %u", windowID);
                if (windowList) CFRelease(windowList);
                return MINIAV_ERROR_INVALID_ARG;
            }
            #else
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Window capture not supported in this build");
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
            platCtx->target_pid = 0; // Will target current process or be set later
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

static MiniAVResultCode coreaudio_start_capture(MiniAVLoopbackContext* ctx, MiniAVBufferCallback callback, void* user_data) {
    if (!ctx || !ctx->platform_ctx || !callback) return MINIAV_ERROR_INVALID_ARG;
    
    CoreAudioLoopbackPlatformContext* platCtx = (CoreAudioLoopbackPlatformContext*)ctx->platform_ctx;

    // Set the callback and user_data on the main context for use by IOProcs/AudioUnit callbacks
    ctx->app_callback = callback;
    ctx->app_callback_user_data = user_data;
    
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
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Attempting to start Audio Tap capture (mode: %d)", platCtx->capture_mode);
        
        @autoreleasepool {
            NSProcessInfo *processInfo = [NSProcessInfo processInfo];
            int currentProcessID = [processInfo processIdentifier];
            NSUUID* tapUUID = [NSUUID UUID];
            CATapDescription *desc = nil;
            
            // Check if we have the necessary permissions first
            // Audio taps require special entitlements or running as admin
            if (@available(macOS 10.15, *)) {
                if (platCtx->capture_mode == CAPTURE_MODE_PROCESS_TAP && platCtx->target_pid > 0) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Creating process-specific tap for PID: %d", platCtx->target_pid);
                    
                    // Check if the target process exists
                    if (kill(platCtx->target_pid, 0) != 0) {
                        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Target process PID %d does not exist or is not accessible", platCtx->target_pid);
                        status = kAudioHardwareIllegalOperationError;
                    } else {
                        if ([CATapDescription instancesRespondToSelector:@selector(initStereoMixdownOfProcesses:)]) {
                            desc = [[CATapDescription alloc] initStereoMixdownOfProcesses:
                                    [NSArray arrayWithObject:[NSNumber numberWithInt:platCtx->target_pid]]];
                        }
                        if (!desc) {
                            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to init CATapDescription for PID %d", platCtx->target_pid);
                            status = kAudioHardwareIllegalOperationError;
                        }
                    }
                } else if (platCtx->capture_mode == CAPTURE_MODE_SYSTEM_TAP) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Creating system-wide audio tap");
                    
                    // Try different initialization methods based on macOS version
                    if ([CATapDescription instancesRespondToSelector:@selector(initStereoGlobalTapButExcludeProcesses:)]) {
                        desc = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
                    } else if ([CATapDescription instancesRespondToSelector:@selector(initStereoGlobalTap)]) {
                        desc = [[CATapDescription alloc] initStereoGlobalTap];
                    }
                    
                    if (!desc) {
                        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to init CATapDescription for system output");
                        status = kAudioHardwareIllegalOperationError;
                    }
                }
            } else {
                // For older macOS versions, try legacy methods
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Attempting legacy Audio Tap initialization");
                if ([CATapDescription instancesRespondToSelector:@selector(initStereoGlobalTap)]) {
                    desc = [[CATapDescription alloc] initStereoGlobalTap];
                }
                
                if (!desc) {
                    miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: Legacy Audio Tap initialization failed");
                    status = kAudioHardwareIllegalOperationError;
                }
            }

            if (desc && status == noErr) {
                desc.name = [NSString stringWithFormat:@"miniav-tap-%d", currentProcessID];
                desc.UUID = tapUUID;
                desc.privateTap = true;
                desc.muteBehavior = CATapUnmuted;
                desc.exclusive = false;
                desc.mixdown = true;
                
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Attempting to create process tap with description");
                status = AudioHardwareCreateProcessTap(desc, &platCtx->tap_id);
                
                // Log the specific error
                if (status != noErr) {
                    const char* error_name = "Unknown";
                    switch (status) {
                        case kAudioHardwareNotRunningError:
                            error_name = "Audio Hardware Not Running";
                            break;
                        case kAudioHardwareUnspecifiedError:
                            error_name = "Unspecified Hardware Error";
                            break;
                        case kAudioHardwareIllegalOperationError:
                            error_name = "Illegal Operation (Permission Denied)";
                            break;
                        case kAudioHardwareBadPropertySizeError:
                            error_name = "Bad Property Size";
                            break;
                        case kAudioHardwareUnsupportedOperationError:
                            error_name = "Unsupported Operation";
                            break;
                        default:
                            break;
                    }
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: AudioHardwareCreateProcessTap failed with status %d (0x%X): %s", 
                               status, status, error_name);
                    
                    // Provide user-friendly guidance
                    if (status == kAudioHardwareIllegalOperationError || status == 560947818) {
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: Audio Tap creation failed. This may be due to:");
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "  1. Missing com.apple.audio.AudioHardwareService entitlement");
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "  2. App not running with elevated permissions");
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "  3. Target process not accessible");
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "  4. System audio tapping disabled by user/admin");
                    }
                }
            } else if (!desc) {
                status = kAudioHardwareIllegalOperationError;
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Could not create CATapDescription");
            }
            
            if (status != noErr) { 
                miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: Audio Tap creation failed, falling back to virtual device capture");
                platCtx->virtual_device_id = FindVirtualAudioDevice();
                if (platCtx->virtual_device_id != kAudioObjectUnknown) {
                    platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
                    miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Successfully found virtual device ID %u for fallback", platCtx->virtual_device_id);
                } else {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: No virtual audio device found for fallback");
                    miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Consider installing BlackHole (https://github.com/ExistentialAudio/BlackHole) for system audio capture");
                    pthread_mutex_unlock(&platCtx->capture_mutex);
                    return MINIAV_ERROR_DEVICE_NOT_FOUND;
                }
            } else {
                // Successfully created tap, continue with aggregated device creation
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CoreAudio: Process tap created successfully, creating aggregated device");
                
                NSString *deviceName = [NSString stringWithFormat:@"miniav-aggregated-%d", currentProcessID];
                NSNumber *isPrivateKey = [NSNumber numberWithBool:true];
                
                NSArray* tapConf = [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:true], [NSString stringWithUTF8String:kAudioSubTapDriftCompensationKey],
                                    tapUUID.UUIDString, [NSString stringWithUTF8String:kAudioSubTapUIDKey],
                                    nil]];
                
                NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                      deviceName, [NSString stringWithUTF8String:kAudioAggregateDeviceNameKey],
                                      [[NSUUID UUID] UUIDString], [NSString stringWithUTF8String:kAudioAggregateDeviceUIDKey],
                                      isPrivateKey, [NSString stringWithUTF8String:kAudioAggregateDeviceIsPrivateKey],
                                      tapConf, [NSString stringWithUTF8String:kAudioAggregateDeviceTapListKey],
                                      nil];
                
                CFDictionaryRef dictBridge = (__bridge CFDictionaryRef)dict;
                status = AudioHardwareCreateAggregateDevice(dictBridge, &platCtx->aggregated_id);
                
                if (status != noErr) {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to create aggregate device: %d (0x%X)", status, status);
                    AudioHardwareDestroyProcessTap(platCtx->tap_id);
                    platCtx->tap_id = kAudioObjectUnknown;
                    
                    // Fallback to virtual device
                    platCtx->virtual_device_id = FindVirtualAudioDevice();
                    if (platCtx->virtual_device_id != kAudioObjectUnknown) {
                        platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
                    } else {
                        pthread_mutex_unlock(&platCtx->capture_mutex);
                        return MINIAV_ERROR_SYSTEM_CALL_FAILED;
                    }
                } else {
                    status = AudioDeviceCreateIOProcID(platCtx->aggregated_id, AudioTapIOProc, platCtx, &platCtx->io_proc_id);
                    if (status != noErr) {
                        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to create IOProc: %d (0x%X)", status, status);
                        AudioHardwareDestroyAggregateDevice(platCtx->aggregated_id);
                        AudioHardwareDestroyProcessTap(platCtx->tap_id);
                        platCtx->aggregated_id = kAudioObjectUnknown;
                        platCtx->tap_id = kAudioObjectUnknown;
                        
                        // Fallback to virtual device
                        platCtx->virtual_device_id = FindVirtualAudioDevice();
                        if (platCtx->virtual_device_id != kAudioObjectUnknown) {
                            platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
                        } else {
                            pthread_mutex_unlock(&platCtx->capture_mutex);
                            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
                        }
                    } else {
                        status = AudioDeviceStart(platCtx->aggregated_id, platCtx->io_proc_id);
                        if (status != noErr) {
                            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to start audio device: %d (0x%X)", status, status);
                            AudioDeviceDestroyIOProcID(platCtx->aggregated_id, platCtx->io_proc_id);
                            AudioHardwareDestroyAggregateDevice(platCtx->aggregated_id);
                            AudioHardwareDestroyProcessTap(platCtx->tap_id);
                            platCtx->io_proc_id = NULL;
                            platCtx->aggregated_id = kAudioObjectUnknown;
                            platCtx->tap_id = kAudioObjectUnknown;
                            
                            // Fallback to virtual device
                            platCtx->virtual_device_id = FindVirtualAudioDevice();
                            if (platCtx->virtual_device_id != kAudioObjectUnknown) {
                                platCtx->capture_mode = CAPTURE_MODE_VIRTUAL_DEVICE;
                            } else {
                                pthread_mutex_unlock(&platCtx->capture_mutex);
                                return MINIAV_ERROR_SYSTEM_CALL_FAILED;
                            }
                        } else {
                            // Successfully started tap
                            platCtx->is_capturing = true;
                            ctx->is_running = true;
                            pthread_mutex_unlock(&platCtx->capture_mutex);
                            miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Audio Tap capture started successfully");
                            return MINIAV_SUCCESS;
                        }
                    }
                }
            }
        } // @autoreleasepool
    }
#endif // HAS_AUDIO_TAP_API
    
    // Virtual device capture (primary if tap not available/supported, or fallback if tap failed)
    if (platCtx->capture_mode == CAPTURE_MODE_VIRTUAL_DEVICE) {
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Starting virtual device capture.");
        if (platCtx->virtual_device_id == kAudioObjectUnknown) {
            // Attempt to find one last time if not already set by a failed tap attempt
            platCtx->virtual_device_id = FindVirtualAudioDevice();
            if (platCtx->virtual_device_id == kAudioObjectUnknown) {
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: No virtual device ID available for virtual device capture mode.");
                pthread_mutex_unlock(&platCtx->capture_mutex);
                return MINIAV_ERROR_DEVICE_NOT_FOUND;
            }
        }

        AudioComponentDescription compDesc;
        compDesc.componentType = kAudioUnitType_Output;
        compDesc.componentSubType = kAudioUnitSubType_HALOutput;
        compDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
        compDesc.componentFlags = 0;
        compDesc.componentFlagsMask = 0;

        AudioComponent inputComponent = AudioComponentFindNext(NULL, &compDesc);
        if (!inputComponent) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to find input component for virtual device.");
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        status = AudioComponentInstanceNew(inputComponent, &platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to create AudioUnit instance: %d", status);
            pthread_mutex_unlock(&platCtx->capture_mutex);
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        UInt32 enableFlag = 1;
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableFlag, sizeof(enableFlag));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to enable input on AudioUnit: %d", status);
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        enableFlag = 0;
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enableFlag, sizeof(enableFlag));
         if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_WARN, "CoreAudio: Failed to disable output on AudioUnit: %d (continuing)", status);
        }

        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &platCtx->virtual_device_id, sizeof(platCtx->virtual_device_id));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set current device on AudioUnit: %d", status);
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &platCtx->stream_format, sizeof(platCtx->stream_format));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set stream format on AudioUnit: %d", status);
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = AudioInputCallback;
        callbackStruct.inputProcRefCon = platCtx;
        status = AudioUnitSetProperty(platCtx->input_unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callbackStruct, sizeof(callbackStruct));
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to set input callback on AudioUnit: %d", status);
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        MiniAVAudioInfo configured_format;
        coreaudio_get_configured_format(ctx, &configured_format); // Get currently configured format for num_frames
        UInt32 bufferSizeFrames = configured_format.num_frames > 0 ? configured_format.num_frames : 1024;
        UInt32 bufferSizeBytes = bufferSizeFrames * platCtx->stream_format.mBytesPerFrame;
        
        platCtx->audio_buffer_list = (AudioBufferList*)miniav_calloc(1, offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * 1));
        if (!platCtx->audio_buffer_list) {
             miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to allocate audio buffer list.");
             AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
             pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_OUT_OF_MEMORY;
        }
        platCtx->audio_buffer_list->mNumberBuffers = 1;
        platCtx->audio_buffer_list->mBuffers[0].mNumberChannels = platCtx->stream_format.mChannelsPerFrame;
        platCtx->audio_buffer_list->mBuffers[0].mDataByteSize = bufferSizeBytes;
        platCtx->audio_buffer_list->mBuffers[0].mData = miniav_calloc(bufferSizeBytes, 1);

        if (!platCtx->audio_buffer_list->mBuffers[0].mData) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to allocate audio buffer data.");
            miniav_free(platCtx->audio_buffer_list); platCtx->audio_buffer_list = NULL;
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_OUT_OF_MEMORY;
        }

        status = AudioUnitInitialize(platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to initialize AudioUnit: %d", status);
            miniav_free(platCtx->audio_buffer_list->mBuffers[0].mData);
            miniav_free(platCtx->audio_buffer_list); platCtx->audio_buffer_list = NULL;
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        status = AudioOutputUnitStart(platCtx->input_unit);
        if (status != noErr) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to start AudioUnit: %d", status);
            AudioUnitUninitialize(platCtx->input_unit);
            miniav_free(platCtx->audio_buffer_list->mBuffers[0].mData);
            miniav_free(platCtx->audio_buffer_list); platCtx->audio_buffer_list = NULL;
            AudioComponentInstanceDispose(platCtx->input_unit); platCtx->input_unit = NULL;
            pthread_mutex_unlock(&platCtx->capture_mutex); return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        platCtx->is_capturing = true;
        ctx->is_running = true;
        pthread_mutex_unlock(&platCtx->capture_mutex);
        miniav_log(MINIAV_LOG_LEVEL_INFO, "CoreAudio: Virtual device capture started successfully.");
        return MINIAV_SUCCESS;
    }
    
    // If we reach here, it means neither tap nor virtual device capture was successful or applicable
    pthread_mutex_unlock(&platCtx->capture_mutex);
    miniav_log(MINIAV_LOG_LEVEL_ERROR, "CoreAudio: Failed to start capture. No suitable method (Tap or Virtual Device) succeeded for mode %d.", platCtx->capture_mode);
    return MINIAV_ERROR_NOT_SUPPORTED; // Or a more specific error like MINIAV_ERROR_DEVICE_NOT_FOUND
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
    if (platCtx->io_proc_id && platCtx->aggregated_id != kAudioObjectUnknown) {
        AudioDeviceStop(platCtx->aggregated_id, platCtx->io_proc_id);
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