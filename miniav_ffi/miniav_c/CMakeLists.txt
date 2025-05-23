cmake_minimum_required(VERSION 3.15)
project(miniav_c LANGUAGES C CXX)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})

# --- Platform Detection ---
set(MINIAV_PLATFORM_WINDOWS FALSE)
set(MINIAV_PLATFORM_MACOS FALSE)
set(MINIAV_PLATFORM_IOS FALSE)
set(MINIAV_PLATFORM_LINUX FALSE)
set(MINIAV_PLATFORM_ANDROID FALSE)
set(MINIAV_PLATFORM_WEB FALSE)

if(WIN32)
    set(MINIAV_PLATFORM_WINDOWS TRUE)
    set(MINIAV_PLATFORM_NAME "Windows")
elseif(APPLE)
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(MINIAV_PLATFORM_IOS TRUE)
        set(MINIAV_PLATFORM_NAME "iOS")
    else()
        set(MINIAV_PLATFORM_MACOS TRUE)
        set(MINIAV_PLATFORM_NAME "macOS")
    endif()
elseif(ANDROID)
    set(MINIAV_PLATFORM_ANDROID TRUE)
    set(MINIAV_PLATFORM_NAME "Android")
elseif(EMSCRIPTEN)
    set(MINIAV_PLATFORM_WEB TRUE)
    set(MINIAV_PLATFORM_NAME "Web")
elseif(UNIX)
    set(MINIAV_PLATFORM_LINUX TRUE)
    set(MINIAV_PLATFORM_NAME "Linux")
else()
    message(FATAL_ERROR "Unsupported platform for miniav_c")
endif()

message(STATUS "Configuring miniav_c for ${MINIAV_PLATFORM_NAME}")

# --- Module Enable Options ---
option(MINIAV_ENABLE_AUDIO "Enable Audio Module (miniaudio)" ON)
option(MINIAV_ENABLE_CAMERA "Enable Camera Capture Module" ON)
option(MINIAV_ENABLE_SCREEN "Enable Screen Capture Module" ON)

# Loopback is only supported on desktop platforms
if(MINIAV_PLATFORM_WINDOWS OR MINIAV_PLATFORM_MACOS OR MINIAV_PLATFORM_LINUX)
    option(MINIAV_ENABLE_LOOPBACK "Enable Audio Loopback Module" ON)
else()
    set(MINIAV_ENABLE_LOOPBACK OFF CACHE BOOL "Audio Loopback not supported on mobile/web platforms" FORCE)
    message(STATUS "Loopback audio disabled: not supported on ${MINIAV_PLATFORM_NAME}")
endif()

# --- Backend Options ---
# Windows Backends
if(MINIAV_PLATFORM_WINDOWS)
    option(MINIAV_BACKEND_WIN_WGC "Enable WGC for Windows screen capture" ON)
    option(MINIAV_BACKEND_WIN_DXGI "Enable DXGI for Windows screen capture" ON)
    option(MINIAV_BACKEND_WIN_MF "Enable Media Foundation for Windows camera" ON)
    option(MINIAV_BACKEND_WIN_WASAPI "Enable WASAPI for Windows loopback audio" ON)
endif()

# macOS Backends
if(MINIAV_PLATFORM_MACOS)
    option(MINIAV_BACKEND_MACOS_AVF "Enable AVFoundation for macOS camera" ON)
    option(MINIAV_BACKEND_MACOS_CG "Enable CoreGraphics for macOS screen capture" ON)
    option(MINIAV_BACKEND_MACOS_SCK "Enable ScreenCaptureKit for macOS screen capture (macOS 12.3+)" ON)
    option(MINIAV_BACKEND_MACOS_COREAUDIO "Enable CoreAudio/AudioTaps for macOS loopback audio" ON)
endif()

# iOS Backends
if(MINIAV_PLATFORM_IOS)
    option(MINIAV_BACKEND_IOS_AVF "Enable AVFoundation for iOS camera" ON)
    option(MINIAV_BACKEND_IOS_REPLAYKIT "Enable ReplayKit for iOS screen recording" ON)
