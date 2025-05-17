cmake_minimum_required(VERSION 3.15)
project(miniav_c LANGUAGES C CXX)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin/${CMAKE_BUILD_TYPE})

# --- Module Enable Options ---
option(MINIAV_ENABLE_AUDIO "Enable Audio Module (miniaudio)" OFF)
option(MINIAV_ENABLE_CAMERA "Enable Camera Capture Module" ON)
option(MINIAV_ENABLE_SCREEN "Enable Screen Capture Module" OFF)
option(MINIAV_ENABLE_LOOPBACK "Enable Audio Loopback Module" OFF)

# --- Backend Options ---
# Windows Screen Capture Backends
option(MINIAV_BACKEND_WIN_WGC "Enable WGC for Windows screen capture" ON)
option(MINIAV_BACKEND_WIN_DXGI "Enable DXGI for Windows screen capture" ON)

# Linux Camera Backends
option(MINIAV_BACKEND_LINUX_V4L2_CAMERA "Enable V4L2 for Linux camera capture" OFF)
option(MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA "Enable PipeWire for Linux camera capture (experimental)" ON)

# Linux Screen Capture Backends
option(MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN "Enable PipeWire for Linux screen capture" ON)
option(MINIAV_BACKEND_LINUX_X11_SCREEN "Enable X11 for Linux screen capture (fallback/experimental)" OFF)

# --- Standard & Settings ---
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Library Target ---
add_library(miniav_c SHARED)

# --- Initialize Lists for Sources, Includes, Libraries, Definitions ---
set(ALL_SOURCES "")
set(ALL_HEADERS "") # For files that are both source and header, or just headers to be part of the target
set(ALL_PRIVATE_INCLUDE_DIRS "")
set(ALL_LINK_LIBS "")
set(ALL_DEFINITIONS "")

# --- Common Sources & Public Headers (Always Included) ---
file(GLOB COMMON_SOURCES "src/common/*.c" "src/common/*.h")
list(APPEND ALL_SOURCES ${COMMON_SOURCES})
list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/common")

list(APPEND ALL_HEADERS
    "include/miniav_buffer.h"
    "include/miniav_capture.h"
    "include/miniav_types.h"
)
target_sources(miniav_c PRIVATE ${ALL_HEADERS}) # Add public headers to target for IDEs

