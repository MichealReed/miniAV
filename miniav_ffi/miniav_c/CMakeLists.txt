cmake_minimum_required(VERSION 3.15)
project(miniav_c LANGUAGES C CXX)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})

# --- Options ---
option(MINIAV_ENABLE_DIRECTSHOW_FALLBACK "Enable DirectShow fallback for camera on Windows" OFF)
option(MINIAV_ENABLE_GDI_FALLBACK "Enable GDI fallback for screen capture on Windows" OFF)
option(MINIAV_ENABLE_X11_FALLBACK "Enable X11 fallback for screen capture on Linux" OFF)
option(MINIAV_ENABLE_PIPEWIRE_CAMERA "Enable PipeWire camera support on Linux" OFF) # Default to V4L2

# --- Standard & Settings ---
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Library Target ---
add_library(miniav_c SHARED)

# --- Source Files ---
# Common Sources
file(GLOB COMMON_SOURCES
    "src/common/*.c"
    "src/common/*.h"
)

# Audio Sources (using miniaudio)
file(GLOB AUDIO_SOURCES
    "src/audio/*.c"
    "src/audio/*.h"
)

set(MINIAUDIO_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio/miniaudio.c")

# Camera API Source
set(CAMERA_API_SOURCE "src/camera/camera_api.c")

# Screen API Source
set(SCREEN_API_SOURCE "src/screen/screen_api.c")

# Platform-Specific Sources
set(PLATFORM_SOURCES "")
set(PLATFORM_HEADERS "")
set(PLATFORM_LINK_LIBS "")
set(PLATFORM_DEFINITIONS "")

if(WIN32)
    message(STATUS "Configuring for Windows")
    set(PLATFORM_SOURCES
        "src/camera/windows/camera_context_win_mf.c"
        "src/screen/windows/screen_context_win_dxgi.c"
    )
    set(PLATFORM_HEADERS
        "src/camera/windows/camera_context_win_mf.h"
        "src/screen/windows/screen_context_win_dxgi.h"
    )
    set(PLATFORM_LINK_LIBS
        mfplat # Media Foundation Platform
        mfreadwrite # Media Foundation Source Reader
        mfuuid # Media Foundation UUIDs
        dxgi # DXGI for Desktop Duplication
        d3d11 # Required by DXGI
    )
    list(APPEND PLATFORM_DEFINITIONS "MINIAV_PLATFORM_WINDOWS")

    if(MINIAV_ENABLE_DIRECTSHOW_FALLBACK)
        message(STATUS "Enabling DirectShow fallback")
        list(APPEND PLATFORM_SOURCES "src/camera/windows/camera_context_win_ds.c")
        # list(APPEND PLATFORM_HEADERS "src/camera/windows/camera_context_win_ds.h") # Add if header exists
        list(APPEND PLATFORM_LINK_LIBS strmiids quartz) # DirectShow libs
        list(APPEND PLATFORM_DEFINITIONS "MINIAV_SUPPORT_DIRECTSHOW")
    endif()
    if(MINIAV_ENABLE_GDI_FALLBACK)
        message(STATUS "Enabling GDI fallback")
        list(APPEND PLATFORM_SOURCES "src/screen/windows/screen_context_win_gdi.c")
        # list(APPEND PLATFORM_HEADERS "src/screen/windows/screen_context_win_gdi.h") # Add if header exists
        list(APPEND PLATFORM_LINK_LIBS gdi32 user32) # GDI libs
        list(APPEND PLATFORM_DEFINITIONS "MINIAV_SUPPORT_GDI")
    endif()

    # Definition for building DLL
    list(APPEND PLATFORM_DEFINITIONS "MINIAV_BUILD_DLL")

elseif(APPLE)
    message(STATUS "Configuring for macOS")
    # Enable Objective-C
    enable_language(OBJC)
    enable_language(OBJCXX)

    set(PLATFORM_SOURCES
        "src/camera/macos/camera_context_macos_avf.m"
        "src/screen/macos/screen_context_macos_cg.m" # Or screen_context_macos_avf.m
    )
    set(PLATFORM_HEADERS
        "src/camera/macos/camera_context_macos_avf.h"
        "src/screen/macos/screen_context_macos_cg.h" # Or screen_context_macos_avf.h
    )
    # Link against macOS Frameworks
    set(PLATFORM_LINK_LIBS
        "-framework Foundation"
        "-framework AVFoundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
        "-framework CoreGraphics" # For CGDisplayStream or AVF screen input
        # "-framework AppKit" # May be needed depending on specific APIs used
    )
    list(APPEND PLATFORM_DEFINITIONS "MINIAV_PLATFORM_MACOS")

elseif(UNIX AND NOT APPLE)
    message(STATUS "Configuring for Linux")
    # Camera: Default V4L2
    list(APPEND PLATFORM_SOURCES "src/camera/linux/camera_context_linux_v4l2.c")
    list(APPEND PLATFORM_HEADERS "src/camera/linux/camera_context_linux_v4l2.h")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(V4L2 REQUIRED libv4l2)
    list(APPEND PLATFORM_LINK_LIBS ${V4L2_LIBRARIES})
    list(APPEND PLATFORM_DEFINITIONS ${V4L2_CFLAGS_OTHER}) # Include definitions from pkg-config

    if(MINIAV_ENABLE_PIPEWIRE_CAMERA)
        message(STATUS "Enabling PipeWire camera support")
        # Add PipeWire camera source and link dependency if implemented
        # list(APPEND PLATFORM_SOURCES "src/camera/linux/camera_context_linux_pipewire.c")
        # list(APPEND PLATFORM_HEADERS "src/camera/linux/camera_context_linux_pipewire.h")
        # pkg_check_modules(PIPEWIRE_CAMERA REQUIRED libpipewire-0.3)
        # list(APPEND PLATFORM_LINK_LIBS ${PIPEWIRE_CAMERA_LIBRARIES})
        # list(APPEND PLATFORM_DEFINITIONS ${PIPEWIRE_CAMERA_CFLAGS_OTHER})
        list(APPEND PLATFORM_DEFINITIONS "MINIAV_SUPPORT_PIPEWIRE_CAMERA")
    endif()

    # Screen: Default PipeWire
    message(STATUS "Enabling PipeWire screen capture support")
    list(APPEND PLATFORM_SOURCES "src/screen/linux/screen_context_linux_pipewire.c")
    list(APPEND PLATFORM_HEADERS "src/screen/linux/screen_context_linux_pipewire.h")
    pkg_check_modules(PIPEWIRE_SCREEN REQUIRED libpipewire-0.3 gio-unix-2.0) # Gio needed for portal
    list(APPEND PLATFORM_LINK_LIBS ${PIPEWIRE_SCREEN_LIBRARIES})
    list(APPEND PLATFORM_DEFINITIONS ${PIPEWIRE_SCREEN_CFLAGS_OTHER})
    list(APPEND PLATFORM_DEFINITIONS "MINIAV_SUPPORT_PIPEWIRE_SCREEN")

    if(MINIAV_ENABLE_X11_FALLBACK)
        message(STATUS "Enabling X11 fallback")
        # Add X11 source and link dependencies if implemented
        # list(APPEND PLATFORM_SOURCES "src/screen/linux/screen_context_linux_x11.c")
        # list(APPEND PLATFORM_HEADERS "src/screen/linux/screen_context_linux_x11.h")
        # find_package(X11 REQUIRED)
        # list(APPEND PLATFORM_LINK_LIBS ${X11_LIBRARIES})
        list(APPEND PLATFORM_DEFINITIONS "MINIAV_SUPPORT_X11")
    endif()

    list(APPEND PLATFORM_DEFINITIONS "MINIAV_PLATFORM_LINUX")
    # Add pthread if needed explicitly (often handled by compiler/miniaudio)
    # list(APPEND PLATFORM_LINK_LIBS pthread)

else()
    message(WARNING "Unsupported platform for miniav_c build")
endif()

# --- Target Sources ---
target_sources(miniav_c PRIVATE
    ${COMMON_SOURCES}
    ${AUDIO_SOURCES}
    ${CAMERA_API_SOURCE}
    ${SCREEN_API_SOURCE}
    ${PLATFORM_SOURCES}
    ${PLATFORM_HEADERS}
    "include/miniav_buffer.h"
    "include/miniav_capture.h"
    "include/miniav_types.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio/miniaudio.h"
)

# --- Target Include Directories ---
target_include_directories(miniav_c
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src/common
        ${CMAKE_CURRENT_SOURCE_DIR}/src/audio
        ${CMAKE_CURRENT_SOURCE_DIR}/src/camera
        ${CMAKE_CURRENT_SOURCE_DIR}/src/screen
        # Add platform specific include dirs if they exist and are needed internally
        # ${CMAKE_CURRENT_SOURCE_DIR}/src/camera/windows
        # ... etc
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniaudio
        ${V4L2_INCLUDE_DIRS} # Include V4L2 headers if found
        ${PIPEWIRE_SCREEN_INCLUDE_DIRS} # Include PipeWire headers if found
        # ${PIPEWIRE_CAMERA_INCLUDE_DIRS} # Include PipeWire headers if found
        # ${X11_INCLUDE_DIRS} # Include X11 headers if found
)

# --- Target Compile Definitions ---
target_compile_definitions(miniav_c
    PRIVATE
        ${PLATFORM_DEFINITIONS}
)
target_compile_definitions(miniav_c PRIVATE MINIAUDIO_IMPLEMENTATION)

# Public definitions if needed (e.g., for DLL import/export)
if(WIN32)
    target_compile_definitions(miniav_c PUBLIC MINIAV_DLL) # Assume headers use this for dllexport/import
endif()


# --- Target Link Libraries ---
target_link_libraries(miniav_c
    PRIVATE
        ${PLATFORM_LINK_LIBS}
        $<$<PLATFORM_ID:Linux>:pthread dl m>
)

# --- Installation ---
# Install the library, public headers, and potentially CMake config files
include(GNUInstallDirs)
install(TARGETS miniav_c
    EXPORT miniav_cTargets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(DIRECTORY include/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

if(NOT CMAKE_SYSTEM_NAME MATCHES "(Android|iOS|Emscripten)")
    add_executable(test_audio_capture src/audio/test/test_audio_capture.c)

    # Link the test against the miniav_c library
    target_link_libraries(test_audio_capture PRIVATE miniav_c)

    # Add include directories for the test
    target_include_directories(test_audio_capture PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/src" # If common headers are needed
    )

    # Add platform-specific libraries needed by miniaudio (already linked by miniav_c usually)
    # This might already be handled by linking miniav_c, but explicitly:
    if(WIN32)
        target_link_libraries(test_audio_capture PRIVATE ole32 user32)
    elseif(APPLE)
        target_link_libraries(test_audio_capture PRIVATE "-framework CoreFoundation -framework CoreAudio -framework AudioToolbox")
    elseif(UNIX AND NOT APPLE AND NOT ANDROID)
        # Assuming PulseAudio or ALSA linked via miniav_c
        # May need explicit linking depending on miniaudio config
        # target_link_libraries(test_audio_capture PRIVATE pthread dl m)
    endif()

    # Optional: Install the test executable if desired
    # install(TARGETS test_audio_capture DESTINATION bin)
endif()

# --- Output ---
message(STATUS "miniav_c sources: ${COMMON_SOURCES};${AUDIO_SOURCES};${CAMERA_API_SOURCE};${SCREEN_API_SOURCE};${PLATFORM_SOURCES}")
message(STATUS "miniav_c include_dirs: ${CMAKE_CURRENT_SOURCE_DIR}/include;${CMAKE_CURRENT_SOURCE_DIR}/src/common;...")
message(STATUS "miniav_c link libs: MiniAudio::miniaudio;${PLATFORM_LINK_LIBS}")
message(STATUS "miniav_c definitions: ${PLATFORM_DEFINITIONS}")
