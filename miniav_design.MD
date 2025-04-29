# MiniAV Design Document

## Overview

MiniAV is a lightweight, cross-platform library focused on encapsulating audio and video buffers for computer vision and signal processing pipelines. It provides a `miniAVBuffer` type for video and audio data, designed for direct transfer of raw data (pixels or samples) to a GPU compute shader pipeline (like `minigpu`).

## Goals

* **Cross-Platform Compatibility:** Support Windows, macOS, Linux, Android, iOS, and Web (via Emscripten/WASM).
* **Specific Capture APIs:** Provide distinct, tailored C APIs for camera, screen, and audio capture.
* **Rich Buffer Management:** Develop a `miniAVBuffer` struct that encapsulates raw data along with essential metadata (resolution, pixel format, timestamps, audio format, etc.).
* **High-Performance Data Transfer:** Enable zero (or minimal) copy paradigms on native platforms and efficient data transfer on the web for direct use in compute pipelines.
* **Modularity and Extensibility:** Organize the project with clear separation between the core C library (`miniav_c` within `miniav_ffi`), the Dart FFI package (`miniav_ffi`), the web integration (`miniav_web`), and the Dart platform interface (`miniav_platform_interface`).
* **Leverage Existing Libraries:** Utilize `miniaudio` for cross-platform audio capture within the C library.

## Folder Structure

```console
miniav(monorepo)/
├── miniav_ffi/                     # Dart package providing FFI bindings and building the native library.
│   ├── lib/
│   │   ├── src/
│   │   │   ├── miniav_bindings.dart      # Generated FFI bindings (using ffigen).
│   │   │   ├── miniav_impl_ffi.dart      # FFI implementation of the platform interface.
│   │   │   ├── camera_controller_ffi.dart # FFI implementation for camera.
│   │   │   ├── screen_controller_ffi.dart # FFI implementation for screen.
│   │   │   └── audio_controller_ffi.dart  # FFI implementation for audio.
│   │   └── miniav_ffi.dart             # Main package export file.
│   ├── pubspec.yaml
│   ├── build.dart                    # Native assets build script (invokes CMake).
│   └── miniav_c/                     # Core C implementation.
│       ├── CMakeLists.txt            # Main CMake build configuration for miniav_c.
│       ├── cmake/                      # CMake helper modules.
│       │   └── FindMiniAudio.cmake     # Example CMake module.
│       ├── include/                  # Public C headers.
│       │   ├── miniav_buffer.h         # Defines MiniAVBuffer, format enums.
│       │   ├── miniav_capture.h        # Defines capture API functions, callback types.
│       │   └── miniav_types.h          # Defines MiniAVResultCode, MiniAVDeviceInfo, handles, etc.
│       └── src/                      # Native C/C++ source code.
│           ├── common/               # Platform-independent utilities.
│           │   ├── miniav_context_base.h # Base struct/functions for contexts.
│           │   ├── miniav_logging.c
│           │   ├── miniav_logging.h
│           │   ├── miniav_utils.c      # Memory allocation, string helpers.
│           │   ├── miniav_utils.h
│           │   └── miniav_time.c       # Monotonic clock functions.
│           │   └── miniav_time.h
│           ├── audio/                # Audio capture implementation (wraps miniaudio).
│           │   ├── audio_context.c     # Implementation of audio context functions.
│           │   └── audio_context.h     # Internal audio context struct.
│           ├── camera/               # Camera capture implementation.
│           │   ├── camera_api.c        # Implementation of public MiniAV_Camera_* functions.
│           │   ├── camera_context.h    # Internal camera context struct and common logic interface.
│           │   ├── windows/
│           │   │   ├── camera_context_win_mf.c # Media Foundation implementation.
│           │   │   └── camera_context_win_mf.h
│           │   │   └── (camera_context_win_ds.c) # Optional DirectShow fallback.
│           │   ├── macos/
│           │   │   ├── camera_context_macos_avf.m # AVFoundation implementation (Objective-C).
│           │   │   └── camera_context_macos_avf.h
│           │   └── linux/
│           │       ├── camera_context_linux_v4l2.c # V4L2 implementation.
│           │       └── camera_context_linux_v4l2.h
│           │       └── (camera_context_linux_pipewire.c) # Optional PipeWire.
│           └── screen/               # Screen capture implementation.
│               ├── screen_api.c        # Implementation of public MiniAV_Screen_* functions.
│               ├── screen_context.h    # Internal screen context struct and common logic interface.
│               ├── windows/
│               │   ├── screen_context_win_dxgi.c # Desktop Duplication implementation.
│               │   └── screen_context_win_dxgi.h
│               │   └── (screen_context_win_gdi.c) # Optional GDI fallback.
│               ├── macos/
│               │   ├── screen_context_macos_cg.m # CoreGraphics implementation (Objective-C).
│               │   └── screen_context_macos_cg.h
│               │   └── (screen_context_macos_avf.m) # Optional AVFoundation screen input.
│               └── linux/
│                   ├── screen_context_linux_pipewire.c # PipeWire portal implementation.
│                   └── screen_context_linux_pipewire.h
│                   └── (screen_context_linux_x11.c) # Optional X11 fallback.
│
├── miniav_web/                     # Web-specific implementation.
│   ├── lib/
│   │   ├── src/
│   │   │   ├── miniav_impl_web.dart      # Web implementation of the platform interface.
│   │   │   ├── camera_controller_web.dart # Web implementation for camera.
│   │   │   ├── screen_controller_web.dart # Web implementation for screen.
│   │   │   └── audio_controller_web.dart  # Web implementation for audio.
│   │   └── miniav_web.dart             # Main package export file.
│   ├── pubspec.yaml
│   └── web/                          # Potential location for JS interop files or WASM artifacts.
│       └── interop.js
│
└── miniav_platform_interface/      # Defines the common Dart API interface.
    ├── lib/
    │   ├── src/
    │   │   ├── miniav_platform_interface_base.dart # Base class for platform implementations.
    │   │   ├── miniav_controller.dart    # Abstract controller interface.
    │   │   ├── miniav_models.dart        # Dart equivalents of MiniAVBuffer, MiniAVDeviceInfo etc.
    │   │   └── miniav_enums.dart         # Dart equivalents of C enums.
    │   └── miniav_platform_interface.dart # Main package export file.
    └── pubspec.yaml
```

