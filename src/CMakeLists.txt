# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(yuv_ffi_library VERSION 0.0.1 LANGUAGES C)

# Explicit source list (rooted at CMAKE_CURRENT_SOURCE_DIR so paths are
# correct whether this file is configured standalone or pulled in via
# add_subdirectory from windows/, linux/ or android/build.gradle).
#
# This is deliberately NOT a file(GLOB_RECURSE ...): CONFIGURE_DEPENDS (the
# only mechanism that would make a glob notice new files without a manual
# cache clear) requires CMake 3.12, and this project intentionally keeps
# cmake_minimum_required(VERSION 3.10) to support Android tooling that may
# resolve an unpinned CMake 3.10.2. A plain glob without CONFIGURE_DEPENDS
# would silently miss newly added sources until the cache is cleared, which
# is worse than an explicit list.
#
# Adding a new .c file therefore requires adding it here. test/cmake_sources_test.dart
# keeps this list honest: it fails if a source under src/ is missing from
# this list, or if this list contains a name not on disk, or a duplicate.
set(SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv_ffi.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/utils/gauss.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/utils/checked_arithmetic.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/utils/validated_view.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_validate_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_kernel_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_convert_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_black_white_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_grayscale_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_negate_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_gaussian_blur_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_mean_blur_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_box_blur_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_crop_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_flip_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_rotate_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_chroma_swap_v1.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_blackwhite.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_block_uv.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_box_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_crop.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_flip.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_from_rgba.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_gaussblur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_grayscale.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_mean_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_negate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_rotate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_to_i420.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/bgra8888/bgra8888_to_nv21.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_blackwhite.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_box_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_crop.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_flip.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_from_rgba8888.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_gaussblur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_grayscale.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_mean_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_negate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_rotate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_to_420.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_to_bgra8888.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/nv21/nv21_to_nv12.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_blackwhite.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_box_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_crop.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_flip.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_from_rgba.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_gaussblur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_grayscale.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_mean_blur.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_negate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_rotate.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_to_bgra.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/yuv/yuv420/yuv420_to_nv21.c"
)
add_library(
    yuv_ffi SHARED ${SOURCES}
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
