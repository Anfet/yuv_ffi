/*
 * ABI v1 layout test (YUV-36a).
 *
 * The header src/yuv/abi/h/yuv_abi_v1.h already fails to COMPILE on a target
 * whose layout differs from doc/api-abi-0.4-design.md sections 9 and 10. This
 * test adds the other half of the same guarantee: it prints the layout the
 * toolchain actually produced, so a reviewer on a new target (native32,
 * native64, wasm32) can read the real numbers instead of trusting that the
 * build "just passed", and it re-checks each documented row at runtime.
 *
 * Why the checks are not written as plain constant expressions: MSVC reports
 * C4127 ("conditional expression is constant") for a comparison of two
 * compile-time constants, and the harness builds with /W4 /WX, so such a
 * check would fail the build rather than run. Both sides of every comparison
 * therefore pass through a `volatile` local, which forces the comparison to be
 * evaluated at runtime.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>

#include "yuv/abi/h/yuv_abi_v1.h"

static int test_count = 0;
static int failures = 0;

/*
 * Routes both operands through volatile locals so the comparison happens at
 * runtime (see the C4127 note above), reports the actual and expected values
 * on mismatch, and keeps going so one run reports every broken row rather
 * than only the first.
 *
 * Failure is reported through the exit code, never abort(): on Windows an
 * abort() exits with 0xC0000409, which CTest does not treat as an ordinary
 * non-zero return.
 */
static void expect_size(const char *label, size_t actual, size_t expected) {
    volatile size_t a = actual;
    volatile size_t e = expected;

    test_count++;
    printf("  %-48s %4zu", label, (size_t)a);
    if (a == e) {
        printf("  ok\n");
    } else {
        printf("  FAIL (expected %zu)\n", (size_t)e);
        failures++;
    }
}

static void test_plane_layout(void) {
    printf("YuvConstPlaneV1 / YuvMutablePlaneV1 (section 9)\n");

    expect_size("offsetof(YuvConstPlaneV1, length)", offsetof(YuvConstPlaneV1, length), 0);
    expect_size("offsetof(YuvConstPlaneV1, rowStride)", offsetof(YuvConstPlaneV1, rowStride), 8);
    expect_size("offsetof(YuvConstPlaneV1, pixelStride)", offsetof(YuvConstPlaneV1, pixelStride), 16);
    expect_size("offsetof(YuvConstPlaneV1, sampleBytes)", offsetof(YuvConstPlaneV1, sampleBytes), 20);
    expect_size("offsetof(YuvConstPlaneV1, data)", offsetof(YuvConstPlaneV1, data), 24);
    expect_size("sizeof(YuvConstPlaneV1)", sizeof(YuvConstPlaneV1), 32);

    expect_size("offsetof(YuvMutablePlaneV1, length)", offsetof(YuvMutablePlaneV1, length), 0);
    expect_size("offsetof(YuvMutablePlaneV1, rowStride)", offsetof(YuvMutablePlaneV1, rowStride), 8);
    expect_size("offsetof(YuvMutablePlaneV1, pixelStride)", offsetof(YuvMutablePlaneV1, pixelStride), 16);
    expect_size("offsetof(YuvMutablePlaneV1, sampleBytes)", offsetof(YuvMutablePlaneV1, sampleBytes), 20);
    expect_size("offsetof(YuvMutablePlaneV1, data)", offsetof(YuvMutablePlaneV1, data), 24);
    expect_size("sizeof(YuvMutablePlaneV1)", sizeof(YuvMutablePlaneV1), 32);

    /* The plane `data` member is the only one whose width legitimately differs
     * between native64 and native32/wasm32. Asserting it against sizeof(void *)
     * rather than a literal is what makes the single 32-byte plane descriptor
     * valid on all three. */
    expect_size("sizeof(YuvConstPlaneV1::data) vs sizeof(void *)",
        sizeof(((YuvConstPlaneV1 *)0)->data), sizeof(void *));
    expect_size("sizeof(YuvMutablePlaneV1::data) vs sizeof(void *)",
        sizeof(((YuvMutablePlaneV1 *)0)->data), sizeof(void *));
}