## Module Breakdown

### 1. MiniAV Core C Library (`miniav_ffi/miniav_c`)

This standalone C library contains the core buffer definitions, the public C capture APIs (split by type: camera, screen, audio), and all platform-specific native implementations (excluding web). It is built as a native asset by the `miniav_ffi` package.

* **Buffer Definition (`include/miniav_buffer.h`):** Defines `miniAVBuffer` struct, pixel/sample format enums, etc. Includes `internal_handle` for explicit buffer release.
* **Capture API (`include/miniav_capture.h`, `include/miniav_types.h`):** Defines the public C functions (e.g., `MiniAV_Camera_CreateContext`, `MiniAV_Screen_StartCapture`, `MiniAV_Audio_Configure`, `MiniAV_ReleaseBuffer`, etc.) and types (`MiniAVDeviceInfo`, `MiniAVResultCode`, `MiniAVBufferCallback`, etc.). This header is used by `miniav_ffi` to generate Dart bindings.
* **Implementation (`src/`):** Contains platform-independent logic (`src/common`), the `miniaudio` wrapper for audio (`src/audio`), and platform-specific implementations for camera and screen capture located within their respective directories (`src/camera/<platform>`, `src/screen/<platform>`). The common logic within `src/camera` and `src/screen` utilizes the platform-specific code.

#### Platform-Specific Native APIs (Implemented within `miniav_c/src/camera/<platform>` and `miniav_c/src/screen/<platform>`)

* **Windows:**
  * **Camera:** Media Foundation (preferred: `IMFSourceReader`), DirectShow (fallback).
  * **Screen:** Desktop Duplication API (preferred), GDI/BitBlt (fallback).
  * **Audio:** WASAPI (via `miniaudio`).
  * **Zero-Copy:** `IMFMediaBuffer::Lock` (Media Foundation), potentially direct access via GDI. Buffer release involves unlocking/releasing MF buffers.

* **macOS:**
  * **Camera:** AVFoundation (`AVCaptureSession`, `AVCaptureVideoDataOutput`).
  * **Screen:** AVFoundation (`AVCaptureScreenInput`), Core Graphics (`CGDisplayStream`).
  * **Audio:** Core Audio (via `miniaudio`).
  * **Zero-Copy:** `CVPixelBufferGetBaseAddress` on `CMSampleBufferRef` from AVFoundation. Buffer release involves releasing the `CMSampleBufferRef`.