endif()

# Linux Backends
if(MINIAV_PLATFORM_LINUX)
    option(MINIAV_BACKEND_LINUX_V4L2_CAMERA "Enable V4L2 for Linux camera capture" OFF)
    option(MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA "Enable PipeWire for Linux camera capture" ON)
    option(MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN "Enable PipeWire for Linux screen capture" ON)
    option(MINIAV_BACKEND_LINUX_X11_SCREEN "Enable X11 for Linux screen capture (fallback)" OFF)
    option(MINIAV_BACKEND_LINUX_PIPEWIRE_LOOPBACK "Enable PipeWire for Linux loopback audio" ON)
endif()

# Android Backends
if(MINIAV_PLATFORM_ANDROID)
    option(MINIAV_BACKEND_ANDROID_CAMERA2 "Enable Camera2 API for Android camera" ON)
    option(MINIAV_BACKEND_ANDROID_NDK_CAMERA "Enable NDK Camera API for Android camera" OFF)
    option(MINIAV_BACKEND_ANDROID_MEDIAPROJECTION "Enable MediaProjection for Android screen capture" ON)
endif()

# Web Backends
if(MINIAV_PLATFORM_WEB)
    option(MINIAV_BACKEND_WEB_WEBRTC "Enable WebRTC APIs for web capture" ON)
endif()

# --- Standard & Settings ---
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable Objective-C for Apple platforms
if(MINIAV_PLATFORM_MACOS OR MINIAV_PLATFORM_IOS)
    enable_language(OBJC)
    enable_language(OBJCXX)
endif()

# --- Library Target ---
add_library(miniav_c SHARED)

# --- Initialize Lists ---
set(ALL_SOURCES "")
set(ALL_HEADERS "")
set(ALL_PRIVATE_INCLUDE_DIRS "")
set(ALL_LINK_LIBS "")
set(ALL_DEFINITIONS "")
set(ALL_COMPILE_OPTIONS "")

# --- Common Sources & Public Headers (Always Included) ---
file(GLOB COMMON_SOURCES "src/common/*.c" "src/common/*.h")
list(APPEND ALL_SOURCES ${COMMON_SOURCES})
list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/common")

list(APPEND ALL_HEADERS
    "include/miniav_buffer.h"
    "include/miniav_capture.h"
    "include/miniav_types.h"
)

