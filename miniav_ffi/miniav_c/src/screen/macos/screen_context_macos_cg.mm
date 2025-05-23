#include "screen_context_macos_cg.h"
#include "../../common/miniav_logging.h"
#include "../../common/miniav_utils.h"
#include "../../../include/miniav_buffer.h"

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>

// ScreenCaptureKit is available on macOS 12.3+
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 120300
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#define HAS_SCREEN_CAPTURE_KIT 1
#else
#define HAS_SCREEN_CAPTURE_KIT 0
#endif

// --- Platform Specific Context ---
typedef struct CGScreenPlatformContext {
    // Common fields
    MiniAVScreenContext* parent_ctx;
    dispatch_queue_t captureQueue;
    bool is_capturing;
    
    // Metal for GPU path
    id<MTLDevice> metalDevice;
    CVMetalTextureCacheRef textureCache;
    
    // Legacy Core Graphics capture (fallback)
    CGDirectDisplayID displayID;
    dispatch_source_t captureTimer;
    
#if HAS_SCREEN_CAPTURE_KIT
    // Modern ScreenCaptureKit capture (macOS 12.3+)
    SCStream* scStream API_AVAILABLE(macos(12.3));
    SCStreamConfiguration* scStreamConfig API_AVAILABLE(macos(12.3));
    id<SCStreamDelegate> scDelegate API_AVAILABLE(macos(12.3));
#endif
} CGScreenPlatformContext;

// --- Helper Functions ---
static MiniAVPixelFormat CGBitmapInfoToMiniAVPixelFormat(CGBitmapInfo bitmapInfo) {
    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
    CGBitmapInfo byteOrder = bitmapInfo & kCGBitmapByteOrderMask;
    
    // Common formats for screen capture
    if (byteOrder == kCGBitmapByteOrder32Little) {
        if (alphaInfo == kCGImageAlphaPremultipliedFirst) {
            return MINIAV_PIXEL_FORMAT_BGRA32; // BGRA with premultiplied alpha
        } else if (alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaNoneSkipFirst) {
            return MINIAV_PIXEL_FORMAT_BGRA32;
        }
    }
    
    if (byteOrder == kCGBitmapByteOrder32Big || byteOrder == kCGBitmapByteOrderDefault) {
        if (alphaInfo == kCGImageAlphaPremultipliedLast || alphaInfo == kCGImageAlphaLast) {
            return MINIAV_PIXEL_FORMAT_RGBA32;
        } else if (alphaInfo == kCGImageAlphaNoneSkipLast) {
            return MINIAV_PIXEL_FORMAT_RGBA32;
        }
    }
    
    return MINIAV_PIXEL_FORMAT_BGRA32; // Default fallback
}

#if HAS_SCREEN_CAPTURE_KIT
// --- ScreenCaptureKit Delegate ---
@interface MiniAVScreenCaptureDelegate : NSObject <SCStreamDelegate, SCStreamOutput>
{
    MiniAVScreenContext* _screenCtx;
}
- (instancetype)initWithScreenContext:(MiniAVScreenContext*)ctx;
@end

@implementation MiniAVScreenCaptureDelegate

- (instancetype)initWithScreenContext:(MiniAVScreenContext*)ctx {
    self = [super init];
    if (self) {
        _screenCtx = ctx;
    }
    return self;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (!_screenCtx || !_screenCtx->app_callback || !_screenCtx->is_running || !_screenCtx->platform_ctx) {
        return;
    }
    
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)_screenCtx->platform_ctx;
    
    if (type == SCStreamOutputTypeScreen) {
        // Handle video frame
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to get image buffer from sample buffer.");
            return;
        }
        
        [self processVideoFrame:imageBuffer withTimestamp:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        
    } else if (type == SCStreamOutputTypeAudio) {
        // Handle audio frame
        [self processAudioBuffer:sampleBuffer];
    }
}