* **Linux:**
  * **Camera:** V4L2 (Video for Linux 2). PipeWire as a higher-level alternative.
  * **Screen:** X11 (`XShmGetImage`), Wayland (requires compositor-specific protocols or PipeWire portal). PipeWire screen capture portal is preferred for broader compatibility.
  * **Audio:** ALSA / PulseAudio (via `miniaudio`). PipeWire for modern systems.
  * **Zero-Copy:** V4L2 buffer mapping (`mmap`), X11 shared memory extension (`XShm`). Buffer release involves unmapping/returning buffers to the kernel/server.

* **Android (`src/android/` - Future):**
  * **Camera:** Camera2 API (Java/Kotlin via JNI) or NDK Camera (`ACameraManager`).
  * **Screen:** `MediaProjection` API (Java/Kotlin via JNI).
  * **Audio:** AAudio (preferred), OpenSL ES (fallback) - likely via `miniaudio`.
  * **Zero-Copy:** `AHardwareBuffer` access via NDK, `ImageReader` direct buffer access. Release involves specific NDK/API calls.

* **iOS (`src/ios/` - Future):**
  * **Camera:** AVFoundation (`AVCaptureSession`, `AVCaptureVideoDataOutput`).
  * **Screen:** ReplayKit (`RPScreenRecorder`).
  * **Audio:** Core Audio (via `miniaudio` or direct implementation).
  * **Zero-Copy:** `CVPixelBufferGetBaseAddress` on `CMSampleBufferRef`. Release involves releasing the `CMSampleBufferRef`.

### 2. MiniAV FFI (`miniav_ffi`)

* Dart package responsible for interfacing with the native `miniav_c` library.
* Uses `package:ffigen` or similar tools to generate Dart bindings from the headers in `miniav_c/include/`.
* Contains a `build.dart` script that uses the native assets feature to compile `miniav_c` (using CMake) for the target platform.
* Implements the Dart interface defined in `miniav_platform_interface` by calling the C functions via FFI.
* Manages pointer passing, struct marshalling, callback setup (using `NativeCallable`), and **calling `MiniAV_ReleaseBuffer`** between Dart and C.

### 3. MiniAV Web (`miniav_web`)

* Dart package providing the web implementation.
* Uses `dart:html` and `dart:js_interop` to interact with browser APIs (`navigator.mediaDevices.getUserMedia`, `getDisplayMedia`).
* May potentially use a WASM module compiled from parts of `miniav_c` for shared logic or buffer handling if beneficial, but primary capture relies on browser APIs.
* Implements the Dart interface defined in `miniav_platform_interface`.
* Handles data transfer from JavaScript (`ImageData`, `VideoFrame`, `AudioBuffer`) into Dart representations compatible with the platform interface, likely involving copies. (Web platform generally does not support zero-copy access in the same way as native).

### 4. MiniAV Platform Interface (`miniav_platform_interface`)

* A Dart package defining the abstract interface (e.g., using abstract classes or `plugin_platform_interface`) for MiniAV functionality (Camera, Screen, Audio capture).
* Crucially, the interface must now accommodate the concept of **buffer release**. This might involve returning a Dart object that holds the buffer data/pointers *and* a mechanism (e.g., a `dispose()` method) to trigger the underlying native release.
* Both `miniav_ffi` and `miniav_web` implement this interface.
* Allows application code to depend on this package and use the MiniAV features without knowing the underlying platform (native vs. web).

## Core C API Design (`miniav_c/include/`)

This section details the public C API exposed by `miniav_c`.

### Common Types and Concepts

