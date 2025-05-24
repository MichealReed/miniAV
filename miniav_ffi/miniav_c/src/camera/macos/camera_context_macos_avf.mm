#include "camera_context_macos_avf.h"
#include "../../common/miniav_logging.h" // For miniav_log
#include "../../common/miniav_utils.h"   // For miniav_calloc, miniav_free, etc.
#include "../../../include/miniav_buffer.h" // For MiniAVNativeBufferInternalPayload, MiniAVBufferContentType

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h> // For Metal types

// --- Platform Specific Context ---
typedef struct AVFPlatformContext {
    AVCaptureSession *captureSession;
    AVCaptureDeviceInput *deviceInput;
    AVCaptureVideoDataOutput *videoDataOutput;
    dispatch_queue_t sessionQueue;
    dispatch_queue_t videoOutputQueue;
    MiniAVCameraContext* parent_ctx;

    // Metal specific objects for GPU path
    id<MTLDevice> metalDevice;
    CVMetalTextureCacheRef textureCache;
} AVFPlatformContext;


// --- Helper Functions (Static, internal to this file) ---
static MiniAVPixelFormat FourCCToMiniAVPixelFormat(OSType fourCC) {
    switch (fourCC) {
        // --- Standard RGB Formats (8-bit) ---
        case kCVPixelFormatType_24RGB:          return MINIAV_PIXEL_FORMAT_RGB24;
        case kCVPixelFormatType_24BGR:          return MINIAV_PIXEL_FORMAT_BGR24;
        case kCVPixelFormatType_32RGBA:         return MINIAV_PIXEL_FORMAT_RGBA32;
        case kCVPixelFormatType_32BGRA:         return MINIAV_PIXEL_FORMAT_BGRA32;
        case kCVPixelFormatType_32ARGB:         return MINIAV_PIXEL_FORMAT_ARGB32;
        case kCVPixelFormatType_32ABGR:         return MINIAV_PIXEL_FORMAT_ABGR32;
        
        // --- Standard YUV Formats (8-bit) ---
        case kCVPixelFormatType_420YpCbCr8Planar:           return MINIAV_PIXEL_FORMAT_I420;
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:  return MINIAV_PIXEL_FORMAT_I420; // Full range variant
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: return MINIAV_PIXEL_FORMAT_NV12;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:  return MINIAV_PIXEL_FORMAT_NV12; // Full range variant
        case kCVPixelFormatType_422YpCbCr8_yuvs:            return MINIAV_PIXEL_FORMAT_YUY2; // YUYV
        case kCVPixelFormatType_422YpCbCr8:                 return MINIAV_PIXEL_FORMAT_UYVY; // UYVY (2vuy)
        case kCVPixelFormatType_422YpCbCr8FullRange:        return MINIAV_PIXEL_FORMAT_YUY2; // Full range YUYV
        
        // --- High-End RGB Formats ---
        case kCVPixelFormatType_30RGB:                      return MINIAV_PIXEL_FORMAT_RGB30;
        case kCVPixelFormatType_48RGB:                      return MINIAV_PIXEL_FORMAT_RGB48;
        case kCVPixelFormatType_64ARGB:                     return MINIAV_PIXEL_FORMAT_RGBA64;
        case kCVPixelFormatType_64RGBAHalf:                 return MINIAV_PIXEL_FORMAT_RGBA64_HALF;
        case kCVPixelFormatType_128RGBAFloat:               return MINIAV_PIXEL_FORMAT_RGBA128_FLOAT;
        case kCVPixelFormatType_30RGBLEPackedWideGamut:     return MINIAV_PIXEL_FORMAT_RGB30; // Wide gamut variant
        case kCVPixelFormatType_ARGB2101010LEPacked:        return MINIAV_PIXEL_FORMAT_RGB30; // 10-bit with alpha
        
        // --- High-End YUV Formats ---
        case kCVPixelFormatType_422YpCbCr10:                return MINIAV_PIXEL_FORMAT_YUV422_10BIT;
        case kCVPixelFormatType_444YpCbCr10:                return MINIAV_PIXEL_FORMAT_YUV444_10BIT;
        case kCVPixelFormatType_422YpCbCr16:                return MINIAV_PIXEL_FORMAT_YUV422_10BIT; // 10-16 bit variant
        case kCVPixelFormatType_4444YpCbCrA8:               return MINIAV_PIXEL_FORMAT_YUV444_10BIT; // 4:4:4:4 with alpha
        case kCVPixelFormatType_4444AYpCbCr8:               return MINIAV_PIXEL_FORMAT_YUV444_10BIT; // Alpha + 4:4:4
        case kCVPixelFormatType_4444AYpCbCr16:              return MINIAV_PIXEL_FORMAT_YUV444_10BIT; // 16-bit alpha + 4:4:4
        
        // --- Lossless formats (typically from screen capture) ---
        case kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange: 
            return MINIAV_PIXEL_FORMAT_YUV420_10BIT;
        case kCVPixelFormatType_Lossless_64RGBAHalf:        return MINIAV_PIXEL_FORMAT_RGBA64_HALF;
        
        // --- Grayscale Formats ---
        case kCVPixelFormatType_OneComponent8:              return MINIAV_PIXEL_FORMAT_GRAY8;
        case kCVPixelFormatType_16Gray:                     return MINIAV_PIXEL_FORMAT_GRAY16;
        case kCVPixelFormatType_OneComponent16Half:         return MINIAV_PIXEL_FORMAT_GRAY16; // Half-precision
        case kCVPixelFormatType_OneComponent32Float:        return MINIAV_PIXEL_FORMAT_GRAY16; // Float (map to 16-bit)
        case kCVPixelFormatType_32AlphaGray:                return MINIAV_PIXEL_FORMAT_GRAY16; // 16-bit gray with alpha
        
        // --- Two-component formats (could be used for specialized workflows) ---
        case kCVPixelFormatType_TwoComponent8:              return MINIAV_PIXEL_FORMAT_GRAY8;  // Map to gray for simplicity
        case kCVPixelFormatType_TwoComponent16Half:         return MINIAV_PIXEL_FORMAT_GRAY16;
        case kCVPixelFormatType_TwoComponent32Float:        return MINIAV_PIXEL_FORMAT_GRAY16;
        
        // --- Bayer Formats (Professional Cameras) ---
        case kCVPixelFormatType_14Bayer_GRBG:               return MINIAV_PIXEL_FORMAT_BAYER_GRBG16;
        case kCVPixelFormatType_14Bayer_RGGB:               return MINIAV_PIXEL_FORMAT_BAYER_RGGB16;
        case kCVPixelFormatType_14Bayer_BGGR:               return MINIAV_PIXEL_FORMAT_BAYER_BGGR16;
        case kCVPixelFormatType_14Bayer_GBRG:               return MINIAV_PIXEL_FORMAT_BAYER_GBRG16;
        
        // --- Legacy/Indexed Formats (very rare, mainly for legacy compatibility) ---
        case kCVPixelFormatType_1Monochrome:                return MINIAV_PIXEL_FORMAT_GRAY8;  // Map to gray
        case kCVPixelFormatType_8Indexed:                   return MINIAV_PIXEL_FORMAT_GRAY8;  // Map to gray
        case kCVPixelFormatType_8IndexedGray_WhiteIsZero:   return MINIAV_PIXEL_FORMAT_GRAY8;
        
        // --- 16-bit RGB formats ---
        case kCVPixelFormatType_16BE555:                    return MINIAV_PIXEL_FORMAT_RGB24;  // Map to 24-bit
        case kCVPixelFormatType_16LE555:                    return MINIAV_PIXEL_FORMAT_RGB24;
        case kCVPixelFormatType_16LE5551:                   return MINIAV_PIXEL_FORMAT_RGBA32; // Has alpha bit
        case kCVPixelFormatType_16BE565:                    return MINIAV_PIXEL_FORMAT_RGB24;
        case kCVPixelFormatType_16LE565:                    return MINIAV_PIXEL_FORMAT_RGB24;
        
        default: {
            // Enhanced logging with format source detection
            char fourCCStr[5] = {0};
            *(OSType*)fourCCStr = CFSwapInt32HostToBig(fourCC);
            
            bool is_printable = (isprint(fourCCStr[0]) && isprint(fourCCStr[1]) && 
                               isprint(fourCCStr[2]) && isprint(fourCCStr[3]));
            
            if (is_printable) {
                // Detect likely source based on format characteristics
                const char* likely_source = "unknown";
                if (strstr(fourCCStr, "Lossless") || 
                    (fourCC >= kCVPixelFormatType_30RGB && fourCC <= kCVPixelFormatType_128RGBAFloat)) {
                    likely_source = "screen capture/professional video";
                } else if (fourCC >= kCVPixelFormatType_14Bayer_GRBG && fourCC <= kCVPixelFormatType_14Bayer_GBRG) {
                    likely_source = "professional camera RAW";
                } else if (fourCC >= kCVPixelFormatType_420YpCbCr8Planar && fourCC <= kCVPixelFormatType_422YpCbCr8FullRange) {
                    likely_source = "video camera";
                }
                
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: Unknown FourCC: %u ('%.4s') - likely from %s", 
                          fourCC, fourCCStr, likely_source);
            } else {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: Unknown FourCC: %u (non-printable)", fourCC);
            }
            return MINIAV_PIXEL_FORMAT_UNKNOWN;
        }
    }
}