target_include_directories(miniav_c PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# --- Platform-Specific Base Setup ---
if(MINIAV_PLATFORM_WINDOWS)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_WINDOWS")
    list(APPEND ALL_DEFINITIONS "MINIAV_BUILD_DLL")
    target_compile_definitions(miniav_c PUBLIC MINIAV_DLL)
    list(APPEND ALL_LINK_LIBS ole32 uuid shlwapi)
    
elseif(MINIAV_PLATFORM_MACOS)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_MACOS")
    list(APPEND ALL_LINK_LIBS
        "-framework Foundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
    )
    
elseif(MINIAV_PLATFORM_IOS)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_IOS")
    list(APPEND ALL_LINK_LIBS
        "-framework Foundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework UIKit"
    )
    
elseif(MINIAV_PLATFORM_LINUX)
    find_package(PkgConfig REQUIRED)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_LINUX")
    list(APPEND ALL_LINK_LIBS pthread dl m)
    
elseif(MINIAV_PLATFORM_ANDROID)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_ANDROID")
    list(APPEND ALL_LINK_LIBS android log)
    
elseif(MINIAV_PLATFORM_WEB)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_WEB")
    # Emscripten-specific flags will be added later
endif()

# --- Audio Module (miniaudio) ---
if(MINIAV_ENABLE_AUDIO)
    message(STATUS "Audio module enabled")
    list(APPEND ALL_DEFINITIONS "MINIAV_MODULE_AUDIO_ENABLED")
    
    file(GLOB AUDIO_MODULE_SOURCES "src/audio/*.c" "src/audio/*.h")
    list(APPEND ALL_SOURCES ${AUDIO_MODULE_SOURCES})
    list(APPEND ALL_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio/miniaudio.c")
    list(APPEND ALL_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio/miniaudio.h")
    list(APPEND ALL_PRIVATE_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/src/audio"
        "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio"
    )
    
    list(APPEND ALL_DEFINITIONS "MA_NO_DECODING" "MA_NO_ENCODING")

    # Platform-specific audio setup
    if(MINIAV_PLATFORM_MACOS OR MINIAV_PLATFORM_IOS)
        list(APPEND ALL_LINK_LIBS "-framework CoreAudio" "-framework AudioToolbox")
    endif()
else()
    message(STATUS "Audio module disabled")
endif()

# --- Camera Module ---
if(MINIAV_ENABLE_CAMERA)
    message(STATUS "Camera module enabled")
    list(APPEND ALL_DEFINITIONS "MINIAV_MODULE_CAMERA_ENABLED")
    list(APPEND ALL_SOURCES "src/camera/camera_api.c")
    list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/camera")

    if(MINIAV_PLATFORM_WINDOWS AND MINIAV_BACKEND_WIN_MF)
        message(STATUS "Windows: Enabling Media Foundation for camera")
        list(APPEND ALL_SOURCES "src/camera/windows/camera_context_win_mf.c")
        list(APPEND ALL_HEADERS "src/camera/windows/camera_context_win_mf.h")
        list(APPEND ALL_LINK_LIBS mfplat mf mfreadwrite mfuuid ksuser)
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_MF_CAMERA_ENABLED")
        
    elseif(MINIAV_PLATFORM_MACOS AND MINIAV_BACKEND_MACOS_AVF)
        message(STATUS "macOS: Enabling AVFoundation for camera")
        list(APPEND ALL_SOURCES "src/camera/macos/camera_context_macos_avf.m")
        list(APPEND ALL_HEADERS "src/camera/macos/camera_context_macos_avf.h")
        list(APPEND ALL_LINK_LIBS "-framework AVFoundation")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_AVF_CAMERA_ENABLED")
        
    elseif(MINIAV_PLATFORM_IOS AND MINIAV_BACKEND_IOS_AVF)
        message(STATUS "iOS: Enabling AVFoundation for camera")
        list(APPEND ALL_SOURCES "src/camera/ios/camera_context_ios_avf.m")
        list(APPEND ALL_HEADERS "src/camera/ios/camera_context_ios_avf.h")
        list(APPEND ALL_LINK_LIBS "-framework AVFoundation")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_IOS_AVF_CAMERA_ENABLED")
        
    elseif(MINIAV_PLATFORM_LINUX)
        set(LINUX_CAMERA_BACKEND_FOUND FALSE)
        
        if(MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA)
            message(STATUS "Linux: Enabling PipeWire for camera")
            list(APPEND ALL_SOURCES "src/camera/linux/camera_context_linux_pipewire.c")
            list(APPEND ALL_HEADERS "src/camera/linux/camera_context_linux_pipewire.h")
            pkg_check_modules(PIPEWIRE_CAMERA REQUIRED libpipewire-0.3)
            list(APPEND ALL_LINK_LIBS ${PIPEWIRE_CAMERA_LIBRARIES})
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PIPEWIRE_CAMERA_INCLUDE_DIRS})
            list(APPEND ALL_DEFINITIONS ${PIPEWIRE_CAMERA_DEFINITIONS})
            list(APPEND ALL_COMPILE_OPTIONS ${PIPEWIRE_CAMERA_COMPILE_OPTIONS})
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA_ENABLED")
            set(LINUX_CAMERA_BACKEND_FOUND TRUE)
        endif()
        
        if(MINIAV_BACKEND_LINUX_V4L2_CAMERA)
            message(STATUS "Linux: Enabling V4L2 for camera")
            list(APPEND ALL_SOURCES "src/camera/linux/camera_context_linux_v4l2.c")
            list(APPEND ALL_HEADERS "src/camera/linux/camera_context_linux_v4l2.h")
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_V4L2_CAMERA_ENABLED")
            set(LINUX_CAMERA_BACKEND_FOUND TRUE)
        endif()
        
        if(NOT LINUX_CAMERA_BACKEND_FOUND)
            message(WARNING "Linux: No camera backend selected. Camera capture will not be available.")
        endif()
        
    elseif(MINIAV_PLATFORM_ANDROID)
        if(MINIAV_BACKEND_ANDROID_CAMERA2)
            message(STATUS "Android: Enabling Camera2 API for camera")
            list(APPEND ALL_SOURCES "src/camera/android/camera_context_android_camera2.c")
            list(APPEND ALL_HEADERS "src/camera/android/camera_context_android_camera2.h")
            list(APPEND ALL_LINK_LIBS camera2ndk mediandk)
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_ANDROID_CAMERA2_ENABLED")
        endif()
        
        if(MINIAV_BACKEND_ANDROID_NDK_CAMERA)
            message(STATUS "Android: Enabling NDK Camera API for camera")
            list(APPEND ALL_SOURCES "src/camera/android/camera_context_android_ndk.c")
            list(APPEND ALL_HEADERS "src/camera/android/camera_context_android_ndk.h")
            list(APPEND ALL_LINK_LIBS camera2ndk)
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_ANDROID_NDK_CAMERA_ENABLED")
        endif()
        
    elseif(MINIAV_PLATFORM_WEB AND MINIAV_BACKEND_WEB_WEBRTC)
        message(STATUS "Web: Enabling WebRTC APIs for camera")
        list(APPEND ALL_SOURCES "src/camera/web/camera_context_web_webrtc.c")
        list(APPEND ALL_HEADERS "src/camera/web/camera_context_web_webrtc.h")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WEB_WEBRTC_CAMERA_ENABLED")
    endif()
else()
    message(STATUS "Camera module disabled")
endif()

# --- Screen Module ---
if(MINIAV_ENABLE_SCREEN)
    message(STATUS "Screen module enabled")
    list(APPEND ALL_DEFINITIONS "MINIAV_MODULE_SCREEN_ENABLED")
    list(APPEND ALL_SOURCES "src/screen/screen_api.c")
    list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/screen")

    if(MINIAV_PLATFORM_WINDOWS)
        set(WIN_SCREEN_BACKEND_FOUND FALSE)
        
        if(MINIAV_BACKEND_WIN_WGC)
            message(STATUS "Windows: Enabling WGC for screen capture")
            list(APPEND ALL_SOURCES "src/screen/windows/screen_context_win_wgc.cpp")
            list(APPEND ALL_HEADERS "src/screen/windows/screen_context_win_wgc.h")
            list(APPEND ALL_LINK_LIBS d3d11 dxgi)
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_WGC_ENABLED")
            set(WIN_SCREEN_BACKEND_FOUND TRUE)
        endif()
        
        if(MINIAV_BACKEND_WIN_DXGI)
            message(STATUS "Windows: Enabling DXGI for screen capture")
            list(APPEND ALL_SOURCES "src/screen/windows/screen_context_win_dxgi.c")
            list(APPEND ALL_HEADERS "src/screen/windows/screen_context_win_dxgi.h")
            list(APPEND ALL_LINK_LIBS d3d11 dxgi)
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_DXGI_ENABLED")
            set(WIN_SCREEN_BACKEND_FOUND TRUE)
        endif()
        
        if(NOT WIN_SCREEN_BACKEND_FOUND)
            message(WARNING "Windows: No screen capture backend selected")
        endif()
        
    elseif(MINIAV_PLATFORM_MACOS)
        if(MINIAV_BACKEND_MACOS_SCK)
            message(STATUS "macOS: Enabling ScreenCaptureKit for screen capture")
            list(APPEND ALL_SOURCES "src/screen/macos/screen_context_macos_sck.m")
            list(APPEND ALL_HEADERS "src/screen/macos/screen_context_macos_sck.h")
            list(APPEND ALL_LINK_LIBS "-framework ScreenCaptureKit")
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_SCK_SCREEN_ENABLED")
        endif()
        
        if(MINIAV_BACKEND_MACOS_CG)
            message(STATUS "macOS: Enabling CoreGraphics for screen capture")
            list(APPEND ALL_SOURCES "src/screen/macos/screen_context_macos_cg.m")
            list(APPEND ALL_HEADERS "src/screen/macos/screen_context_macos_cg.h")
            list(APPEND ALL_LINK_LIBS "-framework CoreGraphics")
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_CG_SCREEN_ENABLED")
        endif()
        
    elseif(MINIAV_PLATFORM_IOS AND MINIAV_BACKEND_IOS_REPLAYKIT)
        message(STATUS "iOS: Enabling ReplayKit for screen recording")
        list(APPEND ALL_SOURCES "src/screen/ios/screen_context_ios_replaykit.m")
        list(APPEND ALL_HEADERS "src/screen/ios/screen_context_ios_replaykit.h")
        list(APPEND ALL_LINK_LIBS "-framework ReplayKit")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_IOS_REPLAYKIT_SCREEN_ENABLED")
        
    elseif(MINIAV_PLATFORM_LINUX)
        set(LINUX_SCREEN_BACKEND_FOUND FALSE)
        
        if(MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN)
            message(STATUS "Linux: Enabling PipeWire for screen capture")
            list(APPEND ALL_SOURCES "src/screen/linux/screen_context_linux_pipewire.c")
            list(APPEND ALL_HEADERS "src/screen/linux/screen_context_linux_pipewire.h")
            pkg_check_modules(PIPEWIRE_SCREEN REQUIRED libpipewire-0.3 gio-unix-2.0)
            list(APPEND ALL_LINK_LIBS ${PIPEWIRE_SCREEN_LIBRARIES})
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PIPEWIRE_SCREEN_INCLUDE_DIRS})
            list(APPEND ALL_DEFINITIONS ${PIPEWIRE_SCREEN_DEFINITIONS})
            list(APPEND ALL_COMPILE_OPTIONS ${PIPEWIRE_SCREEN_COMPILE_OPTIONS})
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN_ENABLED")
            set(LINUX_SCREEN_BACKEND_FOUND TRUE)
        endif()
        
        if(MINIAV_BACKEND_LINUX_X11_SCREEN)
            message(STATUS "Linux: Enabling X11 for screen capture")
            list(APPEND ALL_SOURCES "src/screen/linux/screen_context_linux_x11.c")
            list(APPEND ALL_HEADERS "src/screen/linux/screen_context_linux_x11.h")
            find_package(X11 REQUIRED)
            list(APPEND ALL_LINK_LIBS ${X11_LIBRARIES})
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${X11_INCLUDE_DIRS})
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_X11_SCREEN_ENABLED")
            set(LINUX_SCREEN_BACKEND_FOUND TRUE)
        endif()
        
        if(NOT LINUX_SCREEN_BACKEND_FOUND)
            message(WARNING "Linux: No screen capture backend selected")
        endif()
        
    elseif(MINIAV_PLATFORM_ANDROID AND MINIAV_BACKEND_ANDROID_MEDIAPROJECTION)
        message(STATUS "Android: Enabling MediaProjection for screen capture")
        list(APPEND ALL_SOURCES "src/screen/android/screen_context_android_mediaprojection.c")
        list(APPEND ALL_HEADERS "src/screen/android/screen_context_android_mediaprojection.h")
        list(APPEND ALL_LINK_LIBS mediandk)
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_ANDROID_MEDIAPROJECTION_SCREEN_ENABLED")
        
    elseif(MINIAV_PLATFORM_WEB AND MINIAV_BACKEND_WEB_WEBRTC)
        message(STATUS "Web: Enabling WebRTC APIs for screen capture")
        list(APPEND ALL_SOURCES "src/screen/web/screen_context_web_webrtc.c")
        list(APPEND ALL_HEADERS "src/screen/web/screen_context_web_webrtc.h")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WEB_WEBRTC_SCREEN_ENABLED")
    endif()