* **Handles (`MiniAVHandle`):** Opaque pointers representing contexts (e.g., `MiniAVCameraContextHandle`, `MiniAVScreenContextHandle`, `MiniAVAudioContextHandle`). Created by `_CreateContext` functions, destroyed by `_DestroyContext` functions. Invalidated after destruction.
* **Result Codes (`MiniAVResultCode`):** Enum defining success (`MINIAV_SUCCESS = 0`) and various error conditions (e.g., `MINIAV_ERROR_INVALID_ARG`, `MINIAV_ERROR_NOT_INITIALIZED`, `MINIAV_ERROR_SYSTEM_CALL_FAILED`, `MINIAV_ERROR_NOT_SUPPORTED`, `MINIAV_ERROR_BUFFER_TOO_SMALL`, `MINIAV_ERROR_INVALID_HANDLE`). Most functions return a `MiniAVResultCode`.
* **Device Info (`MiniAVDeviceInfo`):** Struct containing device ID (unique string, platform-specific format), human-readable name (UTF-8 string), and potentially other metadata like model or manufacturer.

    ```c
    // filepath: miniav_ffi/miniav_c/include/miniav_types.h
    typedef struct {
        char device_id[256]; // Platform-specific unique identifier
        char name[256];      // Human-readable name (UTF-8)
        // Potentially other fields like model, manufacturer, etc.
    } MiniAVDeviceInfo;
    ```

* **Buffer (`MiniAVBuffer`):** Struct containing the core data and metadata. **The data pointers are valid after the callback returns, until `MiniAV_ReleaseBuffer` is called.**

    ```c
    // filepath: miniav_ffi/miniav_c/include/miniav_buffer.h
    typedef enum {
        MINIAV_BUFFER_TYPE_UNKNOWN = 0,
        MINIAV_BUFFER_TYPE_VIDEO,
        MINIAV_BUFFER_TYPE_AUDIO
    } MiniAVBufferType;

    // Common Pixel Formats (Extend as needed)

  typedef enum {
      MINIAV_PIXEL_FORMAT_UNKNOWN = 0,
      MINIAV_PIXEL_FORMAT_I420,    // Planar YUV 4:2:0 (YYYY... UU... VV...)
      MINIAV_PIXEL_FORMAT_NV12,    // Semi-Planar YUV 4:2:0 (YYYY... UVUV...)
      MINIAV_PIXEL_FORMAT_NV21,    // Semi-Planar YUV 4:2:0 (YYYY... VUVU...)
      MINIAV_PIXEL_FORMAT_YUY2,    // Packed YUV 4:2:2 (YUYV YUYV...)
      MINIAV_PIXEL_FORMAT_UYVY,    // Packed YUV 4:2:2 (UYVY UYVY...)
      MINIAV_PIXEL_FORMAT_RGB24,   // Packed RGB (RGB RGB...)
      MINIAV_PIXEL_FORMAT_BGR24,   // Packed BGR (BGR BGR...)
      MINIAV_PIXEL_FORMAT_RGBA32,  // Packed RGBA (RGBA RGBA...)
      MINIAV_PIXEL_FORMAT_BGRA32,  // Packed BGRA (BGRA BGRA...)
      MINIAV_PIXEL_FORMAT_ARGB32,  // Packed ARGB (ARGB ARGB...)
      MINIAV_PIXEL_FORMAT_ABGR32,  // Packed ABGR (ABGR ABGR...)
      MINIAV_PIXEL_FORMAT_MJPEG,   // Motion JPEG (Compressed format)
  } MiniAVPixelFormat;

  // Common Audio Sample Formats (Align with miniaudio where possible)
  typedef enum {
      MINIAV_AUDIO_FORMAT_UNKNOWN = 0,
      MINIAV_AUDIO_FORMAT_U8,      // Unsigned 8-bit integer
      MINIAV_AUDIO_FORMAT_S16,     // Signed 16-bit integer
      MINIAV_AUDIO_FORMAT_S24,     // Signed 24-bit integer (often packed in 32 bits)
      MINIAV_AUDIO_FORMAT_S32,     // Signed 32-bit integer
      MINIAV_AUDIO_FORMAT_F32,     // 32-bit floating point
  } MiniAVAudioFormat;

    typedef struct {
        MiniAVBufferType type;
        int64_t timestamp_us; // Monotonic timestamp in microseconds since an arbitrary epoch (e.g., capture start or system boot)

        union {
            struct {
                uint32_t width;
                uint32_t height;
                MiniAVPixelFormat pixel_format;
                uint32_t stride_bytes[4]; // Stride for each plane (up to 4 for planar formats)
                void* planes[4];          // Pointers to data planes. Valid until MiniAV_ReleaseBuffer is called.
                // Camera Intrinsics (fx, fy, cx, cy, distortion coeffs)
                // double intrinsics[...];
            } video;
            struct {
                uint32_t frame_count;
                uint32_t channel_count;
                MiniAVAudioFormat sample_format;
                void* data; // Pointer to interleaved or planar audio data. Valid until MiniAV_ReleaseBuffer is called.
            } audio;
        } data;

        size_t data_size_bytes; // Total size of the raw data pointed to (useful for copying if needed)
        void* user_data;        // User data pointer passed back in the callback
        void* internal_handle;  // Opaque handle required by MiniAV_ReleaseBuffer to release the underlying native buffer.
    } MiniAVBuffer;
    ```