static OSType MiniAVPixelFormatToFourCC(MiniAVPixelFormat format) {
    switch (format) {
        // --- Standard RGB Formats (8-bit) ---
        case MINIAV_PIXEL_FORMAT_RGB24:          return kCVPixelFormatType_24RGB;
        case MINIAV_PIXEL_FORMAT_BGR24:          return kCVPixelFormatType_24BGR;
        case MINIAV_PIXEL_FORMAT_RGBA32:         return kCVPixelFormatType_32RGBA;
        case MINIAV_PIXEL_FORMAT_BGRA32:         return kCVPixelFormatType_32BGRA;
        case MINIAV_PIXEL_FORMAT_ARGB32:         return kCVPixelFormatType_32ARGB;
        case MINIAV_PIXEL_FORMAT_ABGR32:         return kCVPixelFormatType_32ABGR;
        
        // --- Padding formats (may not have direct Core Video equivalents) ---
        case MINIAV_PIXEL_FORMAT_RGBX32:         return 'RGBX'; // May not be directly supported
        case MINIAV_PIXEL_FORMAT_BGRX32:         return 'BGRX'; // May not be directly supported  
        case MINIAV_PIXEL_FORMAT_XRGB32:         return 'XRGB'; // May not be directly supported
        case MINIAV_PIXEL_FORMAT_XBGR32:         return 'XBGR'; // May not be directly supported
        
        // --- Standard YUV Formats (8-bit) ---
        case MINIAV_PIXEL_FORMAT_I420:           return kCVPixelFormatType_420YpCbCr8Planar;
        case MINIAV_PIXEL_FORMAT_YV12:           return kCVPixelFormatType_420YpCbCr8Planar; // No direct YV12, use I420
        case MINIAV_PIXEL_FORMAT_NV12:           return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        case MINIAV_PIXEL_FORMAT_NV21:           return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; // No direct NV21
        case MINIAV_PIXEL_FORMAT_YUY2:           return kCVPixelFormatType_422YpCbCr8_yuvs; // YUYV
        case MINIAV_PIXEL_FORMAT_UYVY:           return kCVPixelFormatType_422YpCbCr8; // UYVY (2vuy)
        
        // --- High-End RGB Formats ---
        case MINIAV_PIXEL_FORMAT_RGB30:          return kCVPixelFormatType_30RGB;
        case MINIAV_PIXEL_FORMAT_RGB48:          return kCVPixelFormatType_48RGB;
        case MINIAV_PIXEL_FORMAT_RGBA64:         return kCVPixelFormatType_64ARGB;
        case MINIAV_PIXEL_FORMAT_RGBA64_HALF:    return kCVPixelFormatType_64RGBAHalf;
        case MINIAV_PIXEL_FORMAT_RGBA128_FLOAT:  return kCVPixelFormatType_128RGBAFloat;
        
        // --- High-End YUV Formats ---
        case MINIAV_PIXEL_FORMAT_YUV420_10BIT:   return kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange;
        case MINIAV_PIXEL_FORMAT_YUV422_10BIT:   return kCVPixelFormatType_422YpCbCr10;
        case MINIAV_PIXEL_FORMAT_YUV444_10BIT:   return kCVPixelFormatType_444YpCbCr10;
        
        // --- Grayscale Formats ---
        case MINIAV_PIXEL_FORMAT_GRAY8:          return kCVPixelFormatType_OneComponent8;
        case MINIAV_PIXEL_FORMAT_GRAY16:         return kCVPixelFormatType_16Gray;
        
        // --- Bayer Formats ---
        case MINIAV_PIXEL_FORMAT_BAYER_GRBG8:    return kCVPixelFormatType_14Bayer_GRBG; // Map 8-bit to 14-bit
        case MINIAV_PIXEL_FORMAT_BAYER_RGGB8:    return kCVPixelFormatType_14Bayer_RGGB;
        case MINIAV_PIXEL_FORMAT_BAYER_BGGR8:    return kCVPixelFormatType_14Bayer_BGGR;
        case MINIAV_PIXEL_FORMAT_BAYER_GBRG8:    return kCVPixelFormatType_14Bayer_GBRG;
        case MINIAV_PIXEL_FORMAT_BAYER_GRBG16:   return kCVPixelFormatType_14Bayer_GRBG;
        case MINIAV_PIXEL_FORMAT_BAYER_RGGB16:   return kCVPixelFormatType_14Bayer_RGGB;
        case MINIAV_PIXEL_FORMAT_BAYER_BGGR16:   return kCVPixelFormatType_14Bayer_BGGR;
        case MINIAV_PIXEL_FORMAT_BAYER_GBRG16:   return kCVPixelFormatType_14Bayer_GBRG;
        
        default:
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                      "AVF: No Core Video FourCC mapping for MiniAVPixelFormat %d", format);
            return 0;
    }
}