else()
    message(STATUS "Screen module disabled")
endif()

# --- Loopback Audio Module (Desktop Only) ---
if(MINIAV_ENABLE_LOOPBACK)
    message(STATUS "Loopback audio module enabled")
    list(APPEND ALL_DEFINITIONS "MINIAV_MODULE_LOOPBACK_ENABLED")
    list(APPEND ALL_SOURCES "src/loopback/loopback_api.c")
    list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/loopback")

    if(MINIAV_PLATFORM_WINDOWS AND MINIAV_BACKEND_WIN_WASAPI)
        message(STATUS "Windows: Enabling WASAPI for loopback audio")
        list(APPEND ALL_SOURCES "src/loopback/windows/loopback_context_win_wasapi.c")
        list(APPEND ALL_HEADERS "src/loopback/windows/loopback_context_win_wasapi.h")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_WASAPI_LOOPBACK_ENABLED")
        
    elseif(MINIAV_PLATFORM_MACOS AND MINIAV_BACKEND_MACOS_COREAUDIO)
        message(STATUS "macOS: Enabling CoreAudio/AudioTaps for loopback audio")
        list(APPEND ALL_SOURCES "src/loopback/macos/loopback_context_macos_coreaudio.mm")
        list(APPEND ALL_HEADERS "src/loopback/macos/loopback_context_macos_coreaudio.h")
        list(APPEND ALL_LINK_LIBS "-framework AudioToolbox" "-framework CoreAudio")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_COREAUDIO_LOOPBACK_ENABLED")
        
    elseif(MINIAV_PLATFORM_LINUX AND MINIAV_BACKEND_LINUX_PIPEWIRE_LOOPBACK)
        message(STATUS "Linux: Enabling PipeWire for loopback audio")
        list(APPEND ALL_SOURCES "src/loopback/linux/loopback_context_linux_pipewire.c")
        list(APPEND ALL_HEADERS "src/loopback/linux/loopback_context_linux_pipewire.h")
        pkg_check_modules(PIPEWIRE_LOOPBACK REQUIRED libpipewire-0.3)
        list(APPEND ALL_LINK_LIBS ${PIPEWIRE_LOOPBACK_LIBRARIES})
        list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PIPEWIRE_LOOPBACK_INCLUDE_DIRS})
        list(APPEND ALL_DEFINITIONS ${PIPEWIRE_LOOPBACK_DEFINITIONS})
        list(APPEND ALL_COMPILE_OPTIONS ${PIPEWIRE_LOOPBACK_COMPILE_OPTIONS})
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PIPEWIRE_LOOPBACK_ENABLED")
    endif()
