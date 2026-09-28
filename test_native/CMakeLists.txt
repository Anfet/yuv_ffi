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
#
# The check is written as "this platform, and NOT MSVC" rather than as a
# negation of one compiler: NOT MSVC is also true for clang-cl and for clang
# targeting the MSVC ABI on Windows, where ASan's runtime is not the
# integrated one this flag combination assumes. Gating on the actual
# supported platform pair is what keeps that combination out, not a
# compiler-name check that would let it back in.
if((CMAKE_SYSTEM_NAME STREQUAL "Linux" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin") AND NOT MSVC)
    # Enable AddressSanitizer (ASan) and UndefinedBehaviorSanitizer (UBSan)
    # on GCC and Clang on supported platforms to detect memory errors and undefined behavior at runtime
    add_compile_options(-fsanitize=address -fsanitize=undefined)
    add_link_options(-fsanitize=address -fsanitize=undefined)

    # LeakSanitizer is bundled into ASan on x86_64/i386/arm64; no separate
    # -fsanitize=leak flag is needed,
    # and adding one is in fact rejected by the Linux ASan runtime ("-fsanitize=
    # leak is incompatible with enabled -fsanitize=address"). It is NOT
    # supported by ASan on macOS at all (Darwin's ASan silently disables leak
    # detection), so LSAN_OPTIONS/ASAN_OPTIONS=detect_leaks=1 is exported only
    # where it is stably supported: Linux.
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set(YUV_FFI_LSAN_SUPPORTED TRUE)
    else()
        set(YUV_FFI_LSAN_SUPPORTED FALSE)
    endif()
else()
    set(YUV_FFI_LSAN_SUPPORTED FALSE)
endif()

# abi_sanitizer_test.c uses the GNU/gold/lld ELF linker's --wrap to inject
# controlled allocation failures into the ABI v1 blur entry points, the only
# ones that allocate.
# --wrap is a linker feature, not a compiler one, and is not available from
# MSVC's link.exe or from lld-link's MSVC-compatible driver -- only from an
# ELF-targeting linker. That is exactly the Linux/non-MSVC condition already
# established above for the sanitizers themselves, so the same guard is
# reused rather than re-deriving a second one.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND NOT MSVC)
    set(YUV_FFI_MALLOC_WRAP_SUPPORTED TRUE)
else()
    set(YUV_FFI_MALLOC_WRAP_SUPPORTED FALSE)
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

# Tests the internal validated const/mutable plane and frame views: formats,
# plane counts, sample sizes, independent row/pixel strides, minimum spans, and
# destination geometry. Covers
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

# Verifies the public descriptor/options layout at compile time and at runtime,
# prints sizeof/offsetof values, and checks status/format constant values.
add_executable(abi_layout_test abi_layout_test.c)
target_include_directories(abi_layout_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_layout_tests
    COMMAND abi_layout_test
)

# Exercises the eleven yuv_*_v1 entry points through their shared validation
# prologue: reachable validation statuses have concrete descriptor or options
# cases, while reserved status 3 has its numeric value pinned. Negative cases
# check that the destination buffer remains byte-for-byte unchanged (canary
# fill). Compiles the ABI sources directly, as the other test_native
# targets do, rather than linking the shared library.
add_executable(abi_status_test
    abi_status_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_convert_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_black_white_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_grayscale_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_negate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_gaussian_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_mean_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_box_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_crop_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_flip_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_rotate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_chroma_swap_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_status_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_status_tests
    COMMAND abi_status_test
)

# Verifies crop, flip, and rotate against an independent visible-pixel oracle
# across I420, NV12, and BGRA8888 at even, odd, and
# degenerate (1x1, 1xN, Nx1) geometry. Every fixture carries padded row
# strides and canary-filled gaps, so a kernel that copies a row stride or a
# pixel stride instead of a sample is caught rather than merely suspected.
add_executable(abi_transform_test
    abi_transform_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_crop_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_flip_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_rotate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_transform_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_transform_tests
    COMMAND abi_transform_test
)

# Tests parity: the same image presented as RGBA and as BGRA
# must convert to identical YUV samples, which fails for either half of the
# conversion contract (matrix selection or chroma averaging). Absolute values
# are additionally pinned
# against the reference oracle transcribed into the test, so two paths that
# agree and are both wrong still fail.
add_executable(abi_convert_test
    abi_convert_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_convert_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_convert_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_convert_tests
    COMMAND abi_convert_test
)

# Tests grayscale rounding, the black-white `>= 128` threshold, and RGB-visible
# negate across I420, NV12 and BGRA. BGRA is also compared with the exact oracle
# result, and all three formats must agree on the visible output.
add_executable(abi_effect_test
    abi_effect_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_grayscale_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_black_white_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_negate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_chroma_swap_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_effect_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_effect_tests
    COMMAND abi_effect_test
)

# The test verifies that prior destination contents do not affect results,
# alpha and bytes outside the region are preserved, and edges use replication.
# Assertions include flat-image preservation and a hand-computed vector.
add_executable(abi_blur_test
    abi_blur_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_mean_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_box_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_gaussian_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_blur_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

add_test(
    NAME abi_blur_tests
    COMMAND abi_blur_test
)

# Calls all eleven exported ABI v1 entry points against frames whose planes are
# each their own exact-length heap allocation, so a kernel that steps outside a
# plane trips ASan's own heap redzone rather than only a manually placed byte.
# Row/column padding gaps are filled with a canary and checked byte-for-byte.
# The cases cover each operation family, transforms, chroma swap, region
# processing, exact-fit allocations, repeated allocate/free cycles, invalid
# inputs, and checked-arithmetic overflow.
add_executable(abi_sanitizer_test
    abi_sanitizer_test.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_validate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_kernel_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_convert_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_grayscale_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_black_white_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_negate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_chroma_swap_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_gaussian_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_mean_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_box_blur_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_crop_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_flip_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/abi/yuv_rotate_v1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/validated_view.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../src/yuv/utils/checked_arithmetic.c
)
target_include_directories(abi_sanitizer_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)

if(YUV_FFI_MALLOC_WRAP_SUPPORTED)
    # Only the ELF/GNU-family linker accepts --wrap; guarded above by the same
    # Linux-and-not-MSVC condition the sanitizer flags use.
    target_compile_definitions(abi_sanitizer_test PRIVATE ENABLE_MALLOC_WRAP)
    target_link_options(abi_sanitizer_test PRIVATE -Wl,--wrap=malloc)
endif()

add_test(
    NAME abi_sanitizer_tests
    COMMAND abi_sanitizer_test
)

if(YUV_FFI_LSAN_SUPPORTED)
    set_tests_properties(abi_sanitizer_tests PROPERTIES ENVIRONMENT "ASAN_OPTIONS=detect_leaks=1")
endif()

# Windows: document ASan/UBSan limitation
# On Windows, the standard LLVM/GCC sanitizers may not be available. Projects using
# this harness on Windows CI should either:
#  1. Use MSVC's /fsanitize=address (available in MSVC 16.4+)
#  2. Use a CI system that provides clang-cl or MinGW with sanitizer support
#  3. Document the limitation and rely on static analysis and manual testing
#
# For now, the tests compile and run on all platforms, but ASan/UBSan are only
# actively enabled on Linux and macOS.