// Enhanced Metal Pixel Format mapping with better coverage
static MTLPixelFormat CVPixelFormatToMTLPixelFormat(OSType cvPixelFormat) {
    switch (cvPixelFormat) {
        // --- Standard RGB Formats ---
        case kCVPixelFormatType_32BGRA:         return MTLPixelFormatBGRA8Unorm;
        case kCVPixelFormatType_32RGBA:         return MTLPixelFormatRGBA8Unorm;
        case kCVPixelFormatType_32ARGB:         return MTLPixelFormatBGRA8Unorm; // Need swizzling
        case kCVPixelFormatType_32ABGR:         return MTLPixelFormatRGBA8Unorm; // Need swizzling
        case kCVPixelFormatType_24RGB:          return MTLPixelFormatInvalid;    // No direct 24-bit support
        case kCVPixelFormatType_24BGR:          return MTLPixelFormatInvalid;    // No direct 24-bit support
        
        // --- High-End RGB Formats ---
        case kCVPixelFormatType_30RGB:          return MTLPixelFormatBGR10A2Unorm;
        case kCVPixelFormatType_64ARGB:         return MTLPixelFormatRGBA16Unorm;
        case kCVPixelFormatType_64RGBAHalf:     return MTLPixelFormatRGBA16Float;
        case kCVPixelFormatType_128RGBAFloat:   return MTLPixelFormatRGBA32Float;
        case kCVPixelFormatType_48RGB:          return MTLPixelFormatInvalid;    // No direct 48-bit RGB
        
        // --- Grayscale Formats ---
        case kCVPixelFormatType_OneComponent8:  return MTLPixelFormatR8Unorm;
        case kCVPixelFormatType_16Gray:         return MTLPixelFormatR16Unorm;
        case kCVPixelFormatType_OneComponent16Half: return MTLPixelFormatR16Float;
        case kCVPixelFormatType_OneComponent32Float: return MTLPixelFormatR32Float;
        
        // --- Two-component formats ---
        case kCVPixelFormatType_TwoComponent8:  return MTLPixelFormatRG8Unorm;
        case kCVPixelFormatType_TwoComponent16Half: return MTLPixelFormatRG16Float;
        case kCVPixelFormatType_TwoComponent32Float: return MTLPixelFormatRG32Float;
        
        // --- YUV Formats (require multi-plane setup) ---
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // NV12: Plane 0 (Y) = R8Unorm, Plane 1 (UV) = RG8Unorm
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: NV12 format requires multi-plane Metal texture setup");
            return MTLPixelFormatInvalid; // Indicates special handling needed
            
        case kCVPixelFormatType_420YpCbCr8Planar:
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            // I420: 3 planes, all R8Unorm
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: I420 format requires 3-plane Metal texture setup");
            return MTLPixelFormatInvalid; // Indicates special handling needed
            
        case kCVPixelFormatType_422YpCbCr8:
        case kCVPixelFormatType_422YpCbCr8_yuvs:
            
        // --- 10-bit and specialized formats ---
        case kCVPixelFormatType_422YpCbCr10:
        case kCVPixelFormatType_444YpCbCr10:
        case kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange:
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: 10-bit YUV format requires specialized Metal texture setup");
            return MTLPixelFormatInvalid; // Indicates special handling needed
            
        // --- Bayer formats ---
        case kCVPixelFormatType_14Bayer_GRBG:
        case kCVPixelFormatType_14Bayer_RGGB:
        case kCVPixelFormatType_14Bayer_BGGR:
        case kCVPixelFormatType_14Bayer_GBRG:
            // Bayer could be treated as R16Unorm with demosaicing shader
            return MTLPixelFormatR16Unorm;
            
        default: {
            char fourCCStr[5] = {0};
            *(OSType*)fourCCStr = CFSwapInt32HostToBig(cvPixelFormat);
            if (isprint(fourCCStr[0]) && isprint(fourCCStr[1]) && 
                isprint(fourCCStr[2]) && isprint(fourCCStr[3])) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: No Metal pixel format mapping for CVPixelFormat '%.4s' (%u)", 
                          fourCCStr, cvPixelFormat);
            } else {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: No Metal pixel format mapping for CVPixelFormat %u", cvPixelFormat);
            }
            return MTLPixelFormatInvalid;
        }
    }
}

// --- AVFoundation Delegate for Video Output ---
@interface MiniAVCaptureDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
{
    MiniAVCameraContext* _miniAVCtx; 
}
- (instancetype)initWithMiniAVContext:(MiniAVCameraContext*)ctx;
@end

@implementation MiniAVCaptureDelegate

