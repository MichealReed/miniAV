# MiniAV Design Document

## Overview

MiniAV is a lightweight, cross-platform library focused on encapsulating audio and video buffers for computer vision and signal processing pipelines. It provides two buffer types—one for video and one for audio—that allow direct transfer of raw data (pixel or sample data) to a GPU compute shader pipeline. MiniAV is engineered to integrate with an existing compute shader library (minigpu) that already supports a fully cross-platform, high-performance compute engine.

## Goals

- **Cross-Platform Compatibility:**  
  Support iOS, macOS, Windows, Linux, Android, and Web (via Emscripten).

- **Unified Buffer Management:**  
  Develop a `miniAVBuffer` interface for video and audio that encapsulates raw data (e.g., `uint8_t` for video, `int16_t`/`float` for audio) along with rich metadata such as:
  - Resolution (width, height)
  - Pixel format (e.g., I420, BGRA)
  - Framerate and timestamps / frame indices
  - Camera intrinsics (focal length, principal point, calibration data)
  - Additional optional metadata (exposure, ISO, white balance)

- **High-Performance Data Transfer:**  
  Enable zero (or minimal) copy paradigms on native platforms and efficient data transfer on the web so that raw buffers can be directly passed to the minigpu pipeline.

- **Modularity and Extensibility:**  
  Organize the project in a monorepo with clear separation between the core implementation, FFI bindings, web-specific integration, and platform-specific implementations. Moreover, factor out the core functionality into a standalone library (`miniAV_c`) so that the FFI wrapper (`miniAV_ffi`) can be built on top of it and published separately.

## Folder Structure

```console
miniav(monorepo)/
├── miniav_c/                 # Core implementation of audio and video buffer classes (standalone C library).
├── miniav_ffi/               # C FFI wrappers built on top of miniAV_c for integration with other languages (e.g., Dart, Rust, Python).
├── miniav_web/               # Web-specific integrations via Emscripten and JavaScript APIs.
└── miniav_platform_interface/ # Platform-specific native implementations for AV capture.
```

## Module Breakdown

### 1. MiniAV Core (miniav_c)

**Buffer Types:**

- **Video Buffer Class:**  
  Represents a video frame. Fields include:
  - **Raw Data Pointer:** (`uint8_t *`) for direct zero-copy access.
  - **Resolution:** Width and height.
  - **Pixel Format:** e.g., I420, BGRA.
  - **Framerate:** Frame rate or frame duration.
  - **Timestamps / Frame Index:** For synchronization.
  - **Camera Intrinsics:**  
    - Focal lengths (fx, fy)
    - Principal point (cx, cy)
    - Optional distortion coefficients and/or full calibration matrix.
  - **Additional Parameters (Optional):**
    - Exposure, ISO, white balance.
    - Sensor details (if available)

- **Audio Buffer Class:**  
  Represents an audio sample buffer. Fields include:
  - **Raw Data Pointer:** (data type may be `int16_t*` or `float*`).
  - **Sample Rate & Channel Count**
  - **Buffer Length:** In samples or bytes.
  - **Timestamps:** For synchronization between audio and video.

**API Functions:**

- Allocate, manage, and release buffer instances.
- Helper functions for metadata extraction, conversion (if necessary), and synchronization.
- Expose a stable, unified C API that supports zero-copy or minimal copy data transfers.
- Designed to integrate directly with the minigpu pipeline via functions such as `toGPU(data)`.

### 2. MiniAV FFI (miniav_ffi)

- Provide C API wrappers to expose the core functionality from miniAV_c.
- Present a stable and simplified FFI interface for language bindings.
- Maintain consistent error codes and callback mechanisms for reporting capture or processing events.
- Ensure that bindings for Dart (or other languages) can obtain raw pointer handles and full metadata.
- Will be built as a separate library that depends on the standalone miniAV_c.

### 3. MiniAV Web (miniav_web)

**Browser Capture Integration:**

- Use JavaScript APIs (e.g., `getUserMedia` and the Screen Capture API) to obtain audio and video.
- Utilize an OffscreenCanvas for video frame extraction.
- Employ Emscripten interop (via `EM_ASM`, `EM_JS`, or Embind) to efficiently transfer pixel data (typically as `Uint8` buffers) into WASM memory.

**Performance Considerations:**

- While a true zero-copy path is not feasible on the web, aim to minimize copying overhead with efficient data transfers.

### 4. MiniAV Platform Interface (miniav_platform_interface)

Provide platform-specific implementations to capture native AV data:

- **iOS/macOS:**
  - Wrap AVFoundation and Core Video APIs.
  - Use `CVPixelBufferRef` for video; obtain raw pointers with minimal overhead.
  - Support screen capture (e.g., via `CGDisplayStream`).

- **Android:**
  - Utilize the Android NDK with Camera2 (or similar) API to capture data.
  - Expose raw buffers and accompanying metadata.

- **Windows:**
  - Use Media Foundation or DirectShow for camera and screen capture buffers.

- **Linux:**
  - Implement capture using V4L2 for camera buffers.
  - Leverage standard X11/Wayland APIs for screen capture.

**Common Aspects:**

- Extract and populate metadata (resolution, pixel format, intrinsic parameters) from captured buffers.
- Aim for minimal copy data transfers using native zero-copy or pinned memory techniques where possible.

## Data Flow

1. **Capture Stage:**  
   Platform-specific code captures audio/video frames and instantiates a corresponding MiniAVBuffer (video or audio) in the native layer (implemented in miniAV_c).

2. **Buffer Management:**  
   The core library (miniAV_c) handles the lifecycle of these buffers, including reference counting and metadata management.

3. **FFI Layer / Web Interop:**  
   - **Native:** A C API is exposed to create and pass these buffers seamlessly.
   - **Web:** JavaScript-captured data is bridged to C/WASM via Emscripten interop.

4. **Compute Pipeline Integration:**  
   The raw buffer pointer and full metadata are passed to the minigpu pipeline (e.g., via `toGPU(data)`), allowing compute shaders to process the data directly with minimal overhead.

## Considerations for Computer Vision

- **Metadata Requirements:**
  - **Video:** Resolution, color space, frame rate, and detailed camera intrinsics.
  - **Audio:** Sample rate, channel count, bit depth, and synchronization timestamps.
- **Additional Information:**
  - Exposure, ISO, white balance, and other sensor details.
  - Provision for offline calibration or configuration override for cameras that do not output full calibration data.
- **Realtime Calibration & Intrinsics Extraction:**
  - **Realtime Methods:**  
    Investigate online self-calibration, continuous sensor fusion (combining IMU data with video), or lightweight deep learning approaches to estimate extrinsics during operation.
- **Overhead Minimization:**
  - Native platforms should target near zero-copy data transfers.
  - Optimize web transfers to minimize copy overhead via efficient techniques allowed by Emscripten.

## Conclusion

MiniAV is designed as a modular, cross-platform bridge between native AV capture and the minigpu compute shader pipeline. Its flexible structure—comprising core functions (miniAV_c), FFI bindings (miniAV_ffi), platform-specific integrations, and web support—ensures that rich metadata (including calibration data, sensor details, and synchronization information) is available to facilitate advanced computer vision and signal processing tasks. This design lays the foundation for an efficient system that delivers raw AV data with high performance, independent of platform-specific limitations.