- (void)processVideoFrame:(CVImageBufferRef)imageBuffer withTimestamp:(CMTime)timestamp {
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)_screenCtx->platform_ctx;
    MiniAVNativeBufferInternalPayload* payload = NULL;
    MiniAVBuffer* mavBuffer_ptr = NULL;
    
    // Allocate payload and buffer
    payload = (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
    if (!payload) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to allocate video payload.");
        return;
    }
    
    mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
    if (!mavBuffer_ptr) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to allocate video buffer.");
        miniav_free(payload);
        return;
    }
    
    payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
    payload->context_owner = _screenCtx;
    payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
    mavBuffer_ptr->internal_handle = payload;
    
    bool use_gpu_path = (_screenCtx->configured_video_format.output_preference == MINIAV_OUTPUT_PREFERENCE_GPU);
    bool gpu_path_successful = false;
    
    // Try GPU path with Metal texture
    if (use_gpu_path && platCtx->metalDevice && platCtx->textureCache) {
        IOSurfaceRef ioSurface = CVPixelBufferGetIOSurface(imageBuffer);
        if (ioSurface) {
            CVMetalTextureRef metalTextureRef = NULL;
            CVReturn err = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, platCtx->textureCache, imageBuffer, NULL,
                MTLPixelFormatBGRA8Unorm, CVPixelBufferGetWidth(imageBuffer), 
                CVPixelBufferGetHeight(imageBuffer), 0, &metalTextureRef);
                
            if (err == kCVReturnSuccess && metalTextureRef) {
                id<MTLTexture> texture = CVMetalTextureGetTexture(metalTextureRef);
                if (texture) {
                    CFRetain(metalTextureRef);
                    payload->native_singular_resource_ptr = metalTextureRef;
                    
                    mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE;
                    mavBuffer_ptr->data.video.info.width = [texture width];
                    mavBuffer_ptr->data.video.info.height = [texture height];
                    mavBuffer_ptr->data.video.info.pixel_format = MINIAV_PIXEL_FORMAT_BGRA32;
                    
                    mavBuffer_ptr->data.video.num_planes = 1;
                    mavBuffer_ptr->data.video.planes[0].data_ptr = (void*)texture;
                    mavBuffer_ptr->data.video.planes[0].width = [texture width];
                    mavBuffer_ptr->data.video.planes[0].height = [texture height];
                    mavBuffer_ptr->data.video.planes[0].stride_bytes = 0;
                    mavBuffer_ptr->data.video.planes[0].offset_bytes = 0;
                    mavBuffer_ptr->data.video.planes[0].subresource_index = 0;
                    
                    gpu_path_successful = true;
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "SCK: GPU Path - Metal texture created from IOSurface.");
                } else {
                    if (metalTextureRef) CFRelease(metalTextureRef);
                }
            }
        }
    }
    
    // Fallback to CPU path
    if (!gpu_path_successful) {
        CVBufferRetain(imageBuffer);
        payload->native_singular_resource_ptr = (void*)imageBuffer;
        
        if (CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: CPU Path - Failed to lock pixel buffer.");
            CVBufferRelease(imageBuffer);
            miniav_free(mavBuffer_ptr);
            miniav_free(payload);
            return;
        }
        
        mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
        mavBuffer_ptr->data.video.info.width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
        mavBuffer_ptr->data.video.info.height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
        mavBuffer_ptr->data.video.info.pixel_format = MINIAV_PIXEL_FORMAT_BGRA32; // ScreenCaptureKit typically provides BGRA
        
        mavBuffer_ptr->data.video.num_planes = 1;
        mavBuffer_ptr->data.video.planes[0].data_ptr = CVPixelBufferGetBaseAddress(imageBuffer);
        mavBuffer_ptr->data.video.planes[0].width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
        mavBuffer_ptr->data.video.planes[0].height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
        mavBuffer_ptr->data.video.planes[0].stride_bytes = (uint32_t)CVPixelBufferGetBytesPerRow(imageBuffer);
        mavBuffer_ptr->data.video.planes[0].offset_bytes = 0;
        mavBuffer_ptr->data.video.planes[0].subresource_index = 0;
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    }
    
    // Set common video properties
    mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_VIDEO;
    mavBuffer_ptr->timestamp_us = CMTimeGetSeconds(timestamp) * 1000000;
    mavBuffer_ptr->data.video.info.frame_rate_numerator = _screenCtx->configured_video_format.frame_rate_numerator;
    mavBuffer_ptr->data.video.info.frame_rate_denominator = _screenCtx->configured_video_format.frame_rate_denominator;
    mavBuffer_ptr->data.video.info.output_preference = _screenCtx->configured_video_format.output_preference;
    mavBuffer_ptr->user_data = _screenCtx->app_callback_user_data;
    
    _screenCtx->app_callback(mavBuffer_ptr, _screenCtx->app_callback_user_data);
}

