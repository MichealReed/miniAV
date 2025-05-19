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
  // ... other GPU types as needed for video.
} MiniAVBufferContentType;

typedef struct {
  MiniAVBufferType type;
  MiniAVBufferContentType content_type; // CPU or GPU type
  int64_t timestamp_us;

  union {
    struct {
      MiniAVVideoInfo info;

      // CPU data
      uint32_t stride_bytes[4];
      void *planes[4];

      // GPU handles
      void *native_gpu_shared_handle; // e.g., NT HANDLE for D3D11
      void *native_gpu_texture_ptr;   // e.g., ID3D11Texture2D*
      int native_gpu_dmabuf_fd;       // e.g., DMA-BUF file descriptor
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
  void *context_owner;       // e.g., MiniAVCameraContextHandle,
                             // MiniAVAudioContextHandle
  void *native_resource_ptr; // e.g., IMFMediaBuffer*, v4l2_buffer*,
                             // CMSampleBufferRef
  MiniAVBuffer
      *parent_miniav_buffer_ptr; // Pointer to the heap-allocated MiniAVBuffer
} MiniAVNativeBufferInternalPayload;

#ifdef __cplusplus
}
#endif

#endif // MINIAV_BUFFER_H