static void test_frame_layout(void) {
    printf("YuvConstFrameV1 / YuvMutableFrameV1 (section 9)\n");

    expect_size("offsetof(YuvConstFrameV1, structSize)", offsetof(YuvConstFrameV1, structSize), 0);
    expect_size("offsetof(YuvConstFrameV1, abiVersion)", offsetof(YuvConstFrameV1, abiVersion), 4);
    expect_size("offsetof(YuvConstFrameV1, format)", offsetof(YuvConstFrameV1, format), 8);
    expect_size("offsetof(YuvConstFrameV1, planeCount)", offsetof(YuvConstFrameV1, planeCount), 12);
    expect_size("offsetof(YuvConstFrameV1, width)", offsetof(YuvConstFrameV1, width), 16);
    expect_size("offsetof(YuvConstFrameV1, height)", offsetof(YuvConstFrameV1, height), 20);
    expect_size("offsetof(YuvConstFrameV1, colorMatrix)", offsetof(YuvConstFrameV1, colorMatrix), 24);
    expect_size("offsetof(YuvConstFrameV1, colorRange)", offsetof(YuvConstFrameV1, colorRange), 28);
    expect_size("offsetof(YuvConstFrameV1, planes[0])", offsetof(YuvConstFrameV1, planes), 32);
    expect_size("offsetof(YuvConstFrameV1, planes[1])", offsetof(YuvConstFrameV1, planes[1]), 64);
    expect_size("offsetof(YuvConstFrameV1, planes[2])", offsetof(YuvConstFrameV1, planes[2]), 96);
    expect_size("offsetof(YuvConstFrameV1, reserved)", offsetof(YuvConstFrameV1, reserved), 128);
    expect_size("sizeof(YuvConstFrameV1)", sizeof(YuvConstFrameV1), 160);

    expect_size("offsetof(YuvMutableFrameV1, structSize)", offsetof(YuvMutableFrameV1, structSize), 0);
    expect_size("offsetof(YuvMutableFrameV1, abiVersion)", offsetof(YuvMutableFrameV1, abiVersion), 4);
    expect_size("offsetof(YuvMutableFrameV1, format)", offsetof(YuvMutableFrameV1, format), 8);
    expect_size("offsetof(YuvMutableFrameV1, planeCount)", offsetof(YuvMutableFrameV1, planeCount), 12);
    expect_size("offsetof(YuvMutableFrameV1, width)", offsetof(YuvMutableFrameV1, width), 16);
    expect_size("offsetof(YuvMutableFrameV1, height)", offsetof(YuvMutableFrameV1, height), 20);
    expect_size("offsetof(YuvMutableFrameV1, colorMatrix)", offsetof(YuvMutableFrameV1, colorMatrix), 24);
    expect_size("offsetof(YuvMutableFrameV1, colorRange)", offsetof(YuvMutableFrameV1, colorRange), 28);
    expect_size("offsetof(YuvMutableFrameV1, planes[0])", offsetof(YuvMutableFrameV1, planes), 32);
    expect_size("offsetof(YuvMutableFrameV1, planes[1])", offsetof(YuvMutableFrameV1, planes[1]), 64);
    expect_size("offsetof(YuvMutableFrameV1, planes[2])", offsetof(YuvMutableFrameV1, planes[2]), 96);
    expect_size("offsetof(YuvMutableFrameV1, reserved)", offsetof(YuvMutableFrameV1, reserved), 128);
    expect_size("sizeof(YuvMutableFrameV1)", sizeof(YuvMutableFrameV1), 160);
}