- (void)processAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!_screenCtx->configured_audio_format.enabled) {
        return; // Audio not requested
    }
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuffer) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to get audio block buffer.");
        return;
    }
    
    MiniAVNativeBufferInternalPayload* payload = NULL;
    MiniAVBuffer* mavBuffer_ptr = NULL;
    
    // Allocate payload and buffer
    payload = (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
    if (!payload) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to allocate audio payload.");
        return;
    }
    
    mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
    if (!mavBuffer_ptr) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to allocate audio buffer.");
        miniav_free(payload);
        return;
    }
    
    payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_AUDIO_SCREEN;
    payload->context_owner = _screenCtx;
    payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
    mavBuffer_ptr->internal_handle = payload;
    
    // Audio is always CPU-based
    CFRetain(sampleBuffer);
    payload->native_singular_resource_ptr = (void*)sampleBuffer;
    
    // Get audio format description
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    
    // Get audio data
    char* audioDataPtr = NULL;
    size_t audioDataSize = 0;
    CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &audioDataSize, &audioDataPtr);
    
    mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_AUDIO;
    mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
    mavBuffer_ptr->timestamp_us = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000;
    
    // Set audio properties
    mavBuffer_ptr->data.audio.info.sample_rate = (uint32_t)asbd->mSampleRate;
    mavBuffer_ptr->data.audio.info.channels = asbd->mChannelsPerFrame;
    mavBuffer_ptr->data.audio.info.sample_format = MINIAV_AUDIO_FORMAT_F32; // ScreenCaptureKit typically provides float32
    mavBuffer_ptr->data.audio.info.samples_per_channel = (uint32_t)(audioDataSize / (asbd->mChannelsPerFrame * sizeof(float)));
    
    mavBuffer_ptr->data.audio.data_ptr = audioDataPtr;
    mavBuffer_ptr->data.audio.data_size_bytes = (uint32_t)audioDataSize;
    mavBuffer_ptr->user_data = _screenCtx->app_callback_user_data;
    
    _screenCtx->app_callback(mavBuffer_ptr, _screenCtx->app_callback_user_data);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    if (error) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Stream stopped with error: %s", [[error localizedDescription] UTF8String]);
    } else {
        miniav_log(MINIAV_LOG_LEVEL_INFO, "SCK: Stream stopped normally.");
    }
}

@end
#endif // HAS_SCREEN_CAPTURE_KIT