- (instancetype)initWithMiniAVContext:(MiniAVCameraContext*)ctx {
    self = [super init];
    if (self) {
        _miniAVCtx = ctx; // Weak reference, parent MiniAVCameraContext owns this delegate's lifecycle indirectly
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!_miniAVCtx || !_miniAVCtx->app_callback || !_miniAVCtx->is_running || !_miniAVCtx->platform_ctx) {
        return;
    }

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to get image buffer from sample buffer.");
        return;
    }

    AVFPlatformContext* platCtx = (AVFPlatformContext*)_miniAVCtx->platform_ctx;
    MiniAVNativeBufferInternalPayload* payload = NULL;
    MiniAVBuffer* mavBuffer_ptr = NULL;

    payload = (MiniAVNativeBufferInternalPayload*)miniav_calloc(1, sizeof(MiniAVNativeBufferInternalPayload));
    if (!payload) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to allocate MiniAVNativeBufferInternalPayload.");
        return;
    }

    mavBuffer_ptr = (MiniAVBuffer*)miniav_calloc(1, sizeof(MiniAVBuffer));
    if (!mavBuffer_ptr) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to allocate MiniAVBuffer.");
        miniav_free(payload);
        return;
    }
    
    payload->handle_type = MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA;
    payload->context_owner = _miniAVCtx;
    payload->parent_miniav_buffer_ptr = mavBuffer_ptr;
    mavBuffer_ptr->internal_handle = payload;

    bool use_gpu_path = (_miniAVCtx->configured_video_format.output_preference == MINIAV_OUTPUT_PREFERENCE_GPU);
    bool gpu_path_successful = false;

    if (use_gpu_path && platCtx->metalDevice && platCtx->textureCache) {
        size_t frame_width = CVPixelBufferGetWidth(imageBuffer);
        size_t frame_height = CVPixelBufferGetHeight(imageBuffer);
        OSType cv_pixel_format_type = CVPixelBufferGetPixelFormatType(imageBuffer);
        MTLPixelFormat mtlPixelFormat = CVPixelFormatToMTLPixelFormat(cv_pixel_format_type);

        // For planar formats like NV12, this simple mapping won't work directly for a single texture.
        // It would require creating separate textures for Y and UV planes.
        // This example prioritizes common non-planar formats for simplicity.
        if (mtlPixelFormat != MTLPixelFormatInvalid && !CVPixelBufferIsPlanar(imageBuffer)) {
            CVMetalTextureRef metalTextureRef = NULL;
            CVReturn err = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, platCtx->textureCache, imageBuffer, NULL,
                mtlPixelFormat, frame_width, frame_height, 0, &metalTextureRef);

            if (err == kCVReturnSuccess && metalTextureRef) {
                id<MTLTexture> texture = CVMetalTextureGetTexture(metalTextureRef);
                if (texture) {
                    CFRetain(metalTextureRef); // Retain the CVMetalTextureRef for the payload
                    payload->native_singular_resource_ptr = metalTextureRef;

                    mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE;
                    mavBuffer_ptr->data.video.info.width = [texture width];
                    mavBuffer_ptr->data.video.info.height = [texture height];
                    mavBuffer_ptr->data.video.info.pixel_format = FourCCToMiniAVPixelFormat(cv_pixel_format_type);
                    
                    // Use unified plane structure for GPU
                    mavBuffer_ptr->data.video.num_planes = 1;
                    mavBuffer_ptr->data.video.planes[0].data_ptr = (void*)texture; // Pass non-retained id<MTLTexture>
                    mavBuffer_ptr->data.video.planes[0].width = [texture width];
                    mavBuffer_ptr->data.video.planes[0].height = [texture height];
                    mavBuffer_ptr->data.video.planes[0].stride_bytes = 0; // Not applicable for GPU texture
                    mavBuffer_ptr->data.video.planes[0].offset_bytes = 0;
                    mavBuffer_ptr->data.video.planes[0].subresource_index = 0;
                    
                    gpu_path_successful = true;
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: GPU Path - Metal texture created.");
                } else {
                    miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: GPU Path - CVMetalTextureGetTexture failed.");
                    if (metalTextureRef) CFRelease(metalTextureRef); // Was created but GetTexture failed
                }
            } else {
                miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: GPU Path - CVMetalTextureCacheCreateTextureFromImage failed (err: %d). Falling back to CPU.", err);
            }
        } else {
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: GPU Path - Source CVPixelBuffer format (%.4s) or planar status not suitable for simple Metal texture. Falling back to CPU.", (char*)&cv_pixel_format_type);
        }
    }

    if (!gpu_path_successful) {
        miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Using CPU path for buffer.");
        CVBufferRetain(imageBuffer); // Retain for CPU path
        payload->native_singular_resource_ptr = (void*)imageBuffer;

        if (CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: CPU Path - Failed to lock pixel buffer.");
            CVBufferRelease(imageBuffer); // Release the retained buffer
            miniav_free(mavBuffer_ptr);
            miniav_free(payload);
            return;
        }
        
        mavBuffer_ptr->content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU;
        mavBuffer_ptr->data.video.info.width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
        mavBuffer_ptr->data.video.info.height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
        mavBuffer_ptr->data.video.info.pixel_format = FourCCToMiniAVPixelFormat(CVPixelBufferGetPixelFormatType(imageBuffer));

        if (CVPixelBufferIsPlanar(imageBuffer)) {
            size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);
            mavBuffer_ptr->data.video.num_planes = (uint32_t)planeCount;
            for (size_t i = 0; i < planeCount && i < MINIAV_VIDEO_FORMAT_MAX_PLANES; ++i) {
                mavBuffer_ptr->data.video.planes[i].data_ptr = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i);
                mavBuffer_ptr->data.video.planes[i].width = (uint32_t)CVPixelBufferGetWidthOfPlane(imageBuffer, i);
                mavBuffer_ptr->data.video.planes[i].height = (uint32_t)CVPixelBufferGetHeightOfPlane(imageBuffer, i);
                mavBuffer_ptr->data.video.planes[i].stride_bytes = (uint32_t)CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i);
                mavBuffer_ptr->data.video.planes[i].offset_bytes = 0;
                mavBuffer_ptr->data.video.planes[i].subresource_index = 0;
            }
        } else {
            mavBuffer_ptr->data.video.num_planes = 1;
            mavBuffer_ptr->data.video.planes[0].data_ptr = CVPixelBufferGetBaseAddress(imageBuffer);
            mavBuffer_ptr->data.video.planes[0].width = (uint32_t)CVPixelBufferGetWidth(imageBuffer);
            mavBuffer_ptr->data.video.planes[0].height = (uint32_t)CVPixelBufferGetHeight(imageBuffer);
            mavBuffer_ptr->data.video.planes[0].stride_bytes = (uint32_t)CVPixelBufferGetBytesPerRow(imageBuffer);
            mavBuffer_ptr->data.video.planes[0].offset_bytes = 0;
            mavBuffer_ptr->data.video.planes[0].subresource_index = 0;
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    }

    mavBuffer_ptr->type = MINIAV_BUFFER_TYPE_VIDEO;
    mavBuffer_ptr->timestamp_us = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000;
    mavBuffer_ptr->data.video.info.frame_rate_numerator = _miniAVCtx->configured_video_format.frame_rate_numerator;
    mavBuffer_ptr->data.video.info.frame_rate_denominator = _miniAVCtx->configured_video_format.frame_rate_denominator;
    mavBuffer_ptr->data.video.info.output_preference = _miniAVCtx->configured_video_format.output_preference;
    mavBuffer_ptr->user_data = _miniAVCtx->app_callback_user_data;

    _miniAVCtx->app_callback(mavBuffer_ptr, _miniAVCtx->app_callback_user_data);
}

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: Dropped a video frame.");
}
@end


// --- CameraContextInternalOps Implementations ---

static MiniAVResultCode macos_avf_init_platform(MiniAVCameraContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;
    
    @autoreleasepool {
        platCtx->captureSession = [[AVCaptureSession alloc] init];
        if (!platCtx->captureSession) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to create AVCaptureSession.");
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        platCtx->sessionQueue = dispatch_queue_create("com.miniav.sessionQueue", DISPATCH_QUEUE_SERIAL);
        platCtx->videoOutputQueue = dispatch_queue_create("com.miniav.videoOutputQueue", DISPATCH_QUEUE_SERIAL);
        platCtx->parent_ctx = ctx;

        // Initialize Metal device and texture cache
        platCtx->metalDevice = MTLCreateSystemDefaultDevice();
        if (!platCtx->metalDevice) {
            miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: Failed to create Metal device. GPU path will be unavailable.");
        } else {
            CVReturn err = CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, platCtx->metalDevice, NULL, &platCtx->textureCache);
            if (err != kCVReturnSuccess) {
                miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to create Metal texture cache (err: %d). GPU path will be unavailable.", err);
                platCtx->textureCache = NULL; // Ensure it's NULL
                // [platCtx->metalDevice release]; // Keep device for now, or release if only for cache
                // platCtx->metalDevice = nil;
            } else {
                 miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Metal device and texture cache initialized for GPU path.");
            }
        }
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Platform context initialized.");
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_destroy_platform(MiniAVCameraContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_SUCCESS;
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;

    @autoreleasepool {
        if (platCtx->captureSession && [platCtx->captureSession isRunning]) {
            [platCtx->captureSession stopRunning];
        }
        if (platCtx->deviceInput) {
            if(platCtx->captureSession) [platCtx->captureSession removeInput:platCtx->deviceInput];
            [platCtx->deviceInput release];
            platCtx->deviceInput = nil;
        }
        if (platCtx->videoDataOutput) {
             if(platCtx->captureSession) [platCtx->captureSession removeOutput:platCtx->videoDataOutput];
            [platCtx->videoDataOutput release];
            platCtx->videoDataOutput = nil;
        }
        if (platCtx->captureSession) {
            [platCtx->captureSession release];
            platCtx->captureSession = nil;
        }
        if (platCtx->sessionQueue) {
            dispatch_release(platCtx->sessionQueue);
            platCtx->sessionQueue = nil;
        }
        if (platCtx->videoOutputQueue) {
            dispatch_release(platCtx->videoOutputQueue);
            platCtx->videoOutputQueue = nil;
        }
        // Release Metal objects
        if (platCtx->textureCache) {
            CVMetalTextureCacheFlush(platCtx->textureCache, 0);
            CFRelease(platCtx->textureCache);
            platCtx->textureCache = NULL;
        }
        if (platCtx->metalDevice) {
            [platCtx->metalDevice release]; // Metal device was retained by MTLCreateSystemDefaultDevice implicitly
            platCtx->metalDevice = nil;
        }
    }
    miniav_free(platCtx);
    ctx->platform_ctx = NULL;
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Platform context destroyed.");
    return MINIAV_SUCCESS;
}

static BOOL macos_avf_validate_format_support(AVCaptureDevice *device, const MiniAVVideoInfo* format_req) {
    if (!device || !format_req) return NO;
    
    float requested_fps = (format_req->frame_rate_denominator > 0) ? 
                         (float)format_req->frame_rate_numerator / format_req->frame_rate_denominator : 0;
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
              "AVF: Validating format: %dx%d, PixelFormat:%d, FPS:%.2f", 
              format_req->width, format_req->height, format_req->pixel_format, requested_fps);
    
    for (AVCaptureDeviceFormat *avFormat in device.formats) {
        CMFormatDescriptionRef desc = avFormat.formatDescription;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
        OSType fourCC = CMFormatDescriptionGetMediaSubType(desc);
        MiniAVPixelFormat currentMiniAVFormat = FourCCToMiniAVPixelFormat(fourCC);
        
        char fourCCStr[5] = {0};
        *(OSType*)fourCCStr = CFSwapInt32HostToBig(fourCC);
        
        // Check exact match for resolution and pixel format
        if (dimensions.width == format_req->width && 
            dimensions.height == format_req->height &&
            currentMiniAVFormat == format_req->pixel_format) {
            
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                      "AVF: Found matching format: %dx%d, FourCC: '%.4s', PixelFormat: %d", 
                      dimensions.width, dimensions.height, fourCCStr, currentMiniAVFormat);
            
            // Check frame rate support
            for (AVFrameRateRange *range in avFormat.videoSupportedFrameRateRanges) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: Checking FPS range: %.2f - %.2f, requested: %.2f", 
                          range.minFrameRate, range.maxFrameRate, requested_fps);
                
                BOOL fps_match = NO;
                if (requested_fps == 0 && range.maxFrameRate > 0) {
                    fps_match = YES; // Zero FPS means "any supported rate"
                } else if (requested_fps > 0) {
                    // **IMPORTANT FIX: Add tolerance for floating point comparison**
                    float tolerance = 0.1f; // Allow 0.1 FPS difference
                    if (requested_fps >= (range.minFrameRate - tolerance) && 
                        requested_fps <= (range.maxFrameRate + tolerance)) {
                        fps_match = YES;
                    }
                }
                
                if (fps_match) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Format validation SUCCESS - %dx%d, PixelFormat:%d, FPS:%.2f", 
                              format_req->width, format_req->height, format_req->pixel_format, requested_fps);
                    return YES; // Format is supported
                }
            }
        }
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
              "AVF: Format validation failed - %dx%d, PixelFormat:%d, FPS:%.2f not supported", 
              format_req->width, format_req->height, format_req->pixel_format, requested_fps);
    return NO;
}