* **Buffer Callback (`MiniAVBufferCallback`):** Function pointer type for receiving buffers.

    ```c
    // filepath: miniav_ffi/miniav_c/include/miniav_capture.h
    // The buffer passed is valid beyond the callback; the user MUST eventually call MiniAV_ReleaseBuffer.
    typedef void (*MiniAVBufferCallback)(const MiniAVBuffer* buffer, void* user_data);
    ```

* **Logging Callback (`MiniAVLogCallback`):** Function pointer type for receiving log messages.

    ```c
    // filepath: miniav_ffi/miniav_c/include/miniav_types.h
    typedef enum {
        MINIAV_LOG_LEVEL_DEBUG = 0,
        MINIAV_LOG_LEVEL_INFO,
        MINIAV_LOG_LEVEL_WARN,
        MINIAV_LOG_LEVEL_ERROR
    } MiniAVLogLevel;

    typedef void (*MiniAVLogCallback)(MiniAVLogLevel level, const char* message, void* user_data);
    ```

### Common / Utility API

* `MiniAVResultCode MiniAV_GetVersion(uint32_t* major, uint32_t* minor, uint32_t* patch);`
* `const char* MiniAV_GetVersionString();`
* `MiniAVResultCode MiniAV_SetLogCallback(MiniAVLogCallback callback, void* user_data);`
* `MiniAVResultCode MiniAV_SetLogLevel(MiniAVLogLevel level);`
* `const char* MiniAV_GetErrorString(MiniAVResultCode code);` // Get human-readable string for an error code
* `MiniAVResultCode MiniAV_ReleaseBuffer(void* internal_handle);` // **New:** Releases the native buffer associated with the handle. Must be called by the user when done with the buffer data.

### Camera Capture API

* `MiniAVResultCode MiniAV_Camera_EnumerateDevices(MiniAVDeviceInfo** devices, uint32_t* count);`
  * Allocates memory for the device list; caller must free using `MiniAV_FreeDeviceList`.
* `MiniAVResultCode MiniAV_FreeDeviceList(MiniAVDeviceInfo* devices, uint32_t count);`
* `MiniAVResultCode MiniAV_Camera_GetSupportedFormats(const char* device_id, MiniAVVideoFormatInfo** formats, uint32_t* count);`
  * Describes supported resolution, pixel format, frame rate combinations.
  * Allocates memory; caller must free using `MiniAV_FreeFormatList`.
* `MiniAVResultCode MiniAV_FreeFormatList(MiniAVVideoFormatInfo* formats, uint32_t count);` // Needs refinement for distinct video/audio format lists/freeing
* `MiniAVResultCode MiniAV_Camera_CreateContext(MiniAVCameraContextHandle* context);`
* `MiniAVResultCode MiniAV_Camera_DestroyContext(MiniAVCameraContextHandle context);`
* `MiniAVResultCode MiniAV_Camera_Configure(MiniAVCameraContextHandle context, const char* device_id, const MiniAVVideoFormatInfo* format);`
  * Must be called before `StartCapture`. Can potentially be called after `StopCapture` to reconfigure.
* `MiniAVResultCode MiniAV_Camera_StartCapture(MiniAVCameraContextHandle context, MiniAVBufferCallback callback, void* user_data);`
* `MiniAVResultCode MiniAV_Camera_StopCapture(MiniAVCameraContextHandle context);`
* *(Property API - TBD: Define `MiniAVPropertyKey` enum and `MiniAVPropertyValue` variant struct/union)*
  * `MiniAV_Camera_GetPropertyInfo(...)`
  * `MiniAV_Camera_GetProperty(...)`
  * `MiniAV_Camera_SetProperty(...)`
  * `MiniAV_Camera_SetAutoProperty(...)`

