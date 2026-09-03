# 3.16 is the floor for enable_language(OBJCXX), which the Apple backend needs.
cmake_minimum_required(VERSION 3.16)
project(miniav_media_session_native C)

# Native half of miniav_media_session: publishes now-playing state to the OS
# shell and routes transport commands back.
#
# Links NOTHING from miniav_c, FFmpeg or minigpu. This library is deliberately
# tiny and dependency-free — an app should be able to adopt "tell the shell what
# is playing" without inheriting a decode stack.

set(MINIAV_MS_PUBLIC_SOURCES
  src/media_session_api.c
)

# Per-platform backend switches. Each defaults ON where its platform can build
# it; turning one OFF falls back to the honest placeholder, which is how a
# platform gets bisected when its shell integration misbehaves.
option(MINIAV_MS_ENABLE_SMTC "Windows System Media Transport Controls" ON)
option(MINIAV_MS_ENABLE_NOWPLAYING "macOS/iOS MPNowPlayingInfoCenter" ON)
option(MINIAV_MS_ENABLE_ANDROID_SESSION "Android MediaSession" OFF)
# OFF and staying off: the Linux backend is implemented in Dart
# (lib/src/backend_mpris.dart), because MPRIS is a D-Bus wire protocol rather
# than an OS API. Linux therefore builds this library with the placeholder and
# never calls into it — the Dart factory routes Platform.isLinux to MPRIS
# before the code asset is touched.
option(MINIAV_MS_ENABLE_MPRIS "Linux MPRIS over D-Bus (superseded by Dart)" OFF)

# --- Backend selection --------------------------------------------------------
# Exactly one backend TU provides ms_platform_*; see src/media_session_internal.h.
# To land a real backend, add its source here for that platform and drop it from
# the placeholder branch. Keep the placeholder as the else-branch so an
# unhandled platform still LINKS and still reports UNSUPPORTED honestly, rather
# than failing to build or silently succeeding.
if(WIN32 AND MINIAV_MS_ENABLE_SMTC)
  enable_language(CXX)
  set(MINIAV_MS_BACKEND_SOURCES src/windows/media_session_smtc.cpp)
  set(MINIAV_MS_BACKEND_NAME "smtc")
elseif(APPLE AND MINIAV_MS_ENABLE_NOWPLAYING)
  enable_language(OBJCXX)
  set(MINIAV_MS_BACKEND_SOURCES src/apple/media_session_nowplaying.mm)
  set(MINIAV_MS_BACKEND_NAME "nowplaying")
elseif(ANDROID AND MINIAV_MS_ENABLE_ANDROID_SESSION)
  set(MINIAV_MS_BACKEND_SOURCES src/android/media_session_android.c)
  set(MINIAV_MS_BACKEND_NAME "androidsession")
elseif(UNIX AND NOT APPLE AND MINIAV_MS_ENABLE_MPRIS)
  set(MINIAV_MS_BACKEND_SOURCES src/linux/media_session_mpris.c)
  set(MINIAV_MS_BACKEND_NAME "mpris")
else()
  set(MINIAV_MS_BACKEND_SOURCES src/media_session_unimplemented.c)
  set(MINIAV_MS_BACKEND_NAME "unimplemented")
endif()

message(STATUS "miniav_media_session backend: ${MINIAV_MS_BACKEND_NAME}")

add_library(miniav_media_session_native SHARED
  ${MINIAV_MS_PUBLIC_SOURCES}
  ${MINIAV_MS_BACKEND_SOURCES}
)

set_target_properties(miniav_media_session_native PROPERTIES
  C_STANDARD 11
  # C++/WinRT requires C++17 at minimum; 20 is what the rest of the repo builds
  # its WinRT translation units with.
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  OUTPUT_NAME "miniav_media_session_native"
  # Symbols are exported explicitly via MINIAV_MS_API. Hiding the rest keeps the
  # placeholder's ms_platform_* internal, so a consumer cannot bind to them and
  # then break when a real backend replaces the TU.
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_include_directories(miniav_media_session_native
  PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Platform link deps are attached to the BACKEND, not to the platform: the
# placeholder needs none of them, and demanding windowsapp.lib or
# MediaPlayer.framework to build a file that calls neither would turn a missing
# SDK component into a build failure for a library that does not use it.
if(MINIAV_MS_BACKEND_NAME STREQUAL "smtc")
  # WinRT activation surface (SystemMediaTransportControls lives here).
  target_link_libraries(miniav_media_session_native PRIVATE windowsapp)
  # C++/WinRT propagates failures as exceptions (winrt::hresult_error), so the
  # backend needs real unwinding. Without /EHsc MSVC compiles the catch blocks
  # but does not guarantee they run.
  target_compile_options(miniav_media_session_native PRIVATE /EHsc)
elseif(MINIAV_MS_BACKEND_NAME STREQUAL "nowplaying")
  target_link_libraries(miniav_media_session_native PRIVATE
    "-framework Foundation"
    "-framework MediaPlayer"
  )
  if(IOS)
    target_link_libraries(miniav_media_session_native PRIVATE "-framework UIKit")
  else()
    target_link_libraries(miniav_media_session_native PRIVATE "-framework AppKit")
  endif()
  # ARC. The backend allocates Objective-C objects and stores them in a C++
  # struct without any manual retain/release — under MRR every one of those
  # would leak, and the artwork ones are megabytes each.
  set_source_files_properties(src/apple/media_session_nowplaying.mm
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
endif()
