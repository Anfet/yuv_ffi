# PERF-01 native benchmark harness (doc/perf/PERF-01-bench-setup.md).
#
# Builds one executable, yuv_bench, that loads the library under test at run time
# (--dll), so the same build measures the 0.2.4 DLL and the ABI v1 DLL. The harness
# never compiles either library's sources; only the ABI v1 *type* header is included.
#
#   cmake -S tool/bench/native -B <build> -G "Visual Studio 17 2022" -A x64
#   cmake --build <build> --config Release
#
# Release uses the CMake defaults (/MD /O2 /Ob2 /DNDEBUG), the same flags the measured
# DLLs are built with.

cmake_minimum_required(VERSION 3.20)
project(yuv_bench LANGUAGES C)

if(NOT WIN32)
  message(FATAL_ERROR "yuv_bench is Windows-only: it uses QueryPerformanceCounter, CNG and LoadLibraryExW.")
endif()

# Types only (descriptors, options, status); the header declares no symbols. The ABI v1
# layout is wire-stable and asserted at compile time, so the working-tree copy is safe
# to use for every measured SHA.
set(YUV_ABI_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/yuv/abi/h"
    CACHE PATH "Directory that contains yuv_abi_v1.h")

if(NOT EXISTS "${YUV_ABI_INCLUDE_DIR}/yuv_abi_v1.h")
  message(FATAL_ERROR "yuv_abi_v1.h not found in YUV_ABI_INCLUDE_DIR=${YUV_ABI_INCLUDE_DIR}")
endif()

add_executable(yuv_bench bench_main.c)
target_include_directories(yuv_bench PRIVATE "${YUV_ABI_INCLUDE_DIR}")
target_compile_definitions(yuv_bench PRIVATE WIN32_LEAN_AND_MEAN _CRT_SECURE_NO_WARNINGS UNICODE _UNICODE)
target_link_libraries(yuv_bench PRIVATE bcrypt)

if(MSVC)
  target_compile_options(yuv_bench PRIVATE /W4)
endif()