else()
    message(STATUS "Loopback audio module disabled")
endif()

# --- Web-specific Setup ---
if(MINIAV_PLATFORM_WEB)
    # Emscripten-specific compile flags
    list(APPEND ALL_COMPILE_OPTIONS
        "-s" "USE_WEBGL2=1"
        "-s" "WASM=1"
        "--bind"
    )
    
    # Emscripten-specific link flags
    target_link_options(miniav_c PRIVATE
        "-s" "USE_WEBGL2=1"
        "-s" "WASM=1"
        "-s" "ALLOW_MEMORY_GROWTH=1"
        "--bind"
    )
endif()

# --- Android-specific Setup ---
if(MINIAV_PLATFORM_ANDROID)
    # Android NDK API level
    if(NOT ANDROID_NATIVE_API_LEVEL)
        set(ANDROID_NATIVE_API_LEVEL 21) # Minimum API level for Camera2
    endif()
    
    list(APPEND ALL_DEFINITIONS "MINIAV_ANDROID_API_LEVEL=${ANDROID_NATIVE_API_LEVEL}")
    
    # JNI support for accessing Java APIs
    find_library(ANDROID_JNI_LIB jnigraphics)
    if(ANDROID_JNI_LIB)
        list(APPEND ALL_LINK_LIBS ${ANDROID_JNI_LIB})
    endif()