static MiniAVResultCode macos_avf_configure(MiniAVCameraContext* ctx, const char* device_id_str, const MiniAVVideoInfo* format_req) {
    if (!ctx || !ctx->platform_ctx || !format_req) return MINIAV_ERROR_INVALID_ARG;
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;
    MiniAVResultCode result = MINIAV_SUCCESS;

    @autoreleasepool {
        AVCaptureDevice *selectedDevice = nil;
        if (device_id_str && strlen(device_id_str) > 0) {
            selectedDevice = [AVCaptureDevice deviceWithUniqueID:[NSString stringWithUTF8String:device_id_str]];
        } else {
            selectedDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        }

        if (!selectedDevice) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Device not found: %s", device_id_str ? device_id_str : "Default");
            return MINIAV_ERROR_DEVICE_NOT_FOUND;
        }

        if (!macos_avf_validate_format_support(selectedDevice, format_req)) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, 
                      "AVF: Requested format not supported by device. Use MiniAV_Camera_GetSupportedFormats() to get valid options.");
            return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
        }

        float requested_fps = (format_req->frame_rate_denominator > 0) ? 
                             (float)format_req->frame_rate_numerator / format_req->frame_rate_denominator : 0;
        miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                  "AVF: Attempting to configure: %dx%d, PixelFormat: %d, FPS: %.2f", 
                  format_req->width, format_req->height, format_req->pixel_format, requested_fps);

        BOOL format_set = NO;
        
        [platCtx->captureSession beginConfiguration];

        // Remove existing input if any
        if (platCtx->deviceInput) {
            [platCtx->captureSession removeInput:platCtx->deviceInput];
            [platCtx->deviceInput release];
            platCtx->deviceInput = nil;
        }

        // Create new input
        NSError *inputError = nil;
        platCtx->deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:selectedDevice error:&inputError];
        if (!platCtx->deviceInput) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to create device input: %s", 
                      [[inputError localizedDescription] UTF8String]);
            [platCtx->captureSession commitConfiguration];
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        if ([platCtx->captureSession canAddInput:platCtx->deviceInput]) {
            [platCtx->captureSession addInput:platCtx->deviceInput];
        } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Cannot add device input to session.");
            [platCtx->deviceInput release];
            platCtx->deviceInput = nil;
            [platCtx->captureSession commitConfiguration];
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }

        for (AVCaptureDeviceFormat *avFormat in selectedDevice.formats) {
            CMFormatDescriptionRef desc = avFormat.formatDescription;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
            OSType fourCC = CMFormatDescriptionGetMediaSubType(desc);
            MiniAVPixelFormat currentMiniAVFormat = FourCCToMiniAVPixelFormat(fourCC);

            char fourCCStr[5] = {0};
            *(OSType*)fourCCStr = CFSwapInt32HostToBig(fourCC);

            if (dimensions.width == format_req->width && 
                dimensions.height == format_req->height &&
                currentMiniAVFormat == format_req->pixel_format) {

                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: **EXACT MATCH FOUND** - %dx%d, FourCC: '%.4s', PixelFormat: %d", 
                          dimensions.width, dimensions.height, fourCCStr, currentMiniAVFormat);

                for (AVFrameRateRange *range in avFormat.videoSupportedFrameRateRanges) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Checking frame rate range: %.2f - %.2f for requested: %.2f", 
                              range.minFrameRate, range.maxFrameRate, requested_fps);

                    BOOL fps_in_range = NO;
                    if (requested_fps == 0 && range.maxFrameRate > 0) {
                        fps_in_range = YES;
                    } else if (requested_fps > 0) {
                        float tolerance = 0.1f;
                        if (requested_fps >= (range.minFrameRate - tolerance) && 
                            requested_fps <= (range.maxFrameRate + tolerance)) {
                            fps_in_range = YES;
                        }
                    }

                    if (fps_in_range) {
                        miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                                  "AVF: Frame rate %.2f is within range %.2f-%.2f. Attempting to set format...", 
                                  requested_fps, range.minFrameRate, range.maxFrameRate);
                        
                        CMTime targetFrameDuration;
                        float actual_fps_to_set = requested_fps;
                        if (requested_fps == 0) {
                           actual_fps_to_set = range.maxFrameRate;
                           targetFrameDuration = CMTimeMake(1, (int32_t)range.maxFrameRate);
                        } else {
                           targetFrameDuration = CMTimeMake(1, (int32_t)actual_fps_to_set);
                           

                           for (AVFrameRateRange *exactRange in avFormat.videoSupportedFrameRateRanges) {
                               if (fabsf(exactRange.maxFrameRate - actual_fps_to_set) < 0.1f) {
                                   targetFrameDuration = exactRange.maxFrameDuration;
                                   miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                                             "AVF: Using device's preferred frame duration for %.2f FPS", actual_fps_to_set);
                                   break;
                               }
                           }
                        }
                        
                        NSError *lockError = nil;
                        BOOL lockSuccess = [selectedDevice lockForConfiguration:&lockError];
                        
                        if (lockSuccess) {
                            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Successfully locked device for configuration");
                            
                            // Set the format
                            selectedDevice.activeFormat = avFormat;
                            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Set activeFormat");
                            
                            miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                                      "AVF: Setting frame duration: %lld/%d (%.6f seconds, %.2f FPS)", 
                                      targetFrameDuration.value, targetFrameDuration.timescale,
                                      CMTimeGetSeconds(targetFrameDuration), 
                                      1.0 / CMTimeGetSeconds(targetFrameDuration));
                            
                            // Set frame rate
                            selectedDevice.activeVideoMinFrameDuration = targetFrameDuration;
                            selectedDevice.activeVideoMaxFrameDuration = targetFrameDuration;
                            miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Set frame durations");
                            
                            [selectedDevice unlockForConfiguration];
                            format_set = YES;
                            
                            miniav_log(MINIAV_LOG_LEVEL_INFO, 
                                      "AVF: ✅ Successfully set format: %dx%d @ %.2f FPS, PixelFormat: %d (FourCC: '%.4s')",
                                      format_req->width, format_req->height, actual_fps_to_set, 
                                      format_req->pixel_format, fourCCStr);
                            break; 
                        } else {
                            const char* errorDesc = lockError ? [[lockError localizedDescription] UTF8String] : "Unknown error";
                            miniav_log(MINIAV_LOG_LEVEL_ERROR, 
                                      "AVF: ❌ Failed to lock device for format config: %s (Code: %ld)", 
                                      errorDesc, lockError ? [lockError code] : -1);
                            
                            if (lockError && [lockError code] == AVErrorDeviceAlreadyUsedByAnotherSession) {
                                miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Device is already in use by another session");
                                result = MINIAV_ERROR_DEVICE_BUSY;
                            } else if (lockError && [lockError code] == AVErrorDeviceNotAvailableInBackground) {
                                miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Device not available in background");
                                result = MINIAV_ERROR_DEVICE_NOT_FOUND;
                            } else {
                                result = MINIAV_ERROR_SYSTEM_CALL_FAILED;
                            }
                        }
                    } else {
                        miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                                  "AVF: Frame rate %.2f NOT in range %.2f-%.2f", 
                                  requested_fps, range.minFrameRate, range.maxFrameRate);
                    }
                }
            } else {
                // Log why this format doesn't match
                if (dimensions.width != format_req->width || dimensions.height != format_req->height) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Skipping format - resolution mismatch: %dx%d (wanted %dx%d)", 
                              dimensions.width, dimensions.height, format_req->width, format_req->height);
                } else if (currentMiniAVFormat != format_req->pixel_format) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Skipping format - pixel format mismatch: %d (wanted %d, FourCC: '%.4s')", 
                              currentMiniAVFormat, format_req->pixel_format, fourCCStr);
                }
            }
            if (format_set) break;
        }

        if (!format_set && result == MINIAV_SUCCESS) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, 
                      "AVF: ❌ Could not find or set matching format for %dx%d PxFormat:%d FPS:%.2f - despite validation passing!",
                      format_req->width, format_req->height, format_req->pixel_format, requested_fps);
            result = MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
        }
        
        if (result != MINIAV_SUCCESS) {
            [platCtx->captureSession commitConfiguration];
            return result;
        }

        // **REST OF THE FUNCTION CONTINUES...**
        if (platCtx->videoDataOutput) {
            [platCtx->captureSession removeOutput:platCtx->videoDataOutput];
            [platCtx->videoDataOutput release];
            platCtx->videoDataOutput = nil;
        }
        platCtx->videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        OSType targetOutputFourCC = MiniAVPixelFormatToFourCC(format_req->pixel_format);
        if (targetOutputFourCC == 0) {
            miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: No direct FourCC for MiniAVPixelFormat %d. Requesting BGRA for output.", format_req->pixel_format);
            targetOutputFourCC = kCVPixelFormatType_32BGRA;
        }
        
        NSDictionary *videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(targetOutputFourCC)};
        platCtx->videoDataOutput.videoSettings = videoSettings;
        platCtx->videoDataOutput.alwaysDiscardsLateVideoFrames = YES;

        MiniAVCaptureDelegate *delegate = [[MiniAVCaptureDelegate alloc] initWithMiniAVContext:ctx];
        [platCtx->videoDataOutput setSampleBufferDelegate:delegate queue:platCtx->videoOutputQueue];
        [delegate release]; 

        if ([platCtx->captureSession canAddOutput:platCtx->videoDataOutput]) {
            [platCtx->captureSession addOutput:platCtx->videoDataOutput];
        } else {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Cannot add video data output to session.");
            [platCtx->videoDataOutput release]; 
            platCtx->videoDataOutput = nil;
            [platCtx->captureSession commitConfiguration];
            return MINIAV_ERROR_SYSTEM_CALL_FAILED;
        }
        
        [platCtx->captureSession commitConfiguration];
    }
    
    if (result == MINIAV_SUCCESS) {
         miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: ✅ Successfully configured device: %s", device_id_str ? device_id_str : "Default");
    }
    return result;
}