target_include_directories(miniav_c PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# --- Platform-Specific Base Setup ---
if(WIN32)
    message(STATUS "Configuring for Windows")
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_WINDOWS")
    list(APPEND ALL_DEFINITIONS "MINIAV_BUILD_DLL") # For dllexport/dllimport
    target_compile_definitions(miniav_c PUBLIC MINIAV_DLL) # For consumers of the DLL
    list(APPEND ALL_LINK_LIBS ole32 uuid shlwapi) # Base libs for Windows
elseif(APPLE)
    message(STATUS "Configuring for macOS")
    enable_language(OBJC)
    enable_language(OBJCXX)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_MACOS")
    list(APPEND ALL_LINK_LIBS
        "-framework Foundation"
        "-framework CoreMedia"
        "-framework CoreVideo"
    )
elseif(UNIX AND NOT APPLE)
    message(STATUS "Configuring for Linux")
    find_package(PkgConfig REQUIRED)
    list(APPEND ALL_DEFINITIONS "MINIAV_PLATFORM_LINUX")
    list(APPEND ALL_LINK_LIBS pthread dl m) # Common Linux libs
else()
    message(WARNING "Unsupported platform for miniav_c build")
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
    list(APPEND ALL_DEFINITIONS "MA_NO_DECODING")
    list(APPEND ALL_DEFINITIONS "MA_NO_ENCODING")


    if(APPLE)
        list(APPEND ALL_LINK_LIBS "-framework CoreAudio" "-framework AudioToolbox")
    elseif(WIN32)
        # user32 might be needed by miniaudio, often linked by default or via other system libs
        # list(APPEND ALL_LINK_LIBS user32) # Add if explicit linking becomes necessary
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

    if(WIN32)
        message(STATUS "Windows: Enabling Media Foundation for camera.")
        list(APPEND ALL_SOURCES "src/camera/windows/camera_context_win_mf.c")
        list(APPEND ALL_HEADERS "src/camera/windows/camera_context_win_mf.h")
        list(APPEND ALL_LINK_LIBS mfplat mf mfreadwrite mfuuid ksuser)
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_MF_CAMERA_ENABLED")
    elseif(APPLE)
        message(STATUS "macOS: Enabling AVFoundation for camera.")
        list(APPEND ALL_SOURCES "src/camera/macos/camera_context_macos_avf.m")
        list(APPEND ALL_HEADERS "src/camera/macos/camera_context_macos_avf.h")
        list(APPEND ALL_LINK_LIBS "-framework AVFoundation")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_AVF_CAMERA_ENABLED")
    elseif(UNIX AND NOT APPLE)
        set(LINUX_CAMERA_BACKEND_FOUND FALSE)
        if(MINIAV_BACKEND_LINUX_V4L2_CAMERA)
            message(STATUS "Linux: Enabling V4L2 for camera.")
            list(APPEND ALL_SOURCES "src/camera/linux/camera_context_linux_v4l2.c")
            list(APPEND ALL_HEADERS "src/camera/linux/camera_context_linux_v4l2.h")
            pkg_check_modules(V4L2 REQUIRED libv4l2)
            list(APPEND ALL_LINK_LIBS ${V4L2_LIBRARIES})
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${V4L2_INCLUDE_DIRS})
            list(APPEND ALL_DEFINITIONS ${V4L2_CFLAGS_OTHER})
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_V4L2_CAMERA_ENABLED")
            set(LINUX_CAMERA_BACKEND_FOUND TRUE)
        endif()
        if(MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA)
            message(STATUS "Linux: Enabling PipeWire for camera.")
            list(APPEND ALL_SOURCES "src/camera/linux/camera_context_linux_pipewire.c") # Uncomment when implemented
            list(APPEND ALL_HEADERS "src/camera/linux/camera_context_linux_pipewire.h") # Uncomment when implemented
            pkg_check_modules(PIPEWIRE_CAMERA REQUIRED libpipewire-0.3) # Uncomment when implemented
            list(APPEND ALL_LINK_LIBS ${PIPEWIRE_CAMERA_LIBRARIES}) # Uncomment when implemented
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PIPEWIRE_CAMERA_INCLUDE_DIRS}) # Uncomment when implemented
            list(APPEND ALL_DEFINITIONS ${PIPEWIRE_CAMERA_CFLAGS_OTHER}) # Uncomment when implemented
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PIPEWIRE_CAMERA_ENABLED")
            set(LINUX_CAMERA_BACKEND_FOUND TRUE) # Uncomment when implemented
            message(WARNING "Linux: PipeWire camera backend is selected but not fully implemented in CMake script.")
        endif()
        if(NOT LINUX_CAMERA_BACKEND_FOUND)
            message(WARNING "Linux: Camera module enabled, but no camera backend (V4L2 or PipeWire) selected/implemented. Camera capture may not be available.")
        endif()
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

    if(WIN32)
        set(WIN_SCREEN_BACKEND_FOUND FALSE)
        if(MINIAV_BACKEND_WIN_WGC)
            message(STATUS "Windows: Enabling WGC for screen capture.")
            list(APPEND ALL_SOURCES "src/screen/windows/screen_context_win_wgc.cpp")
            list(APPEND ALL_HEADERS "src/screen/windows/screen_context_win_wgc.h")
            list(APPEND ALL_LINK_LIBS d3d11 dxgi)
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_WGC_ENABLED")
            set(WIN_SCREEN_BACKEND_FOUND TRUE)
        endif()
        if(MINIAV_BACKEND_WIN_DXGI)
            message(STATUS "Windows: Enabling DXGI for screen capture.")
            list(APPEND ALL_SOURCES "src/screen/windows/screen_context_win_dxgi.c")
            list(APPEND ALL_HEADERS "src/screen/windows/screen_context_win_dxgi.h")
            list(APPEND ALL_LINK_LIBS d3d11 dxgi) # DXGI also uses these
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_DXGI_ENABLED")
            set(WIN_SCREEN_BACKEND_FOUND TRUE)
        endif()
        if(NOT WIN_SCREEN_BACKEND_FOUND)
            message(WARNING "Windows: Screen module enabled, but no screen capture backend (WGC or DXGI) selected. Screen capture will not be available.")
        endif()
    elseif(APPLE)
        message(STATUS "macOS: Enabling CoreGraphics for screen capture.")
        list(APPEND ALL_SOURCES "src/screen/macos/screen_context_macos_cg.m")
        list(APPEND ALL_HEADERS "src/screen/macos/screen_context_macos_cg.h")
        list(APPEND ALL_LINK_LIBS "-framework CoreGraphics")
        # list(APPEND ALL_LINK_LIBS "-framework AppKit") # If AppKit specific APIs are used
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_CG_SCREEN_ENABLED")
    elseif(UNIX AND NOT APPLE)
        set(LINUX_SCREEN_BACKEND_FOUND FALSE)
        if(MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN)
            message(STATUS "Linux: Enabling PipeWire for screen capture.")
            list(APPEND ALL_SOURCES "src/screen/linux/screen_context_linux_pipewire.c")
            list(APPEND ALL_HEADERS "src/screen/linux/screen_context_linux_pipewire.h")
            pkg_check_modules(PIPEWIRE_SCREEN REQUIRED libpipewire-0.3 gio-unix-2.0) # Gio needed for portal
            list(APPEND ALL_LINK_LIBS ${PIPEWIRE_SCREEN_LIBRARIES})
            list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PIPEWIRE_SCREEN_INCLUDE_DIRS})
            list(APPEND ALL_DEFINITIONS ${PIPEWIRE_SCREEN_CFLAGS_OTHER})
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PIPEWIRE_SCREEN_ENABLED")
            set(LINUX_SCREEN_BACKEND_FOUND TRUE)
        endif()
        if(MINIAV_BACKEND_LINUX_X11_SCREEN)
            message(STATUS "Linux: Enabling X11 for screen capture.")
            # list(APPEND ALL_SOURCES "src/screen/linux/screen_context_linux_x11.c") # Uncomment when implemented
            # list(APPEND ALL_HEADERS "src/screen/linux/screen_context_linux_x11.h") # Uncomment when implemented
            # find_package(X11 REQUIRED) # Uncomment when implemented
            # list(APPEND ALL_LINK_LIBS ${X11_LIBRARIES}) # Uncomment when implemented
            # list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${X11_INCLUDE_DIRS}) # Uncomment when implemented
            list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_X11_SCREEN_ENABLED")
            # set(LINUX_SCREEN_BACKEND_FOUND TRUE) # Uncomment when implemented
            message(WARNING "Linux: X11 screen backend is selected but not fully implemented in CMake script.")
        endif()
        if(NOT LINUX_SCREEN_BACKEND_FOUND)
            message(WARNING "Linux: Screen module enabled, but no screen backend (PipeWire or X11) selected/implemented. Screen capture may not be available.")
        endif()
    endif()