endif()

# --- Apply all collected settings to the target ---
target_sources(miniav_c PRIVATE ${ALL_SOURCES} ${ALL_HEADERS})
target_include_directories(miniav_c PRIVATE ${ALL_PRIVATE_INCLUDE_DIRS})
target_compile_definitions(miniav_c PRIVATE ${ALL_DEFINITIONS})
target_compile_options(miniav_c PRIVATE ${ALL_COMPILE_OPTIONS})
target_link_libraries(miniav_c PRIVATE ${ALL_LINK_LIBS})

# --- Installation ---
include(GNUInstallDirs)
install(TARGETS miniav_c
    EXPORT miniav_cTargets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    FILES_MATCHING PATTERN "*.h"
)

# --- Test Executables (Desktop Only) ---
if(MINIAV_PLATFORM_WINDOWS OR MINIAV_PLATFORM_MACOS OR MINIAV_PLATFORM_LINUX)
    set(TEST_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
    )

    if(MINIAV_ENABLE_AUDIO)
        add_executable(test_audio_capture src/audio/test/test_audio_capture.c)
        target_link_libraries(test_audio_capture PRIVATE miniav_c)
        target_include_directories(test_audio_capture PRIVATE ${TEST_INCLUDE_DIRS})
        if(MINIAV_PLATFORM_WINDOWS)
            target_link_libraries(test_audio_capture PRIVATE ole32 user32)
        endif()
    endif()

    if(MINIAV_ENABLE_CAMERA)
        add_executable(test_camera_capture src/camera/test/test_camera_capture.c)
        target_link_libraries(test_camera_capture PRIVATE miniav_c)
        target_include_directories(test_camera_capture PRIVATE ${TEST_INCLUDE_DIRS})
    endif()

    if(MINIAV_ENABLE_SCREEN)
        add_executable(test_screen_capture src/screen/test/test_screen_capture.c)
        target_link_libraries(test_screen_capture PRIVATE miniav_c)
        target_include_directories(test_screen_capture PRIVATE ${TEST_INCLUDE_DIRS})
    endif()

    if(MINIAV_ENABLE_LOOPBACK)
        add_executable(test_loopback_capture src/loopback/test/test_loopback_capture.c)
        target_link_libraries(test_loopback_capture PRIVATE miniav_c)
        target_include_directories(test_loopback_capture PRIVATE ${TEST_INCLUDE_DIRS})
    endif()
