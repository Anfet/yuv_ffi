# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(yuv_ffi_library VERSION 0.0.1 LANGUAGES C)

set_property(GLOBAL PROPERTY CMAKE_CONFIGURE_DEPENDS "yuv/*.c")

# Собираем все исходники из папки yuv/
file(GLOB_RECURSE SOURCES "yuv/*.c" "yuv_ffi.c" "**/*.c")
add_library(
    yuv_ffi SHARED ${SOURCES} "yuv_ffi.c"
)

target_include_directories(
        yuv_ffi
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
        PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
        PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/yuv
)

set_target_properties(yuv_ffi PROPERTIES
        PUBLIC_HEADER yuv_ffi.h
        OUTPUT_NAME "yuv_ffi"
)

target_compile_definitions(yuv_ffi PUBLIC DART_SHARED_LIB)

# --- Optimization ---
#
# The conversion loops are the hot path of this plugin: a 1080p i420 -> BGRA8888
# frame measures ~31 ms unoptimized and ~8.8 ms at -O3 on the same machine, so
# the flag is worth roughly 3.6x on every operation.
#
# Flags are applied only to non-Debug configurations so that debug builds stay
# steppable. Single-config generators (Ninja/Makefiles, used by Android and
# Linux) report the type in CMAKE_BUILD_TYPE; multi-config generators (Visual
# Studio, Xcode) resolve $<CONFIG> per build, so the generator expression covers
# both without branching on the generator.
if (MSVC)
    target_compile_options(yuv_ffi PRIVATE $<$<NOT:$<CONFIG:Debug>>:/O2>)
else ()
    target_compile_options(yuv_ffi PRIVATE $<$<NOT:$<CONFIG:Debug>>:-O3>)
endif ()

# Baseline SIMD only. `-march=native` is deliberately NOT used: it targets the
# build machine, and a binary built on a newer CPU crashes on an older one.
# arm64 always has NEON and x86_64 always has SSE2, so the default baseline
# already allows vectorization on every supported target.

# --- Platform-specific linking ---

# Android: link with liblog for __android_log_print
if (ANDROID)
    target_link_libraries(yuv_ffi log)
    # Android 15: 16k page size support
    target_link_options(yuv_ffi PRIVATE "-Wl,-z,max-page-size=16384")

    # Windows: link with basic system libraries (optional)
elseif (WIN32)
    target_link_libraries(yuv_ffi PRIVATE)

elseif (APPLE)
    find_library(CORE_FOUNDATION CoreFoundation)
    if (CORE_FOUNDATION)
        target_link_libraries(yuv_ffi PRIVATE ${CORE_FOUNDATION})
    endif()
endif()