### Screen Capture API

* `MiniAVResultCode MiniAV_Screen_EnumerateDisplays(MiniAVDeviceInfo** displays, uint32_t* count);`
  * Allocates memory; caller must free using `MiniAV_FreeDeviceList`.
* `MiniAVResultCode MiniAV_Screen_EnumerateWindows(MiniAVDeviceInfo** windows, uint32_t* count);` // Optional, platform support varies
  * Allocates memory; caller must free using `MiniAV_FreeDeviceList`.
* `MiniAVResultCode MiniAV_Screen_CreateContext(MiniAVScreenContextHandle* context);`
* `MiniAVResultCode MiniAV_Screen_DestroyContext(MiniAVScreenContextHandle context);`
* `MiniAVResultCode MiniAV_Screen_ConfigureDisplay(MiniAVScreenContextHandle context, const char* display_id, const MiniAVVideoFormatInfo* format);` // Format might be less strict, often just target FPS
* `MiniAVResultCode MiniAV_Screen_ConfigureWindow(MiniAVScreenContextHandle context, const char* window_id, const MiniAVVideoFormatInfo* format);` // `window_id` might be HWND, Window ID, etc.
* `MiniAVResultCode MiniAV_Screen_ConfigureRegion(MiniAVScreenContextHandle context, const char* display_id, int x, int y, int width, int height, const MiniAVVideoFormatInfo* format);`
* `MiniAVResultCode MiniAV_Screen_StartCapture(MiniAVScreenContextHandle context, MiniAVBufferCallback callback, void* user_data);`
* `MiniAVResultCode MiniAV_Screen_StopCapture(MiniAVScreenContextHandle context);`
* *(Property API - TBD: Define specific properties like cursor visibility, capture rate control)*
  * `MiniAV_Screen_GetProperty(...)`
  * `MiniAV_Screen_SetProperty(...)`

### Audio Capture API

* `MiniAVResultCode MiniAV_Audio_EnumerateDevices(MiniAVDeviceInfo** devices, uint32_t* count);`
  * Allocates memory; caller must free using `MiniAV_FreeDeviceList`.
* `MiniAVResultCode MiniAV_Audio_GetSupportedFormats(const char* device_id, MiniAVAudioFormatInfo** formats, uint32_t* count);`
  * Describes supported sample format, channel count, sample rate combinations.
  * Allocates memory; caller must free using `MiniAV_FreeFormatList`. // Needs distinct audio format list freeing
* `MiniAVResultCode MiniAV_Audio_CreateContext(MiniAVAudioContextHandle* context);`
* `MiniAVResultCode MiniAV_Audio_DestroyContext(MiniAVAudioContextHandle context);`
* `MiniAVResultCode MiniAV_Audio_Configure(MiniAVAudioContextHandle context, const char* device_id, const MiniAVAudioFormatInfo* format);`
* `MiniAVResultCode MiniAV_Audio_StartCapture(MiniAVAudioContextHandle context, MiniAVBufferCallback callback, void* user_data);`
* `MiniAVResultCode MiniAV_Audio_StopCapture(MiniAVAudioContextHandle context);`
* *(Property API - TBD: Define specific properties like gain/volume/loopback if available)*
  * `MiniAV_Audio_GetProperty(...)`
  * `MiniAV_Audio_SetProperty(...)`

## Technical Considerations