static void test_options_layout(void) {
    printf("Options structs (section 10)\n");

    expect_size("offsetof(YuvRegionOptionsV1, structSize)", offsetof(YuvRegionOptionsV1, structSize), 0);
    expect_size("offsetof(YuvRegionOptionsV1, abiVersion)", offsetof(YuvRegionOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvRegionOptionsV1, left)", offsetof(YuvRegionOptionsV1, left), 8);
    expect_size("offsetof(YuvRegionOptionsV1, top)", offsetof(YuvRegionOptionsV1, top), 12);
    expect_size("offsetof(YuvRegionOptionsV1, right)", offsetof(YuvRegionOptionsV1, right), 16);
    expect_size("offsetof(YuvRegionOptionsV1, bottom)", offsetof(YuvRegionOptionsV1, bottom), 20);
    expect_size("offsetof(YuvRegionOptionsV1, enabled)", offsetof(YuvRegionOptionsV1, enabled), 24);
    expect_size("offsetof(YuvRegionOptionsV1, reserved0)", offsetof(YuvRegionOptionsV1, reserved0), 28);
    expect_size("sizeof(YuvRegionOptionsV1)", sizeof(YuvRegionOptionsV1), 32);

    expect_size("offsetof(YuvBlurOptionsV1, structSize)", offsetof(YuvBlurOptionsV1, structSize), 0);
    expect_size("offsetof(YuvBlurOptionsV1, abiVersion)", offsetof(YuvBlurOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvBlurOptionsV1, radius)", offsetof(YuvBlurOptionsV1, radius), 8);
    expect_size("offsetof(YuvBlurOptionsV1, borderMode)", offsetof(YuvBlurOptionsV1, borderMode), 12);
    expect_size("offsetof(YuvBlurOptionsV1, sigma)", offsetof(YuvBlurOptionsV1, sigma), 16);
    expect_size("offsetof(YuvBlurOptionsV1, region)", offsetof(YuvBlurOptionsV1, region), 24);
    expect_size("offsetof(YuvBlurOptionsV1, reserved)", offsetof(YuvBlurOptionsV1, reserved), 56);
    expect_size("sizeof(YuvBlurOptionsV1)", sizeof(YuvBlurOptionsV1), 72);

    expect_size("offsetof(YuvEffectOptionsV1, structSize)", offsetof(YuvEffectOptionsV1, structSize), 0);
    expect_size("offsetof(YuvEffectOptionsV1, abiVersion)", offsetof(YuvEffectOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvEffectOptionsV1, region)", offsetof(YuvEffectOptionsV1, region), 8);
    expect_size("offsetof(YuvEffectOptionsV1, reserved)", offsetof(YuvEffectOptionsV1, reserved), 40);
    expect_size("sizeof(YuvEffectOptionsV1)", sizeof(YuvEffectOptionsV1), 56);

    expect_size("offsetof(YuvConvertOptionsV1, structSize)", offsetof(YuvConvertOptionsV1, structSize), 0);
    expect_size("offsetof(YuvConvertOptionsV1, abiVersion)", offsetof(YuvConvertOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvConvertOptionsV1, reserved)", offsetof(YuvConvertOptionsV1, reserved), 8);
    expect_size("sizeof(YuvConvertOptionsV1)", sizeof(YuvConvertOptionsV1), 32);

    expect_size("offsetof(YuvCropOptionsV1, structSize)", offsetof(YuvCropOptionsV1, structSize), 0);
    expect_size("offsetof(YuvCropOptionsV1, abiVersion)", offsetof(YuvCropOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvCropOptionsV1, left)", offsetof(YuvCropOptionsV1, left), 8);
    expect_size("offsetof(YuvCropOptionsV1, top)", offsetof(YuvCropOptionsV1, top), 12);
    expect_size("offsetof(YuvCropOptionsV1, width)", offsetof(YuvCropOptionsV1, width), 16);
    expect_size("offsetof(YuvCropOptionsV1, height)", offsetof(YuvCropOptionsV1, height), 20);
    expect_size("offsetof(YuvCropOptionsV1, reserved)", offsetof(YuvCropOptionsV1, reserved), 24);
    expect_size("sizeof(YuvCropOptionsV1)", sizeof(YuvCropOptionsV1), 32);

    expect_size("offsetof(YuvFlipOptionsV1, structSize)", offsetof(YuvFlipOptionsV1, structSize), 0);
    expect_size("offsetof(YuvFlipOptionsV1, abiVersion)", offsetof(YuvFlipOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvFlipOptionsV1, direction)", offsetof(YuvFlipOptionsV1, direction), 8);
    expect_size("offsetof(YuvFlipOptionsV1, reserved0)", offsetof(YuvFlipOptionsV1, reserved0), 12);
    expect_size("offsetof(YuvFlipOptionsV1, reserved)", offsetof(YuvFlipOptionsV1, reserved), 16);
    expect_size("sizeof(YuvFlipOptionsV1)", sizeof(YuvFlipOptionsV1), 32);

    expect_size("offsetof(YuvRotateOptionsV1, structSize)", offsetof(YuvRotateOptionsV1, structSize), 0);
    expect_size("offsetof(YuvRotateOptionsV1, abiVersion)", offsetof(YuvRotateOptionsV1, abiVersion), 4);
    expect_size("offsetof(YuvRotateOptionsV1, rotationDegrees)", offsetof(YuvRotateOptionsV1, rotationDegrees), 8);
    expect_size("offsetof(YuvRotateOptionsV1, reserved0)", offsetof(YuvRotateOptionsV1, reserved0), 12);
    expect_size("offsetof(YuvRotateOptionsV1, reserved)", offsetof(YuvRotateOptionsV1, reserved), 16);
    expect_size("sizeof(YuvRotateOptionsV1)", sizeof(YuvRotateOptionsV1), 32);
}

/*
 * The status and format values cross the FFI and WASM boundaries as plain
 * integers, and Dart's exception mapping table is written against these exact
 * numbers, so a renumbering must break a test rather than silently remap
 * every caller's error handling.
 */
static void test_constant_values(void) {
    printf("Status and contract constants (section 9)\n");

    expect_size("YUV_STATUS_OK", (size_t)YUV_STATUS_OK, 0);
    expect_size("YUV_STATUS_INVALID_ARGUMENT", (size_t)YUV_STATUS_INVALID_ARGUMENT, 1);
    expect_size("YUV_STATUS_UNSUPPORTED_FORMAT", (size_t)YUV_STATUS_UNSUPPORTED_FORMAT, 2);
    expect_size("YUV_STATUS_UNSUPPORTED_LAYOUT", (size_t)YUV_STATUS_UNSUPPORTED_LAYOUT, 3);
    expect_size("YUV_STATUS_OVERFLOW", (size_t)YUV_STATUS_OVERFLOW, 4);
    expect_size("YUV_STATUS_ALLOCATION_FAILED", (size_t)YUV_STATUS_ALLOCATION_FAILED, 5);
    expect_size("YUV_STATUS_INTERNAL_ERROR", (size_t)YUV_STATUS_INTERNAL_ERROR, 6);
    expect_size("YUV_STATUS_UNSUPPORTED_COLOR", (size_t)YUV_STATUS_UNSUPPORTED_COLOR, 7);
    expect_size("sizeof(YuvStatus)", sizeof(YuvStatus), 4);

    expect_size("YUV_ABI_VERSION_1", (size_t)YUV_ABI_VERSION_1, 1);

    expect_size("YUV_FORMAT_I420", (size_t)YUV_FORMAT_I420, 1);
    expect_size("YUV_FORMAT_NV12", (size_t)YUV_FORMAT_NV12, 2);
    expect_size("YUV_FORMAT_BGRA8888", (size_t)YUV_FORMAT_BGRA8888, 3);
    expect_size("YUV_FORMAT_RGBA8888", (size_t)YUV_FORMAT_RGBA8888, 4);

    expect_size("YUV_COLOR_MATRIX_NONE", (size_t)YUV_COLOR_MATRIX_NONE, 0);
    expect_size("YUV_COLOR_MATRIX_BT601", (size_t)YUV_COLOR_MATRIX_BT601, 1);
    expect_size("YUV_COLOR_RANGE_NONE", (size_t)YUV_COLOR_RANGE_NONE, 0);
    expect_size("YUV_COLOR_RANGE_LIMITED", (size_t)YUV_COLOR_RANGE_LIMITED, 1);

    expect_size("YUV_BORDER_CLAMP", (size_t)YUV_BORDER_CLAMP, 1);
    expect_size("YUV_FLIP_HORIZONTAL", (size_t)YUV_FLIP_HORIZONTAL, 1);
    expect_size("YUV_FLIP_VERTICAL", (size_t)YUV_FLIP_VERTICAL, 2);
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 layout test (pointer width: %zu bytes)\n", sizeof(void *));
    printf("=============================================================\n");

    test_plane_layout();
    printf("\n");
    test_frame_layout();
    printf("\n");
    test_options_layout();
    printf("\n");
    test_constant_values();
    printf("\n");

    printf("=============================================================\n");
    if (failures != 0) {
        printf("%d of %d checks FAILED\n", failures, test_count);
        printf("=============================================================\n");
        return EXIT_FAILURE;
    }

    printf("All %d checks passed!\n", test_count);
    printf("=============================================================\n");
    return EXIT_SUCCESS;
}
