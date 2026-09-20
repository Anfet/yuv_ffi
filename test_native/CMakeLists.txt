# Test harness for yuv_ffi native C library
# This file is only processed when BUILD_TESTING=ON

# Enable strict compiler warnings for all test targets
if(MSVC)
    # MSVC flags: /W4 is equivalent to -Wall, /WX turns warnings into errors
    add_compile_options(/W4 /WX)
else()
    # GCC/Clang: -Wall -Wextra -Werror for strict warnings
    add_compile_options(-Wall -Wextra -Werror -Wstrict-prototypes -Wmissing-prototypes)
endif()

# Configure ASan/UBSan for supported platforms only
# AddressSanitizer and UndefinedBehaviorSanitizer are enabled on Linux and macOS
# with non-MSVC compilers (GCC, Clang). On Windows, Clang targets MSVC-compatible
# lld-link which does not provide integrated ASan/UBSan runtime, so sanitizers
# are disabled to avoid link errors (_wassert undefined symbols, ASan init conflicts).
# Tests still compile and run normally on Windows without sanitizers.
if((CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin") AND NOT MSVC)
    # Enable AddressSanitizer (ASan) and UndefinedBehaviorSanitizer (UBSan)
    # on GCC and Clang on supported platforms to detect memory errors and undefined behavior at runtime
    add_compile_options(-fsanitize=address -fsanitize=undefined)
    add_link_options(-fsanitize=address -fsanitize=undefined)
endif()

# Smoke test 1: basic assertions and boundary checks
# This test exercises the test harness itself and verifies it catches failures
add_executable(smoke_test smoke_test.c)
target_include_directories(smoke_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Mark this test as expected to fail, demonstrating that the harness correctly
# detects assertion failures. The test contains an intentional assertion that fails,
# and CMake will report it as a pass (meaning the failure was correctly caught).
add_test(
    NAME smoke_test_expected_failure
    COMMAND smoke_test
)
set_tests_properties(
    smoke_test_expected_failure
    PROPERTIES WILL_FAIL TRUE
)

# Smoke test 2: passing test to ensure normal tests work correctly
# This test verifies that the harness can also run and pass normal tests
add_executable(smoke_test_pass smoke_test_pass.c)
target_include_directories(smoke_test_pass PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME smoke_test_passing
    COMMAND smoke_test_pass
)

# Checked arithmetic boundary tests
# Tests the checked arithmetic helpers: add, multiply, ceil-half, plane span/size, sample offset
# Verifies overflow detection and correctness on boundary values (SIZE_MAX, 0, 1, etc.)
# The executable also compiles the library source under test directly (test_native/
# targets do not link against the yuv_ffi shared library target), so the helpers'
# implementation is part of this translation unit set, not just its header.
add_executable(checked_arithmetic_test
    checked_arithmetic_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(checked_arithmetic_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME checked_arithmetic_tests
    COMMAND checked_arithmetic_test
)

# Validated plane/frame view tests (YUV-33c)
# Tests the internal validated const/mutable plane and frame views: format IDs,
# plane counts, sample sizes, independent row/pixel strides, minimum spans, and
# destination geometry, per docs/api-abi-0.3-design.md sections 9-11. Covers
# null pointers, zero/negative geometry, undersized strides/spans, wrong plane
# count/sample size, incompatible destination geometry, and the allowed
# padded/custom-pixel-stride and odd-geometry cases for I420, NV12, BGRA8888,
# and RGBA8888. Uses only a stack placeholder as plane data (never dereferenced)
# so it needs no real allocation.
add_executable(validated_view_test
    validated_view_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(validated_view_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME validated_view_tests
    COMMAND validated_view_test
)

# ABI v1 layout test (YUV-36a)
# Verifies that the public wire-stable descriptor/options layout matches
# docs/api-abi-0.3-design.md sections 9-10 on this toolchain, and prints the
# actual sizeof/offsetof values so a reviewer on a new target (native32,
# native64, wasm32) can read them rather than infer them. The header itself
# also fails to compile on a mismatch; this target proves the same numbers at
# runtime and covers the status/format constant values. Header-only: there is
# no library source to compile in, because YUV-36a adds no exported symbol.
add_executable(abi_layout_test abi_layout_test.c)
target_include_directories(abi_layout_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_layout_tests
    COMMAND abi_layout_test
)

# Windows: document ASan/UBSan limitation
# On Windows, the standard LLVM/GCC sanitizers may not be available. Projects using
# this harness on Windows CI should either:
#  1. Use MSVC's /fsanitize=address (available in MSVC 16.4+)
#  2. Use a CI system that provides clang-cl or MinGW with sanitizer support
#  3. Document the limitation and rely on static analysis and manual testing
#
# For now, the tests compile and run on all platforms, but ASan/UBSan are only
# actively enabled on Linux and macOS.