* **Data Ownership & Buffer Strategy:**
  * The `MiniAVBuffer` passed to the `MiniAVBufferCallback` provides access to native buffer memory. The buffer's data pointers (`planes`, `data`) and its `internal_handle` are **valid after the callback returns**.
  * The user (e.g., the Dart FFI layer) is **responsible for explicitly releasing** the underlying native buffer when it is no longer needed by calling `MiniAV_ReleaseBuffer(buffer->internal_handle)` via FFI.
  * **Failure to call `MiniAV_ReleaseBuffer` will result in resource leaks** (e.g., holding onto camera frames, screen capture resources, audio buffers).
  * **Frame Drops:** If the user does not release buffers promptly via `MiniAV_ReleaseBuffer`, the underlying native capture APIs may run out of their internal buffers, potentially leading to dropped frames or errors. The exact behavior is platform-specific.
  * This explicit release mechanism allows the user to pass the raw data pointers (`buffer->data.video.planes[0]`, `buffer->data.audio.data`) and metadata to other libraries (like `minigpu`) for direct processing or GPU upload, avoiding a CPU-side copy in the FFI layer.
  * **Internal Buffering:** `miniav_c` itself aims to be a thin layer and generally does *not* implement deep internal buffering (like large circular buffers) beyond what native APIs provide. This avoids extra copies and latency within `miniav_c`. If the consuming application requires more complex buffering (e.g., queuing multiple frames), it should implement that logic *after* receiving the buffer pointer and release handle from the callback.
  * **Zero-Copy Goal:** Internally, `miniav_c` aims for zero-copy where platform APIs allow. This explicit release strategy enables consumers to leverage this by avoiding the Dart FFI copy, facilitating direct CPU->GPU uploads. True zero-copy (GPU texture sharing without CPU involvement) is highly platform-specific and complex, potentially a future enhancement beyond direct pointer access.

