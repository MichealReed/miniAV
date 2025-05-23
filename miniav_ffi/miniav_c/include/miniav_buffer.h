#ifndef MINIAV_BUFFER_H
#define MINIAV_BUFFER_H

#include "miniav_types.h" // Includes the format enums now
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- Buffer Type ---
typedef enum {
  MINIAV_BUFFER_TYPE_UNKNOWN = 0,
  MINIAV_BUFFER_TYPE_VIDEO,
  MINIAV_BUFFER_TYPE_AUDIO
} MiniAVBufferType;

typedef enum {
  MINIAV_NATIVE_HANDLE_TYPE_UNKNOWN = 0,
  MINIAV_NATIVE_HANDLE_TYPE_VIDEO_CAMERA,
  MINIAV_NATIVE_HANDLE_TYPE_VIDEO_SCREEN,
  MINIAV_NATIVE_HANDLE_TYPE_AUDIO
} MiniAVNativeHandleType;

typedef enum {
  MINIAV_BUFFER_CONTENT_TYPE_CPU, // CPU-accessible memory. Check
                                  // MiniAVBuffer.type to interpret data.video
                                  // or data.audio.
  MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE, // Video:
                                               // data.video.native_gpu_shared_handle
                                               // is a D3D11 NT HANDLE
  MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE, // Video:
                                                // data.video.native_gpu_texture_ptr
                                                // is an id<MTLTexture>
  MINIAV_BUFFER_CONTENT_TYPE_GPU_DMABUF_FD, // Video:
                                            // data.video.native_gpu_dmabuf_fd
                                            // is a DMA-BUF file descriptor
} MiniAVBufferContentType;

typedef struct {
  // Per-plane data (works for both CPU and GPU)
  void *data_ptr;        // CPU: memory pointer, GPU: texture/handle pointer
  uint32_t width;        // Plane width
  uint32_t height;       // Plane height
  uint32_t stride_bytes; // Row stride in bytes
  uint32_t offset_bytes; // Offset within a shared resource (GPU DMA-BUF, D3D11
                         // subresource)
  uint32_t
      subresource_index; // GPU: D3D11 subresource, Vulkan image aspect, etc.
} MiniAVVideoPlane;

typedef struct {
  MiniAVBufferType type;
  MiniAVBufferContentType content_type; // CPU or GPU type
  int64_t timestamp_us;

  union {
    struct {
      MiniAVVideoInfo
          info; // Overall frame info (total width, height, pixel format)
      // Unified plane data (CPU or GPU)
      uint32_t num_planes; // 1 for BGRA, 2 for NV12, 3 for I420
      MiniAVVideoPlane
          planes[MINIAV_VIDEO_FORMAT_MAX_PLANES]; // Unified plane info
    } video;

    struct {
      uint32_t frame_count;
      MiniAVAudioInfo info;
      void *data;
    } audio;
  } data;

  size_t data_size_bytes;
  void *user_data;
  void *internal_handle;
} MiniAVBuffer;

typedef struct MiniAVNativeBufferInternalPayload {
  MiniAVNativeHandleType handle_type;
  void *context_owner;

  // For single resources that need cleanup (CVPixelBuffer, HANDLE, etc.)
  void *native_singular_resource_ptr;

  // For multi-plane resources that need individual cleanup (multiple
  // CVMetalTextureRef)
  void *native_planar_resource_ptrs[MINIAV_VIDEO_FORMAT_MAX_PLANES];
  uint32_t num_planar_resources_to_release;

  MiniAVBuffer *parent_miniav_buffer_ptr;
} MiniAVNativeBufferInternalPayload;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_BUFFER_H