else()
    message(STATUS "Screen module disabled")
endif()

# --- Loopback Audio Module ---
if(MINIAV_ENABLE_LOOPBACK)
    message(STATUS "Loopback audio module enabled")
    list(APPEND ALL_DEFINITIONS "MINIAV_MODULE_LOOPBACK_ENABLED")
    list(APPEND ALL_SOURCES "src/loopback/loopback_api.c")
    list(APPEND ALL_PRIVATE_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/src/loopback")

    if(WIN32)
        message(STATUS "Windows: Enabling WASAPI for loopback audio.")
        list(APPEND ALL_SOURCES "src/loopback/windows/loopback_context_win_wasapi.c")
        list(APPEND ALL_HEADERS "src/loopback/windows/loopback_context_win_wasapi.h")
        list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_WIN_WASAPI_LOOPBACK_ENABLED")
        # Dependencies (ole32) are usually covered by base Windows libs or miniaudio
    elseif(APPLE)
        message(WARNING "macOS: Loopback audio capture not yet implemented.")
        # list(APPEND ALL_SOURCES "src/loopback/macos/loopback_context_macos_coreaudio.m")
        # list(APPEND ALL_HEADERS "src/loopback/macos/loopback_context_macos_coreaudio.h")
        # list(APPEND ALL_LINK_LIBS "-framework AudioToolbox") # Example
        # list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_MACOS_COREAUDIO_LOOPBACK_ENABLED")
    elseif(UNIX AND NOT APPLE)
        message(WARNING "Linux: Loopback audio capture not yet implemented.")
        # list(APPEND ALL_SOURCES "src/loopback/linux/loopback_context_linux_pulse.c") # Example for PulseAudio
        # list(APPEND ALL_HEADERS "src/loopback/linux/loopback_context_linux_pulse.h")
        # pkg_check_modules(PULSEAUDIO REQUIRED libpulse)
        # list(APPEND ALL_LINK_LIBS ${PULSEAUDIO_LIBRARIES})
        # list(APPEND ALL_PRIVATE_INCLUDE_DIRS ${PULSEAUDIO_INCLUDE_DIRS})
        # list(APPEND ALL_DEFINITIONS "MINIAV_BACKEND_LINUX_PULSE_LOOPBACK_ENABLED")
    endif()
else()
    message(STATUS "Loopback audio module disabled")
endif()

# --- Apply all collected sources, includes, definitions, and libraries to the target ---
target_sources(miniav_c PRIVATE ${ALL_SOURCES} ${ALL_HEADERS})
target_include_directories(miniav_c PRIVATE ${ALL_PRIVATE_INCLUDE_DIRS})
target_compile_definitions(miniav_c PRIVATE ${ALL_DEFINITIONS})
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

# --- Test Executables (Conditional) ---
if(NOT CMAKE_SYSTEM_NAME MATCHES "(Android|iOS|Emscripten)")
    set(TEST_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/src" # For common test utilities if any
    )

    if(MINIAV_ENABLE_AUDIO)
        add_executable(test_audio_capture src/audio/test/test_audio_capture.c)
        target_link_libraries(test_audio_capture PRIVATE miniav_c)
        target_include_directories(test_audio_capture PRIVATE ${TEST_INCLUDE_DIRS})
        if(WIN32) # miniaudio test might need these explicitly if not pulled by miniav_c link
            target_link_libraries(test_audio_capture PRIVATE ole32 user32)
        endif()
        # install(TARGETS test_audio_capture DESTINATION bin)
    endif()

    if(MINIAV_ENABLE_CAMERA)
        add_executable(test_camera_capture src/camera/test/test_camera_capture.c)
        target_link_libraries(test_camera_capture PRIVATE miniav_c)
        target_include_directories(test_camera_capture PRIVATE ${TEST_INCLUDE_DIRS})
        # install(TARGETS test_camera_capture DESTINATION bin)
    endif()

    if(MINIAV_ENABLE_SCREEN)
        add_executable(test_screen_capture src/screen/test/test_screen_capture.c)
        target_link_libraries(test_screen_capture PRIVATE miniav_c)
        target_include_directories(test_screen_capture PRIVATE ${TEST_INCLUDE_DIRS})
        # install(TARGETS test_screen_capture DESTINATION bin)
    endif()

    if(MINIAV_ENABLE_LOOPBACK)
        add_executable(test_loopback_capture src/loopback/test/test_loopback_capture.c)
        target_link_libraries(test_loopback_capture PRIVATE miniav_c)
        target_include_directories(test_loopback_capture PRIVATE ${TEST_INCLUDE_DIRS})
        # install(TARGETS test_loopback_capture DESTINATION bin)
    endif()
endif()

# --- Output Summary ---
message(STATUS "--- Miniav_c Configuration Summary ---")
message(STATUS "Enabled Modules:")

if(MINIAV_ENABLE_AUDIO)    
    message(STATUS "  - Audio") 
endif()
if(MINIAV_ENABLE_CAMERA)   
    message(STATUS "  - Camera") 
endif()
if(MINIAV_ENABLE_SCREEN)   
    message(STATUS "  - Screen") 
endif()
if(MINIAV_ENABLE_LOOPBACK) 
    message(STATUS "  - Loopback") 
endif()

message(STATUS "Selected Definitions: ${ALL_DEFINITIONS}")
# message(STATUS "Final Sources: ${ALL_SOURCES}") # Can be very verbose
# message(STATUS "Final Link Libraries: ${ALL_LINK_LIBS}") # Can be verbose
message(STATUS "--- End Summary ---")