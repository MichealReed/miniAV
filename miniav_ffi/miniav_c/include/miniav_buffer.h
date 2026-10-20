#ifndef MINIAV_BUFFER_H
#define MINIAV_BUFFER_H

#include "miniav_types.h" // Includes the format enums now
#include "export.h"
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

// content_type is THE discriminator between the CPU and GPU buffer layouts.
// Do NOT probe planes[0].data_ptr to decide: on the GPU paths it is non-NULL
// (it carries the GPU handle) and planes[0].stride_bytes is 0.
typedef enum {
  MINIAV_BUFFER_CONTENT_TYPE_CPU, // CPU-accessible memory. Check
                                  // MiniAVBuffer.type to interpret data.video
                                  // or data.audio.
  // Video (Windows): planes[0].data_ptr is a *shared NT HANDLE* to a D3D11
  // texture (cast to HANDLE), planes[0].stride_bytes is 0, and there is no
  // CPU-readable pixel data.
  //
  // OWNERSHIP: miniav owns the handle and CloseHandle()s it inside
  // MiniAV_ReleaseBuffer. The app must NOT close it. The app must finish
  // importing it BEFORE calling MiniAV_ReleaseBuffer; after release the handle
  // is invalid. OpenSharedResource1 retains access to the SAME shared storage,
  // not a private copy. Untagged resources require the consumer to preserve
  // its snapshot before release. See MINIAV_D3D11_IMMUTABLE_READY_TAG below.
  MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE,
  MINIAV_BUFFER_CONTENT_TYPE_GPU_METAL_TEXTURE, // Video:
                                                // data.video.native_gpu_texture_ptr
                                                // is an id<MTLTexture>
  MINIAV_BUFFER_CONTENT_TYPE_GPU_DMABUF_FD, // Video:
                                            // data.video.native_gpu_dmabuf_fd
                                            // is a DMA-BUF file descriptor
  MINIAV_BUFFER_CONTENT_TYPE_GPU_AHARDWAREBUFFER, // Android: planes[0].data_ptr
                                                  // is AHardwareBuffer*
} MiniAVBufferContentType;

// Exact producer provenance, only for GPU_D3D11_HANDLE BGRA32 plane 0. A fresh,
// immutable allocation contains a completed producer copy. Consumers may keep
// an opened COM resource alive after MiniAV_ReleaseBuffer, without copying its
// pixels. The NT handle itself remains owned by MiniAV and closes on release.
// Stored in drm_format_modifier to preserve the existing C/Dart FFI layout;
// that field remains a DRM modifier on Linux. Absence means no such guarantee.
#define MINIAV_D3D11_IMMUTABLE_READY_TAG UINT64_C(0x57474331)

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
  // Linux DMA-BUF extended info; Windows may carry the provenance tag above.
  int      dmabuf_fd;            // Per-plane DMA-BUF file descriptor (-1 if n/a)
  uint64_t drm_format_modifier;  // DRM format modifier (DRM_FORMAT_MOD_LINEAR=0)
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

  // Optional native fence for GPU synchronization (zero-init = no fence).
  // Consumers must wait on this fence before reading the GPU resource.
  //
  // STATUS (0.6.0): NOT IMPLEMENTED BY ANY BACKEND — this struct is always
  // left zero-initialised, so d3d11_fence is always NULL, sync_fd is 0/-1 and
  // metal_shared_event is always NULL. Do not treat a NULL fence as "the GPU
  // is idle".
  //
  // What the Windows backends do instead: the producer waits for its own
  // copy before the shared NT handle goes out. Windows Graphics Capture
  // (window and display capture) and the Media Foundation camera signal an
  // ID3D11Fence after the copy (an event query where the runtime has no
  // fences) and wait at most 100 ms for it. A copy not complete by then is
  // never shared: WGC drops the frame, and the camera delivers it as a CPU
  // frame instead. DXGI Desktop Duplication still CPU busy-polls a
  // D3D11_QUERY_EVENT for at most ~16 ms and on timeout logs a rate-limited
  // warning and hands the frame over ANYWAY — i.e. under GPU contention a
  // consumer of that backend can receive a texture whose producer-side copy
  // has not finished (torn/black frame), and must do its own synchronisation
  // if it needs a hard guarantee.
  // See NATIVE_AUDIT.md "P2 — Real fences instead of the poll".
  struct {
    int   sync_fd;             // Linux/Android: sync_file fd (-1 if none)
    void *d3d11_fence;         // Windows: ID3D11Fence* — ALWAYS NULL today
    void *metal_shared_event;  // macOS/iOS: id<MTLSharedEvent> bridged (NULL if none)
    uint64_t metal_fence_value;// macOS/iOS: signaled value on metal_shared_event
  } native_fence;
} MiniAVBuffer;

// Optional screen-damage copy, with no changes to the public buffer layout.
// The buffer must remain alive, with no concurrent release, throughout this call.
// Returns 0 for uncertified/unsupported buffers. Otherwise returns the required
// uint64_t word count; writes only if words != NULL and capacity is sufficient.
// Words: source epoch, generation, width, height, full-frame (0/1), rectangle
// count, then x/y/width/height per rectangle. A non-full changed set is never
// empty. Generations number the frames DELIVERED in one epoch. Partial damage is
// relative ONLY to the frame delivered just before (generation - 1) and already
// includes changes from acquisitions that were never delivered. Missing metadata
// or a generation gap requires full-frame work.
MINIAV_API uint32_t MiniAV_VideoBuffer_CopyDamage(
    const MiniAVBuffer *buffer, uint64_t *words, uint32_t capacity);

typedef enum {
  MINIAV_YUV_MATRIX_UNKNOWN = 0,
  MINIAV_YUV_MATRIX_BT601 = 1,
  MINIAV_YUV_MATRIX_BT709 = 2,
  MINIAV_YUV_MATRIX_BT2020 = 3,
} MiniAVYuvMatrix;

// Optional colour of a YUV video buffer, with no changes to the public buffer
// layout. Same lifetime rule as MiniAV_VideoBuffer_CopyDamage. Returns 0 when
// the producer does not say (RGB formats, screen capture, backends that do not
// report it yet) and writes nothing. Otherwise returns 1 and writes the
// MiniAVYuvMatrix to *matrix and 1 (full, 0..255) or 0 (limited: luma 16..235,
// chroma 16..240) to *full_range; either pointer may be NULL.
MINIAV_API uint32_t MiniAV_VideoBuffer_GetColor(const MiniAVBuffer *buffer,
                                                uint32_t *matrix,
                                                uint32_t *full_range);

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