static MiniAVResultCode macos_avf_start_capture(MiniAVCameraContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;
    if (!platCtx->captureSession) return MINIAV_ERROR_NOT_INITIALIZED;

    @autoreleasepool {
        if (![platCtx->captureSession isRunning]) {
            dispatch_async(platCtx->sessionQueue, ^{
                [platCtx->captureSession startRunning];
                miniav_log(MINIAV_LOG_LEVEL_INFO, "AVF: Capture session started.");
            });
        } else {
            miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: Capture session already running.");
        }
    }
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_stop_capture(MiniAVCameraContext* ctx) {
    if (!ctx || !ctx->platform_ctx) return MINIAV_ERROR_INVALID_ARG;
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;
    if (!platCtx->captureSession) return MINIAV_SUCCESS;

    @autoreleasepool {
        if ([platCtx->captureSession isRunning]) {
            dispatch_sync(platCtx->sessionQueue, ^{ 
                [platCtx->captureSession stopRunning];
                miniav_log(MINIAV_LOG_LEVEL_INFO, "AVF: Capture session stopped.");
            });
        } else {
            miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: Capture session not running or already stopped.");
        }
    }
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_release_buffer(MiniAVCameraContext* ctx, void* native_buffer_payload_void) {
    MINIAV_UNUSED(ctx);
    if (!native_buffer_payload_void) return MINIAV_ERROR_INVALID_ARG;
    
    MiniAVNativeBufferInternalPayload* payload = (MiniAVNativeBufferInternalPayload*)native_buffer_payload_void;
    
    @autoreleasepool {
        if (payload->native_singular_resource_ptr) {
            MiniAVBufferContentType content_type = MINIAV_BUFFER_CONTENT_TYPE_CPU; 
            if (payload->parent_miniav_buffer_ptr) { // Check parent buffer for actual content type
                content_type = payload->parent_miniav_buffer_ptr->content_type;
            }

            if (content_type == MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE) {
                CVMetalTextureRef metalTextureRef = (CVMetalTextureRef)payload->native_singular_resource_ptr;
                CFRelease(metalTextureRef); 
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Released CVMetalTextureRef: %p", metalTextureRef);
            } else { // Default to CPU / CVImageBufferRef
                CVImageBufferRef imageBuffer = (CVImageBufferRef)payload->native_singular_resource_ptr;
                CVBufferRelease(imageBuffer);
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Released CVImageBufferRef: %p", imageBuffer);
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

static MiniAVResultCode macos_avf_enumerate_devices(MiniAVDeviceInfo** devices_out, uint32_t* count_out) {
    if (!devices_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
    *devices_out = NULL; *count_out = 0;

    @autoreleasepool {
        // **FIX DEPRECATED API**
        AVCaptureDeviceDiscoverySession *discoverySession = nil;
        if (@available(macOS 10.15, *)) {
            discoverySession = [AVCaptureDeviceDiscoverySession 
                               discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown]
                               mediaType:AVMediaTypeVideo
                               position:AVCaptureDevicePositionUnspecified];
        }
        
        NSArray<AVCaptureDevice *> *avDevices = nil;
        if (discoverySession) {
            avDevices = discoverySession.devices;
        } else {
            // Fallback for older macOS versions
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            avDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop
        }
        
        if (!avDevices || [avDevices count] == 0) {
            miniav_log(MINIAV_LOG_LEVEL_INFO, "AVF: No video devices found.");
            return MINIAV_SUCCESS; 
        }

        *count_out = (uint32_t)[avDevices count];
        *devices_out = (MiniAVDeviceInfo*)miniav_calloc(*count_out, sizeof(MiniAVDeviceInfo));
        if (!*devices_out) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to allocate memory for device list.");
            *count_out = 0;
            return MINIAV_ERROR_OUT_OF_MEMORY;
        }

        AVCaptureDevice *defaultDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        for (uint32_t i = 0; i < *count_out; ++i) {
            AVCaptureDevice *device = [avDevices objectAtIndex:i];
            MiniAVDeviceInfo *info = &(*devices_out)[i];
            strncpy(info->device_id, [[device uniqueID] UTF8String], MINIAV_DEVICE_ID_MAX_LEN - 1);
            info->device_id[MINIAV_DEVICE_ID_MAX_LEN - 1] = '\0';
            strncpy(info->name, [[device localizedName] UTF8String], MINIAV_DEVICE_NAME_MAX_LEN - 1);
            info->name[MINIAV_DEVICE_NAME_MAX_LEN - 1] = '\0';
            info->is_default = (defaultDevice && [[device uniqueID] isEqualToString:[defaultDevice uniqueID]]);
        }
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Enumerated %u devices.", *count_out);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_get_supported_formats(const char* device_id_str, MiniAVVideoInfo** formats_out, uint32_t* count_out) {
    if (!device_id_str || !formats_out || !count_out) return MINIAV_ERROR_INVALID_ARG;
    *formats_out = NULL; *count_out = 0;

    @autoreleasepool {
        AVCaptureDevice *device = [AVCaptureDevice deviceWithUniqueID:[NSString stringWithUTF8String:device_id_str]];
        if (!device) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Device not found for get_supported_formats: %s", device_id_str);
            return MINIAV_ERROR_DEVICE_NOT_FOUND;
        }

        NSArray<AVCaptureDeviceFormat *> *avFormats = [device formats];
        if (!avFormats || [avFormats count] == 0) {
            miniav_log(MINIAV_LOG_LEVEL_INFO, "AVF: No formats found for device: %s", device_id_str);
            return MINIAV_SUCCESS;
        }
        
        NSMutableArray<NSValue*> *tempFormatList = [NSMutableArray array];

        for (AVCaptureDeviceFormat *avFormat in avFormats) {
            CMFormatDescriptionRef formatDesc = [avFormat formatDescription];
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
            OSType fourCC = CMFormatDescriptionGetMediaSubType(formatDesc);
            MiniAVPixelFormat miniAVFormat = FourCCToMiniAVPixelFormat(fourCC);

            // **NEW: Add detailed format logging**
            char fourCCStr[5] = {0};
            *(OSType*)fourCCStr = CFSwapInt32HostToBig(fourCC);
            miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                      "AVF: Examining format: %dx%d, FourCC: '%.4s' (%u), MiniAV: %d", 
                      dimensions.width, dimensions.height, fourCCStr, fourCC, miniAVFormat);

            if (miniAVFormat == MINIAV_PIXEL_FORMAT_UNKNOWN) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Skipping unknown format");
                continue;
            }

            // **NEW: Filter out unusually small resolutions**
            if (dimensions.width < 160 || dimensions.height < 120) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                          "AVF: Skipping unusually small resolution: %dx%d", 
                          dimensions.width, dimensions.height);
                continue;
            }

            for (AVFrameRateRange *range in avFormat.videoSupportedFrameRateRanges) {
                float maxFrameRate = range.maxFrameRate;
                if (maxFrameRate > 240.0f) {
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Skipping extreme frame rate: %.2f", maxFrameRate);
                    continue;
                }

                // List max frame rate of the range
                float frameRate = maxFrameRate;
                if (frameRate == 0 && range.minFrameRate > 0) frameRate = range.minFrameRate;
                if (frameRate == 0) frameRate = 30; // Fallback

                // Check if this exact format is already added
                bool already_added = false;
                for(NSValue* val in tempFormatList) {
                    MiniAVVideoInfo* existing = (MiniAVVideoInfo*)[val pointerValue];
                    float existing_fps = (existing->frame_rate_denominator > 0) ?
                                         (float)existing->frame_rate_numerator / existing->frame_rate_denominator : 0;
                    if(existing->width == dimensions.width && 
                       existing->height == dimensions.height && 
                       existing->pixel_format == miniAVFormat &&
                       fabsf(existing_fps - frameRate) < 0.01f ) {
                        already_added = true; 
                        break;
                    }
                }

                if(!already_added) {
                    MiniAVVideoInfo *info = (MiniAVVideoInfo*)miniav_calloc(1, sizeof(MiniAVVideoInfo));
                    if (!info) { 
                        for (NSValue* val in tempFormatList) { miniav_free([val pointerValue]); }
                        return MINIAV_ERROR_OUT_OF_MEMORY; 
                    }
                    info->width = dimensions.width;
                    info->height = dimensions.height;
                    info->pixel_format = miniAVFormat;
                    info->frame_rate_numerator = (uint32_t)(frameRate * 1000); 
                    info->frame_rate_denominator = 1000;
                    info->output_preference = MINIAV_OUTPUT_PREFERENCE_CPU;
                    [tempFormatList addObject:[NSValue valueWithPointer:info]];
                    
                    miniav_log(MINIAV_LOG_LEVEL_DEBUG, 
                              "AVF: Added format: %dx%d @ %.2f FPS, PixelFormat: %d", 
                              dimensions.width, dimensions.height, frameRate, miniAVFormat);
                }
            }
        }
        
        *count_out = (uint32_t)[tempFormatList count];
        if (*count_out > 0) {
            *formats_out = (MiniAVVideoInfo*)miniav_calloc(*count_out, sizeof(MiniAVVideoInfo));
            if (!*formats_out) {
                for (NSValue* val in tempFormatList) { miniav_free([val pointerValue]); }
                *count_out = 0;
                return MINIAV_ERROR_OUT_OF_MEMORY;
            }
            for (uint32_t i = 0; i < *count_out; ++i) {
                MiniAVVideoInfo* srcInfo = (MiniAVVideoInfo*)[[tempFormatList objectAtIndex:i] pointerValue];
                memcpy(&(*formats_out)[i], srcInfo, sizeof(MiniAVVideoInfo));
                miniav_free(srcInfo); 
            }
        }
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Found %u supported formats for device: %s", *count_out, device_id_str);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_get_default_format(const char* device_id_str, MiniAVVideoInfo* format_out) {
    if (!device_id_str || !format_out) return MINIAV_ERROR_INVALID_ARG;
    memset(format_out, 0, sizeof(MiniAVVideoInfo));

    @autoreleasepool {
        AVCaptureDevice *device = [AVCaptureDevice deviceWithUniqueID:[NSString stringWithUTF8String:device_id_str]];
        if (!device) {
            miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Device not found for get_default_format: %s", device_id_str);
            return MINIAV_ERROR_DEVICE_NOT_FOUND;
        }

        AVCaptureDeviceFormat *activeFormat = [device activeFormat]; // This is the device's current *active* format
        if (!activeFormat) { // Fallback if no active format (e.g. device not in use)
            miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: No active format for device: %s. Trying first available.", device_id_str);
            if ([[device formats] count] > 0) {
                activeFormat = [[device formats] objectAtIndex:0];
            } else {
                return MINIAV_ERROR_FORMAT_NOT_SUPPORTED;
            }
        }
        
        CMFormatDescriptionRef formatDesc = [activeFormat formatDescription];
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
        OSType fourCC = CMFormatDescriptionGetMediaSubType(formatDesc);

        format_out->width = dimensions.width;
        format_out->height = dimensions.height;
        format_out->pixel_format = FourCCToMiniAVPixelFormat(fourCC);
        if (format_out->pixel_format == MINIAV_PIXEL_FORMAT_UNKNOWN) {
             miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: Default format has unknown pixel format type: %.4s", (char*)&fourCC);
        }

        float frameRate = 30.0f; 
        NSArray *frameRateRanges = [activeFormat videoSupportedFrameRateRanges];
         if ([frameRateRanges count] > 0) {
            AVFrameRateRange *range = [frameRateRanges firstObject]; // Get first range
            // Prefer max frame rate, or a common one like 30 if it's within a range
            if (range.maxFrameRate >= 30.0f && range.minFrameRate <= 30.0f) frameRate = 30.0f;
            else frameRate = range.maxFrameRate;
            if (frameRate == 0 && range.minFrameRate > 0) frameRate = range.minFrameRate;
        }
        format_out->frame_rate_numerator = (uint32_t)(frameRate * 1000);
        format_out->frame_rate_denominator = 1000;
        format_out->output_preference = MINIAV_OUTPUT_PREFERENCE_CPU; // Default preference
    }
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Got default format for device: %s", device_id_str);
    return MINIAV_SUCCESS;
}

static MiniAVResultCode macos_avf_get_configured_video_format(MiniAVCameraContext* ctx, MiniAVVideoInfo* format_out) {
    if (!ctx || !format_out) return MINIAV_ERROR_INVALID_ARG;
    if (!ctx->is_configured || !ctx->platform_ctx) return MINIAV_ERROR_NOT_CONFIGURED;
    
    AVFPlatformContext* platCtx = (AVFPlatformContext*)ctx->platform_ctx;
    if (!platCtx->deviceInput || !platCtx->deviceInput.device || !platCtx->deviceInput.device.activeFormat) {
        *format_out = ctx->configured_video_format; // Fallback to cached
        miniav_log(MINIAV_LOG_LEVEL_WARN, "AVF: get_configured_video_format falling back to cached format (active device/format info missing).");
        return MINIAV_SUCCESS;
    }

    @autoreleasepool {
        AVCaptureDeviceFormat *activeDevFormat = platCtx->deviceInput.device.activeFormat;
        CMFormatDescriptionRef formatDesc = [activeDevFormat formatDescription];
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
        
        format_out->width = dimensions.width;
        format_out->height = dimensions.height;
        
        // Pixel format should be what videoDataOutput is set to deliver
        if (platCtx->videoDataOutput && platCtx->videoDataOutput.videoSettings) {
            NSNumber *outputFourCCNum = [platCtx->videoDataOutput.videoSettings objectForKey:(id)kCVPixelBufferPixelFormatTypeKey];
            if (outputFourCCNum) {
                format_out->pixel_format = FourCCToMiniAVPixelFormat([outputFourCCNum unsignedIntValue]);
            } else { // Fallback to device's active format's pixel format
                 format_out->pixel_format = FourCCToMiniAVPixelFormat(CMFormatDescriptionGetMediaSubType(formatDesc));
            }
        } else { // Fallback if videoDataOutput not fully set up
            format_out->pixel_format = FourCCToMiniAVPixelFormat(CMFormatDescriptionGetMediaSubType(formatDesc));
        }

        CMTime frameDuration = platCtx->deviceInput.device.activeVideoMinFrameDuration;
        if (CMTIME_IS_VALID(frameDuration) && frameDuration.value != 0) {
            format_out->frame_rate_numerator = (uint32_t)frameDuration.timescale;
            format_out->frame_rate_denominator = (uint32_t)frameDuration.value;
        } else {
            format_out->frame_rate_numerator = ctx->configured_video_format.frame_rate_numerator;
            format_out->frame_rate_denominator = ctx->configured_video_format.frame_rate_denominator;
        }
        format_out->output_preference = ctx->configured_video_format.output_preference; 
    }
    return MINIAV_SUCCESS;
}


// --- Global Ops Table ---
const CameraContextInternalOps g_camera_ops_macos_avf = {
    .init_platform = macos_avf_init_platform,
    .destroy_platform = macos_avf_destroy_platform,
    .configure = macos_avf_configure,
    .start_capture = macos_avf_start_capture,
    .stop_capture = macos_avf_stop_capture,
    .release_buffer = macos_avf_release_buffer,
    .enumerate_devices = macos_avf_enumerate_devices,
    .get_supported_formats = macos_avf_get_supported_formats,
    .get_default_format = macos_avf_get_default_format,
    .get_configured_video_format = macos_avf_get_configured_video_format,
};

// --- Platform Init for Selection ---
MiniAVResultCode miniav_camera_context_platform_init_macos_avf(MiniAVCameraContext* ctx) {
    if (!ctx) return MINIAV_ERROR_INVALID_ARG;

    @autoreleasepool { // Check for basic usability
        AVCaptureDeviceDiscoverySession *discoverySession = nil;
        if (@available(macOS 10.15, *)) {
            discoverySession = [AVCaptureDeviceDiscoverySession 
                               discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown]
                               mediaType:AVMediaTypeVideo
                               position:AVCaptureDevicePositionUnspecified];
        }
        
        if (!discoverySession) {
            // Fallback check for older macOS
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if (![AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
                miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: No video devices available during platform check");
            }
#pragma clang diagnostic pop
        }
    }
    
    ctx->ops = &g_camera_ops_macos_avf;
    ctx->platform_ctx = miniav_calloc(1, sizeof(AVFPlatformContext));
    if (!ctx->platform_ctx) {
        miniav_log(MINIAV_LOG_LEVEL_ERROR, "AVF: Failed to allocate AVFPlatformContext.");
        ctx->ops = NULL; 
        return MINIAV_ERROR_OUT_OF_MEMORY;
    }
    
    miniav_log(MINIAV_LOG_LEVEL_DEBUG, "AVF: Platform selected. Platform context memory allocated.");
    return MINIAV_SUCCESS;
}