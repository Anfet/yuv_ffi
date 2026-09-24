cmake_minimum_required(VERSION 3.10)

project(yuv_ffi_native_tests LANGUAGES C)

# This is the root CMakeLists.txt for the yuv_ffi project. It enables testing
# infrastructure and pulls in both the main library (src/) and optional test targets
# (src/tests/). Tests are only built when BUILD_TESTING=ON is explicitly passed
# to cmake; by default, BUILD_TESTING is OFF to avoid affecting the normal Flutter
# plugin build.

# src/CMakeLists.txt declares its own project() directive too, retaining its
# standalone compatibility with Android build.gradle and platform-specific CMake
# entry points. The root still needs its own project() call to be a valid
# top-level CMake project and avoid CMake's developer warning.

# Option to enable building and running C unit tests.
option(BUILD_TESTING "Build C unit tests for yuv_ffi" OFF)

# Include the main library CMakeLists.txt, which builds the yuv_ffi shared library.
add_subdirectory(src)

# If tests are enabled, set up the test infrastructure and add test targets.
if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(test_native)
endif()