// --- Legacy Core Graphics Implementation ---
static void legacy_capture_timer_callback(void* info) {
    MiniAVScreenContext* ctx = (MiniAVScreenContext*)info;
    if (!ctx || !ctx->is_running || !ctx->app_callback) {
        return;
    }
    
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)ctx->platform_ctx;
    
    // Capture screen using Core Graphics
    CGImageRef screenImage = CGDisplayCreateImage(platCtx->displayID);
    if (!screenImage) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CG: Failed to create screen image.");
        return;
    }
    
    // Convert CGImage to buffer
    size_t width = CGImageGetWidth(screenImage);
    size_t height = CGImageGetHeight(screenImage);
    size_t bytesPerRow = CGImageGetBytesPerRow(screenImage);
    
    MiniAVNativeBufferInternalPayload* payload = (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
    MiniAVBuffer* mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
    
    if (!payload || !mavBuffer_ptr) {
        CGImageRelease(screenImage);
        miniav_free(payload);
        miniav_free(mavBuffer_ptr);
        return;
    }
    
    payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN;
    payload->context_owner = ctx;
    payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
    payload->native_singular_resource_ptr = (void*)screenImage; // Store CGImageRef
    mavBuffer_ptr->internal_handle = payload;
    
    // Legacy path is always CPU
    mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_VIDEO;
    mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
    mavBuffer_ptr->timestamp_us = mach_absolute_time() / 1000; // Approximate microseconds
    
    mavBuffer_ptr->data.video.info.width = (uint32_t)width;
    mavBuffer_ptr->data.video.info.height = (uint32_t)height;
    mavBuffer_ptr->data.video.info.pixel_format = CGBitmapInfoToMiniAVPixelFormat(CGImageGetBitmapInfo(screenImage));
    mavBuffer_ptr->data.video.info.frame_rate_numerator = ctx->configured_video_format.frame_rate_numerator;
    mavBuffer_ptr->data.video.info.frame_rate_denominator = ctx->configured_video_format.frame_rate_denominator;
    mavBuffer_ptr->data.video.info.output_preference = MINIAV_OUTPUT_PREFERENCE_CPU;
    
    mavBuffer_ptr->data.video.num_planes = 1;
    mavBuffer_ptr->data.video.planes[0].data_ptr = (void*)CGDataProviderCopyData(CGImageGetDataProvider(screenImage));
    mavBuffer_ptr->data.video.planes[0].width = (uint32_t)width;
    mavBuffer_ptr->data.video.planes[0].height = (uint32_t)height;
    mavBuffer_ptr->data.video.planes[0].stride_bytes = (uint32_t)bytesPerRow;
    mavBuffer_ptr->data.video.planes[0].offset_bytes = 0;
    mavBuffer_ptr->data.video.planes[0].subresource_index = 0;
    
    mavBuffer_ptr->user_data = ctx->app_callback_user_data;
    
    ctx->app_callback(mavBuffer_ptr, ctx->app_callback_user_data);
}

// --- ScreenContextInternalOps Implementations ---