* **Threading:**
  * The `MiniAVBufferCallback` is invoked on an **internal library thread** managed by `miniav_c` (or potentially the underlying native API's thread).
  * Users **should still avoid long-running or blocking operations** within the callback itself to prevent potential frame drops or deadlocks. The recommended practice is to quickly extract the necessary pointers, metadata, and the `internal_handle`, then dispatch processing and the eventual call to `MiniAV_ReleaseBuffer` to a separate application thread or manage it asynchronously (e.g., after a GPU operation completes).
* **API Thread Safety:**
  * `_CreateContext`, `_DestroyContext`, `_Configure`, `_StartCapture`, `_StopCapture` functions remain generally **not thread-safe** for the *same* context handle.
  * `MiniAV_ReleaseBuffer` **must be thread-safe** internally within `miniav_c`, as it might be called from a different thread than the one invoking the callback. The implementation needs to handle potential synchronization if required by the underlying native API's buffer release mechanism.

* **Buffer Synchronization:**
  * The `timestamp_us` field in `MiniAVBuffer` provides the primary mechanism for synchronization.
  * It uses a **monotonic clock** source available on the platform (e.g., `QueryPerformanceCounter` on Windows, `mach_absolute_time` on macOS, `clock_gettime(CLOCK_MONOTONIC)` on Linux).
  * The epoch (zero point) of the timestamp is consistent *within a single capture session* (from `StartCapture` to `StopCapture`) for a given context, but may not be comparable across different contexts or application runs without calibration. It's often relative to the time `StartCapture` was called or system boot time.
  * Users needing to synchronize streams from different contexts (e.g., camera and audio) should record the timestamps from each stream and align them in their application logic. Small clock drifts between different hardware sources are possible.

* **Error Handling:**
  * Most functions return a `MiniAVResultCode`. `MINIAV_SUCCESS` indicates success.
  * Specific error codes provide context. `MiniAV_GetErrorString` can convert these to human-readable messages.
  * Logging (`MiniAV_SetLogCallback`) provides more detailed diagnostic information, especially for internal or system call failures.
  * There is no "get last error" function; errors are reported directly via return codes.
  * `MiniAV_ReleaseBuffer` should return a `MiniAVResultCode` (e.g., `MINIAV_SUCCESS`, `MINIAV_ERROR_INVALID_HANDLE`).

* **FFI Considerations (Dart):**
  * **Callbacks:** The `miniav_ffi` package manages `NativeCallable` lifetime. The `user_data` is crucial for associating the callback with Dart state.
  * **Pointer Ownership & Release:** The FFI layer receives the `MiniAVBuffer` pointer in the callback. It extracts the data pointers, metadata, and the `internal_handle`. It **must not copy** the pixel/audio data if zero-copy is desired. It needs to provide a mechanism (e.g., a Dart object representing the buffer) that holds the `internal_handle` and ensures `MiniAV_ReleaseBuffer` is called via FFI when the Dart object is disposed or the data is no longer needed (potentially using `NativeFinalizer` or manual calls).
  * **Structs & String Handling:** Ensure Dart struct definitions (`package:ffi`) precisely match the C layout and alignment. Use tools like `ffigen`. Be mindful of UTF-8 encoding for strings (`Utf8` pointers from `package:ffi`).

## Data Flow (Native via FFI - Explicit Release)

1. **Initialization:** Dart application calls an initialization method defined in `miniav_platform_interface`. The `miniav_ffi` implementation might call `MiniAV_Initialize` (C API) if needed.
2. **Context Creation:** Application requests a camera/screen/audio context via the platform interface. `miniav_ffi` calls the corresponding `MiniAV_<Type>_CreateContext` (C API) via FFI.
3. **Device Discovery:** Application calls device listing methods. `miniav_ffi` calls `MiniAV_<Type>_EnumerateDevices` (C API) via FFI. `miniav_c` executes platform-specific discovery code. Results are marshalled back to Dart, and the native list is freed using `MiniAV_FreeDeviceList`.
4. **Configuration:** Application selects device/format via Dart objects/methods. `miniav_ffi` translates these to C structs/calls (e.g., `MiniAV_Camera_Configure`).
5. **Capture Start:** Application calls start capture method, providing a Dart callback. `miniav_ffi` sets up a native FFI callback (`NativeCallable`) that wraps the Dart callback (potentially sending data via a `SendPort`) and passes its pointer (and user data containing necessary Dart state/ports) to `MiniAV_<Type>_StartCapture` (C API). `miniav_c` sets up the platform context and registers the native FFI callback.
6. **Data Production:**
    * The platform-specific C code (`miniav_c/src/<type>/<platform>/...`) captures data using native APIs.
    * It obtains a timestamp and populates a `miniAVBuffer`, including the `internal_handle` needed for release.
    * It invokes the native FFI callback pointer provided by `miniav_ffi`.
7. **Callback Invocation:** The native FFI callback executes. It reads the `MiniAVBuffer` data. It extracts the data pointers (`planes`/`data`), metadata (`width`, `height`, `format`, `timestamp_us`, etc.), and the `internal_handle`. It passes these pieces of information (potentially wrapped in a Dart object) to the Dart callback or `SendPort`. **No pixel/audio data is copied here.**
8. **Buffer Consumption:** The Dart application receives the pointers, metadata, and the release handle (e.g., within a custom Dart `MiniAVBuffer` object). It can now pass the data pointer and metadata to a consumer like `minigpu` for direct GPU upload or processing. The Dart object holds onto the `internal_handle`.
9. **GPU Interaction / Processing:** The consumer library (`minigpu`) uses the provided data pointer and metadata to perform its operations (e.g., upload to texture).
10. **Buffer Release:** Once the Dart application determines the buffer data is no longer needed (e.g., GPU upload is complete, processing is finished), it **must** trigger the release. This typically involves calling a method on the Dart `MiniAVBuffer` object which, in turn, calls the `MiniAV_ReleaseBuffer(internal_handle)` C function via FFI.
11. **Capture Stop:** Application calls stop method. `miniav_ffi` calls `MiniAV_<Type>_StopCapture` (C API). The associated `NativeCallable` can be freed. Any outstanding buffers should ideally be released before or shortly after stopping.
12. **Cleanup:** Application disposes of the context object. `miniav_ffi` calls `MiniAV_<Type>_DestroyContext` (C API).

## Considerations for Computer Vision

* **Metadata:** Accurate timestamps (monotonic clock), resolution, pixel format, and camera intrinsics (where available) are paramount. `miniav_c` must query these accurately.
* **Performance:** Prioritize low-latency paths within `miniav_c`. FFI overhead exists but the mandatory CPU copy is avoided with explicit release, enabling faster CPU->GPU transfers. Release call overhead should be minimal.
* **Synchronization:** Rely on accurate `timestamp_us` fields in `MiniAVBuffer` (passed through FFI) for application-level synchronization.
* **Intrinsics:** `miniav_c` implementations should attempt to query intrinsics. Provide API mechanisms (via FFI property system) to override or supply externally calibrated intrinsics.

## Conclusion

MiniAV provides a modular architecture designed for efficient AV capture and integration with compute pipelines like `minigpu`. By adopting an **explicit buffer release** mechanism in its C API (`MiniAV_ReleaseBuffer`), it allows consumers (via the `miniav_ffi` package) to access raw buffer pointers directly. This avoids CPU-side copies in Dart, enabling zero-copy workflows (direct CPU->GPU upload) on supported platforms and reducing latency for demanding CV tasks. The responsibility for timely buffer release lies with the user of the library.