else()
    message(STATUS "Test executables disabled on ${MINIAV_PLATFORM_NAME}")
endif()

# --- Configuration Summary ---
message(STATUS "")
message(STATUS "=== MiniAV Configuration Summary ===")
message(STATUS "Platform: ${MINIAV_PLATFORM_NAME}")
message(STATUS "")
message(STATUS "Enabled Modules:")
if(MINIAV_ENABLE_AUDIO)    
    message(STATUS "  ✓ Audio") 
else()
    message(STATUS "  ✗ Audio")
endif()
if(MINIAV_ENABLE_CAMERA)   
    message(STATUS "  ✓ Camera") 
else()
    message(STATUS "  ✗ Camera")
endif()
if(MINIAV_ENABLE_SCREEN)   
    message(STATUS "  ✓ Screen") 
else()
    message(STATUS "  ✗ Screen")
endif()
if(MINIAV_ENABLE_LOOPBACK) 
    message(STATUS "  ✓ Loopback Audio") 
else()
    message(STATUS "  ✗ Loopback Audio")
endif()

message(STATUS "")
message(STATUS "Active Backends:")
foreach(def ${ALL_DEFINITIONS})
    if(def MATCHES "MINIAV_BACKEND_.*_ENABLED")
        string(REGEX REPLACE "MINIAV_BACKEND_(.*)_ENABLED" "\\1" backend_name ${def})
        string(REPLACE "_" " " backend_name_clean ${backend_name})
        message(STATUS "  ✓ ${backend_name_clean}")
    endif()
endforeach()

message(STATUS "")
message(STATUS "Build Configuration:")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C Standard: C${CMAKE_C_STANDARD}")
message(STATUS "  CXX Standard: C++${CMAKE_CXX_STANDARD}")
if(MINIAV_PLATFORM_ANDROID)
    message(STATUS "  Android API Level: ${ANDROID_NATIVE_API_LEVEL}")
endif()

message(STATUS "")
message(STATUS "=====================================")