static MiniAVResultCode macos_cg_init_platform(MiniAVScreenContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)ctx->platform_ctx;
    
    @autoreleasepool {
        platCtx->parent_ctx = ctx;
        platCtx->captureQueue = dispatch_queue_create("com.miniav.screen.captureQueue", DISPATCH_QUEUE_SERIAL);
        platCtx->is_capturing = false;
        
        // Initialize Metal for GPU path
        platCtx->metalDevice = MTLCreateSystemDefaultDevice();
        if (platCtx->metalDevice) {
            CVReturn err = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, platCtx->metalDevice, NULL, &platCtx->textureCache);
            if (err != kCVReturnSuccess) {
                miniav_log(MINIAV_LOG_LEVEL_WARN, "CG: Failed to create Metal texture cache. GPU path unavailable.");
                platCtx->textureCache = NULL;
            }
        }
        
        // Get main display ID for legacy fallback
        platCtx->displayID = CGMainDisplayID();
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CG: Platform context initialized.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_destroy_platform(MiniAVScreenContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_SUCCESS;
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)ctx->platform_ctx;
    
    @autoreleasepool {
        // Stop capture if running
        if (platCtx->is_capturing) {
#if HAS_SCREEN_CAPTURE_KIT
            if (@available(macOS 12.3, *)) {
                if (platCtx->scStream) {
                    [platCtx->scStream stopCaptureWithCompletionHandler:^(NSError * _Nullable error) {
                        if (error) {
                            miniav_log(MINIAV_LOG_LEVEL_WARN, "SCK: Error stopping stream: %s", [[error localizedDescription] UTF8String]);
                        }
                    }];
                    platCtx->scStream = nil;
                }
                platCtx->scDelegate = nil;
                platCtx->scStreamConfig = nil;
            } else {
#endif
                if (platCtx->captureTimer) {
                    dispatch_source_cancel(platCtx->captureTimer);
                    platCtx->captureTimer = NULL;
                }
#if HAS_SCREEN_CAPTURE_KIT
            }
#endif
        }
        
        // Clean up Metal resources
        if (platCtx->textureCache) {
            CVMetalTextureCacheFlush(platCtx->textureCache, 0);
            CFRelease(platCtx->textureCache);
            platCtx->textureCache = NULL;
        }
        if (platCtx->metalDevice) {
            [platCtx->metalDevice release];
            platCtx->metalDevice = nil;
        }
        
        if (platCtx->captureQueue) {
            dispatch_release(platCtx->captureQueue);
            platCtx->captureQueue = nil;
        }
    }
    
    miniav_free(platCtx);
    ctx->platform_ctx = NULL;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CG: Platform context destroyed.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_configure(MiniAVScreenContext* ctx, const char* source_id_str, const MiniAVVideoInfo* video_format, const MiniAVAudioInfo* audio_format) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    
    // Store configuration
    if (video_format) {
        ctx->configured_video_format = *video_format;
    }
    if (audio_format) {
        ctx->configured_audio_format = *audio_format;
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CG: Screen capture configured.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_start_capture(MiniAVScreenContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)ctx->platform_ctx;
    
    if (platCtx->is_capturing) {
        miniav_log(MINIAV_LOG_LEVEL_WARN, "CG: Capture already running.");
        return MINIAV_SUCCESS;
    }
    
    @autoreleasepool {
#if HAS_SCREEN_CAPTURE_KIT
        if (@available(macOS 12.3, *)) {
            // Use modern ScreenCaptureKit
            [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content, NSError * _Nullable error) {
                if (error || !content) {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to get shareable content: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
                    return;
                }
                
                SCDisplay* mainDisplay = content.displays.firstObject;
                if (!mainDisplay) {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: No displays available for capture.");
                    return;
                }
                
                SCContentFilter* filter = [[SCContentFilter alloc] initWithDisplay:mainDisplay excludingWindows:@[]];
                
                platCtx->scStreamConfig = [[SCStreamConfiguration alloc] init];
                platCtx->scStreamConfig.width = mainDisplay.width;
                platCtx->scStreamConfig.height = mainDisplay.height;
                platCtx->scStreamConfig.pixelFormat = kCVPixelFormatType_32BGRA;
                platCtx->scStreamConfig.minimumFrameInterval = CMTimeMake(ctx->configured_video_format.frame_rate_denominator, 
                                                                         ctx->configured_video_format.frame_rate_numerator);
                platCtx->scStreamConfig.queueDepth = 3;
                
                // Enable audio if requested
                if (ctx->configured_audio_format.enabled) {
                    platCtx->scStreamConfig.capturesAudio = YES;
                    platCtx->scStreamConfig.sampleRate = ctx->configured_audio_format.sample_rate;
                    platCtx->scStreamConfig.channelCount = ctx->configured_audio_format.channels;
                }
                
                platCtx->scDelegate = [[MiniAVScreenCaptureDelegate alloc] initWithScreenContext:ctx];
                platCtx->scStream = [[SCStream alloc] initWithFilter:filter configuration:platCtx->scStreamConfig delegate:platCtx->scDelegate];
                
                NSError* addOutputError = nil;
                BOOL success = [platCtx->scStream addStreamOutput:platCtx->scDelegate type:SCStreamOutputTypeScreen sampleHandlerQueue:platCtx->captureQueue error:&addOutputError];
                if (!success) {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to add video output: %s", [[addOutputError localizedDescription] UTF8String]);
                    return;
                }
                
                if (ctx->configured_audio_format.enabled) {
                    NSError* addAudioError = nil;
                    BOOL audioSuccess = [platCtx->scStream addStreamOutput:platCtx->scDelegate type:SCStreamOutputTypeAudio sampleHandlerQueue:platCtx->captureQueue error:&addAudioError];
                    if (!audioSuccess) {
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "SCK: Failed to add audio output: %s", [[addAudioError localizedDescription] UTF8String]);
                    }
                }
                
                [platCtx->scStream startCaptureWithCompletionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to start stream: %s", [[error localizedDescription] UTF8String]);
                    } else {
                        platCtx->is_capturing = true;
                        miniav_log(MINIAV_LOG_LEVEL_INFO, "SCK: Screen capture started.");
                    }
                }];
                
                [filter release];
            }];
        } else {
#endif
            // Fallback to legacy Core Graphics capture
            double fps = (double)ctx->configured_video_format.frame_rate_numerator / ctx->configured_video_format.frame_rate_denominator;
            uint64_t interval_ns = (uint64_t)(1000000000.0 / fps);
            
            platCtx->captureTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, platCtx->captureQueue);
            dispatch_source_set_timer(platCtx->captureTimer, DISPATCH_TIME_NOW, interval_ns, interval_ns / 10);
            dispatch_source_set_event_handler_f(platCtx->captureTimer, legacy_capture_timer_callback);
            dispatch_set_context(platCtx->captureTimer, ctx);
            dispatch_resume(platCtx->captureTimer);
            
            platCtx->is_capturing = true;
            miniav_log(MINIAV_LOG_LEVEL_INFO, "CG: Legacy screen capture started.");
#if HAS_SCREEN_CAPTURE_KIT
        }
#endif
    }
    
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_stop_capture(MiniAVScreenContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    CGScreenPlatformContext* platCtx = (CGScreenPlatformContext*)ctx->platform_ctx;
    
    if (!platCtx->is_capturing) {
        return MINIAV_SUCCESS;
    }
    
    @autoreleasepool {
#if HAS_SCREEN_CAPTURE_KIT
        if (@available(macOS 12.3, *)) {
            if (platCtx->scStream) {
                [platCtx->scStream stopCaptureWithCompletionHandler:^(NSError * _Nullable error) {
                    platCtx->is_capturing = false;
                    if (error) {
                        miniav_log(MINIAV_LOG_LEVEL_WARN, "SCK: Error stopping capture: %s", [[error localizedDescription] UTF8String]);
                    } else {
                        miniav_log(MINIAV_LOG_LEVEL_INFO, "SCK: Screen capture stopped.");
                    }
                }];
            }
        } else {
#endif
            if (platCtx->captureTimer) {
                dispatch_source_cancel(platCtx->captureTimer);
                platCtx->captureTimer = NULL;
            }
            platCtx->is_capturing = false;
            miniav_log(MINIAV_LOG_LEVEL_INFO, "CG: Legacy screen capture stopped.");
#if HAS_SCREEN_CAPTURE_KIT
        }
#endif
    }
    
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_release_buffer(MiniAVScreenContext* ctx, void* native_buffer_payload_void) {
    MINIAV_UNUSED(ctx);
    if (!native_buffer_payload_void) return MINIAV_ERROR_INVALID_ARG;
    
    MiniAVNativeBufferInternalPayload* payload = (MiniAVNativeBufferInternalPayload*)native_buffer_payload_void;
    
    @autoreleasepool {
        if (payload->native_singular_resource_ptr) {
            if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN) {
                if (payload->parent_miniav_buffer_ptr && 
                    payload->parent_miniav_buffer_ptr->content_type == MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE) {
                    // GPU Metal texture
                    CVMetalTextureRef metalTextureRef = (CVMetalTextureRef)payload->native_singular_resource_ptr;
                    CFRelease(metalTextureRef);
                } else {
                    // Check if it's CGImageRef (legacy) or CVImageBufferRef (modern)
                    CFTypeID typeID = CFGetTypeID(payload->native_singular_resource_ptr);
                    if (typeID == CGImageGetTypeID()) {
                        CGImageRef image = (CGImageRef)payload->native_singular_resource_ptr;
                        // Also release the copied data
                        if (payload->parent_miniav_buffer_ptr && payload->parent_miniav_buffer_ptr->data.video.planes[0].data_ptr) {
                            CFDataRef data = (CFDataRef)payload->parent_miniav_buffer_ptr->data.video.planes[0].data_ptr;
                            CFRelease(data);
                        }
                        CGImageRelease(image);
                    } else {
                        // Assume CVImageBufferRef
                        CVImageBufferRef imageBuffer = (CVImageBufferRef)payload->native_singular_resource_ptr;
                        CVBufferRelease(imageBuffer);
                    }
                }
            } else if (payload->handle_type == MINIAV_NATIVE_HANDLE_TYPE_AUDIO_SCREEN) {
                // Audio sample buffer
                CMSampleBufferRef sampleBuffer = (CMSampleBufferRef)payload->native_singular_resource_ptr;
                CFRelease(sampleBuffer);
            }
            payload->native_singular_resource_ptr = NULL;
        }
    }
    
    if (payload->parent_miniav_buffer_ptr) {
        miniav_free(payload->parent_miniav_buffer_ptr);
        payload->parent_miniav_buffer_ptr = NULL;
    }
    miniav_free(payload);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_cg_enumerate_sources(MiniAVScreenSourceInfo** sources_out, uint32_t* count_out) {
    if (!sources_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
    *sources_out = NULL;
    *count_out = 0;
    
    @autoreleasepool {
#if HAS_SCREEN_CAPTURE_KIT
        if (@available(macOS 12.3, *)) {
            // Use ScreenCaptureKit for enumeration
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block MiniAVResultCode result = MINIAV_SUCCESS;
            
            [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content, NSError * _Nullable error) {
                if (error || !content) {
                    miniav_log(MINIAV_LOG_LEVEL_ERROR, "SCK: Failed to enumerate sources: %s", error ? [[error localizedDescription] UTF8String] : "Unknown error");
                    result = MINIAV_ERROR_SYSTEM_CALL_FAILED;
                } else {
                    NSUInteger totalCount = [content.displays count] + [content.windows count];
                    if (totalCount > 0) {
                        *count_out = (uint32_t)totalCount;
                        *sources_out = (MiniAVScreenSourceInfo*)miniav_calloc(*count_out, sizeof(MiniAVScreenSourceInfo));
                        
                        uint32_t index = 0;
                        
                        // Add displays
                        for (SCDisplay* display in content.displays) {
                            MiniAVScreenSourceInfo* info = &(*sources_out)[index++];
                            snprintf(info->source_id, MINIAV_SCREEN_SOURCE_ID_MAX_LEN, "display_%u", display.displayID);
                            snprintf(info->name, MINIAV_SCREEN_SOURCE_NAME_MAX_LEN, "Display %u (%dx%d)", 
                                    display.displayID, (int)display.width, (int)display.height);
                            info->type = MINIAV_SCREEN_SOURCE_TYPE_DISPLAY;
                            info->width = (uint32_t)display.width;
                            info->height = (uint32_t)display.height;
                        }
                        
                        // Add windows (limit to reasonable number)
                        for (SCWindow* window in content.windows) {
                            if (index >= *count_out) break;
                            if (window.frame.size.width < 100 || window.frame.size.height < 100) continue; // Skip very small windows
                            
                            MiniAVScreenSourceInfo* info = &(*sources_out)[index++];
                            snprintf(info->source_id, MINIAV_SCREEN_SOURCE_ID_MAX_LEN, "window_%u", window.windowID);
                            snprintf(info->name, MINIAV_SCREEN_SOURCE_NAME_MAX_LEN, "%.100s", [window.title UTF8String] ?: "Untitled Window");
                            info->type = MINIAV_SCREEN_SOURCE_TYPE_WINDOW;
                            info->width = (uint32_t)window.frame.size.width;
                            info->height = (uint32_t)window.frame.size.height;
                        }
                        
                        *count_out = index; // Update count to actual items added
                    }
                }
                dispatch_semaphore_signal(semaphore);
            }];
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            dispatch_release(semaphore);
            return result;
        } else {
#endif
            // Fallback to Core Graphics display enumeration
            uint32_t displayCount;
            CGDirectDisplayID* displays = NULL;
            
            if (CGGetActiveDisplayList(0, NULL, &displayCount) != kCGErrorSuccess) {
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "CG: Failed to get display count.");
                return MINIAV_ERROR_SYSTEM_CALL_FAILED;
            }
            
            if (displayCount == 0) {
                return MINIAV_SUCCESS;
            }
            
            displays = (CGDirectDisplayID*)miniav_calloc(displayCount, sizeof(CGDirectDisplayID));
            if (!displays) {
                return MINIAV_ERROR_OUT_OF_MEMORY;
            }
            
            if (CGGetActiveDisplayList(displayCount, displays, &displayCount) != kCGErrorSuccess) {
                miniav_free(displays);
                return MINIAV_ERROR_SYSTEM_CALL_FAILED;
            }
            
            *count_out = displayCount;
            *sources_out = (MiniAVScreenSourceInfo*)miniav_calloc(*count_out, sizeof(MiniAVScreenSourceInfo));
            if (!*sources_out) {
                miniav_free(displays);
                *count_out = 0;
                return MINIAV_ERROR_OUT_OF_MEMORY;
            }
            
            for (uint32_t i = 0; i < displayCount; i++) {
                MiniAVScreenSourceInfo* info = &(*sources_out)[i];
                snprintf(info->source_id, MINIAV_SCREEN_SOURCE_ID_MAX_LEN, "display_%u", displays[i]);
                snprintf(info->name, MINIAV_SCREEN_SOURCE_NAME_MAX_LEN, "Display %u", displays[i]);
                info->type = MINIAV_SCREEN_SOURCE_TYPE_DISPLAY;
                
                CGRect bounds = CGDisplayBounds(displays[i]);
                info->width = (uint32_t)bounds.size.width;
                info->height = (uint32_t)bounds.size.height;
            }
            
            miniav_free(displays);
#if HAS_SCREEN_CAPTURE_KIT
        }
#endif
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CG: Enumerated %u screen sources.", *count_out);
    return MINIAV_SUCCESS;
}

// --- Global Ops Table ---
const ScreenContextInternalOps g_screen_ops_macos_cg = {
    .init_platform = macos_cg_init_platform,
    .destroy_platform = macos_cg_destroy_platform,
    .configure = macos_cg_configure,
    .start_capture = macos_cg_start_capture,
    .stop_capture = macos_cg_stop_capture,
    .release_buffer = macos_cg_release_buffer,
    .enumerate_sources = macos_cg_enumerate_sources,
};

// --- Platform Init for Selection ---
MiniAVResultCode miniav_screen_context_platform_init_macos_cg(MiniAVScreenContext* ctx) {
    if (!ctx) return MINIAV_ERROR_INVALID_ARG;
    
    ctx->ops = &g_screen_ops_macos_cg;
    ctx->platform_ctx = miniav_calloc(1, sizeof(CGScreenPlatformContext));
    if (!ctx->platform_ctx) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "CG: Failed to allocate platform context.");
        ctx->ops = NULL;
        return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "CG: Screen capture platform selected.");
    return MINIAV_SUCCESS;
}