#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#include "yuv/utils/h/validated_view.h"

static int test_count = 0;
static int test_pass = 0;

#define ASSERT_TRUE(condition, msg) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL at test #%d: %s\n", test_count, (msg)); \
            abort(); \
        } \
    } while (0)

#define ASSERT_STATUS(actual, expected, msg) \
    do { \
        if ((actual) != (expected)) { \
            fprintf(stderr, "FAIL: %s (expected status %d, got %d)\n", (msg), (int)(expected), (int)(actual)); \
            abort(); \
        } \
    } while (0)

#define TEST_CASE(name) \
    printf("  %s\n", (name)); \
    test_count++; \
    test_pass++;

/* A placeholder non-null pointer. Never dereferenced by validated_view.c or
 * by these tests -- only compared against NULL. Using an address that is
 * plausibly non-zero but never read keeps these tests free of any real
 * allocation, per YUV-33c DoD. */
static uint8_t g_fake_byte;
#define FAKE_DATA ((const void *)&g_fake_byte)
#define FAKE_MUTABLE_DATA ((void *)&g_fake_byte)

static YuvValidatedConstPlaneIn const_plane(uint64_t length, uint64_t rowStride, uint32_t pixelStride,
    uint32_t sampleBytes, const void *data) {
    YuvValidatedConstPlaneIn p;
    p.length = length;
    p.rowStride = rowStride;
    p.pixelStride = pixelStride;
    p.sampleBytes = sampleBytes;
    p.data = data;
    return p;
}

static YuvValidatedMutablePlaneIn mutable_plane(uint64_t length, uint64_t rowStride, uint32_t pixelStride,
    uint32_t sampleBytes, void *data) {
    YuvValidatedMutablePlaneIn p;
    p.length = length;
    p.rowStride = rowStride;
    p.pixelStride = pixelStride;
    p.sampleBytes = sampleBytes;
    p.data = data;
    return p;
}

/* ============================================================================
 * yuv_validated_view_plane_count / plane_geometry / plane_sample_layout
 * ============================================================================ */

static void test_plane_count(void) {
    printf("Testing yuv_validated_view_plane_count...\n");

    TEST_CASE("I420 has 3 planes");
    ASSERT_TRUE(yuv_validated_view_plane_count(YUV_VIEW_FORMAT_I420) == 3, "I420 plane count");

    TEST_CASE("NV12 has 2 planes");
    ASSERT_TRUE(yuv_validated_view_plane_count(YUV_VIEW_FORMAT_NV12) == 2, "NV12 plane count");

    TEST_CASE("BGRA8888 has 1 plane");
    ASSERT_TRUE(yuv_validated_view_plane_count(YUV_VIEW_FORMAT_BGRA8888) == 1, "BGRA8888 plane count");

    TEST_CASE("RGBA8888 has 1 plane");
    ASSERT_TRUE(yuv_validated_view_plane_count(YUV_VIEW_FORMAT_RGBA8888) == 1, "RGBA8888 plane count");

    TEST_CASE("unknown format has 0 planes");
    ASSERT_TRUE(yuv_validated_view_plane_count(0) == 0, "unknown format 0");
    ASSERT_TRUE(yuv_validated_view_plane_count(999) == 0, "unknown format 999");
}

static void test_plane_geometry(void) {
    printf("Testing yuv_validated_view_plane_geometry...\n");
    uint32_t pw, ph;

    TEST_CASE("I420 Y plane geometry = frame geometry (even)");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_I420, 0, 1920, 1080, &pw, &ph), YUV_VIEW_OK, "I420 Y");
    ASSERT_TRUE(pw == 1920 && ph == 1080, "I420 Y dims");

    TEST_CASE("I420 U/V plane geometry = ceil(w/2) x ceil(h/2) (even)");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_I420, 1, 1920, 1080, &pw, &ph), YUV_VIEW_OK, "I420 U");
    ASSERT_TRUE(pw == 960 && ph == 540, "I420 U dims");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_I420, 2, 1920, 1080, &pw, &ph), YUV_VIEW_OK, "I420 V");
    ASSERT_TRUE(pw == 960 && ph == 540, "I420 V dims");

    TEST_CASE("I420 U/V plane geometry rounds up for odd width/height");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_I420, 1, 5, 3, &pw, &ph), YUV_VIEW_OK, "I420 odd U");
    ASSERT_TRUE(pw == 3 && ph == 2, "ceil(5/2)=3, ceil(3/2)=2");

    TEST_CASE("NV12 Y plane geometry = frame geometry");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_NV12, 0, 7, 5, &pw, &ph), YUV_VIEW_OK, "NV12 Y");
    ASSERT_TRUE(pw == 7 && ph == 5, "NV12 Y dims");

    TEST_CASE("NV12 UV plane geometry = ceil(w/2) x ceil(h/2), odd geometry");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_NV12, 1, 7, 5, &pw, &ph), YUV_VIEW_OK, "NV12 UV");
    ASSERT_TRUE(pw == 4 && ph == 3, "ceil(7/2)=4, ceil(5/2)=3");

    TEST_CASE("BGRA8888 packed plane geometry = frame geometry");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_BGRA8888, 0, 33, 17, &pw, &ph), YUV_VIEW_OK, "BGRA packed");
    ASSERT_TRUE(pw == 33 && ph == 17, "BGRA packed dims");

    TEST_CASE("out-of-range planeIndex is UNSUPPORTED_FORMAT");
    ASSERT_STATUS(
        yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_I420, 3, 4, 4, &pw, &ph), YUV_VIEW_UNSUPPORTED_FORMAT,
        "I420 plane 3 out of range");
    ASSERT_STATUS(
        yuv_validated_view_plane_geometry(YUV_VIEW_FORMAT_BGRA8888, 1, 4, 4, &pw, &ph), YUV_VIEW_UNSUPPORTED_FORMAT,
        "BGRA plane 1 out of range");

    TEST_CASE("unknown format is UNSUPPORTED_FORMAT");
    ASSERT_STATUS(yuv_validated_view_plane_geometry(0, 0, 4, 4, &pw, &ph), YUV_VIEW_UNSUPPORTED_FORMAT, "format 0");
}

static void test_plane_sample_layout(void) {
    printf("Testing yuv_validated_view_plane_sample_layout...\n");
    uint32_t sampleBytes, minPixelStride;

    TEST_CASE("I420 every plane: sampleBytes=1, minPixelStride=1");
    for (uint32_t i = 0; i < 3; i++) {
        ASSERT_STATUS(
            yuv_validated_view_plane_sample_layout(YUV_VIEW_FORMAT_I420, i, &sampleBytes, &minPixelStride),
            YUV_VIEW_OK, "I420 layout");
        ASSERT_TRUE(sampleBytes == 1 && minPixelStride == 1, "I420 sample layout values");
    }

    TEST_CASE("NV12 Y: sampleBytes=1, minPixelStride=1");
    ASSERT_STATUS(
        yuv_validated_view_plane_sample_layout(YUV_VIEW_FORMAT_NV12, 0, &sampleBytes, &minPixelStride), YUV_VIEW_OK,
        "NV12 Y layout");
    ASSERT_TRUE(sampleBytes == 1 && minPixelStride == 1, "NV12 Y sample layout values");

    TEST_CASE("NV12 UV: sampleBytes=2, minPixelStride=2");
    ASSERT_STATUS(
        yuv_validated_view_plane_sample_layout(YUV_VIEW_FORMAT_NV12, 1, &sampleBytes, &minPixelStride), YUV_VIEW_OK,
        "NV12 UV layout");
    ASSERT_TRUE(sampleBytes == 2 && minPixelStride == 2, "NV12 UV sample layout values");

    TEST_CASE("BGRA8888/RGBA8888: sampleBytes=4, minPixelStride=4");
    ASSERT_STATUS(
        yuv_validated_view_plane_sample_layout(YUV_VIEW_FORMAT_BGRA8888, 0, &sampleBytes, &minPixelStride),
        YUV_VIEW_OK, "BGRA layout");
    ASSERT_TRUE(sampleBytes == 4 && minPixelStride == 4, "BGRA sample layout values");
    ASSERT_STATUS(
        yuv_validated_view_plane_sample_layout(YUV_VIEW_FORMAT_RGBA8888, 0, &sampleBytes, &minPixelStride),
        YUV_VIEW_OK, "RGBA layout");
    ASSERT_TRUE(sampleBytes == 4 && minPixelStride == 4, "RGBA sample layout values");
}

/* ============================================================================
 * yuv_validated_view_build_const_frame -- I420
 * ============================================================================ */

static void test_build_const_frame_i420_valid_minimal(void) {
    printf("Testing I420 valid minimal (tight strides, even geometry)...\n");
    TEST_CASE("I420 4x2, tight strides, valid");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),  /* Y: 4x2, rowStride=4, length=(2-1)*4+4=8 */
        const_plane(2, 2, 1, 1, FAKE_DATA),  /* U: ceil(4/2)=2 x ceil(2/2)=1, rowStride=2, length=(1-1)*2+2=2 */
        const_plane(2, 2, 1, 1, FAKE_DATA),  /* V: same as U */
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "I420 4x2 minimal should validate");
    ASSERT_TRUE(view.format == YUV_VIEW_FORMAT_I420, "format");
    ASSERT_TRUE(view.planeCount == 3, "plane count");
    ASSERT_TRUE(view.width == 4 && view.height == 2, "frame geometry");
    ASSERT_TRUE(view.planes[0].data == FAKE_DATA, "Y data preserved");
    ASSERT_TRUE(view.planes[1].data == FAKE_DATA, "U data preserved");
    ASSERT_TRUE(view.planes[2].data == FAKE_DATA, "V data preserved");
}

static void test_build_const_frame_i420_odd_geometry(void) {
    printf("Testing I420 odd width/height...\n");
    TEST_CASE("I420 5x3, odd geometry, tight strides");

    /* Y: 5x3, rowStride=5, length=(3-1)*5+5=15 */
    /* U/V: ceil(5/2)=3 x ceil(3/2)=2, rowStride=3, length=(2-1)*3+3=6 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(15, 5, 1, 1, FAKE_DATA),
        const_plane(6, 3, 1, 1, FAKE_DATA),
        const_plane(6, 3, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 5, 3, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "I420 5x3 odd should validate");
    ASSERT_TRUE(view.width == 5 && view.height == 3, "frame geometry odd");
}

static void test_build_const_frame_i420_padded_layout(void) {
    printf("Testing I420 padded/gapped layout...\n");
    TEST_CASE("I420 4x2, row padding beyond minimum, still valid");

    /* Y: 4x2, min rowStride=4, use 8 (padded); min length=(2-1)*8+4=12, use 20 (extra trailing bytes) */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(20, 8, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "I420 padded rowStride/length should validate");
}

static void test_build_const_frame_i420_custom_pixel_stride(void) {
    printf("Testing I420 custom (larger) pixel stride...\n");
    TEST_CASE("I420 4x2, pixelStride=2 on Y (gapped pixels), still valid");

    /* Y: 4x2, pixelStride=2, sampleBytes=1: span=(4-1)*2+1=7, use rowStride=8; length=(2-1)*8+7=15, use 16 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(16, 8, 2, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "I420 custom pixelStride should validate");
}

static void test_build_const_frame_i420_undersized_stride(void) {
    printf("Testing I420 undersized rowStride...\n");
    TEST_CASE("I420 4x2, rowStride too small for width");

    /* Y needs rowStride >= 4, give 3 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(6, 3, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "undersized rowStride should be rejected");
    ASSERT_TRUE(view.format == 0 && view.planes[0].data == NULL, "view left zero-filled on failure");
}

static void test_build_const_frame_i420_undersized_length(void) {
    printf("Testing I420 undersized length...\n");
    TEST_CASE("I420 4x2, length too small for rowStride*height span");

    /* Y: rowStride=4 (min), needs length >= 8, give 7 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(7, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "undersized length should be rejected");
}

static void test_build_const_frame_i420_wrong_sample_bytes(void) {
    printf("Testing I420 wrong sampleBytes...\n");
    TEST_CASE("I420 Y plane sampleBytes=2 (wrong, must be exactly 1)");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 2, FAKE_DATA), /* sampleBytes wrong */
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "wrong sampleBytes should be rejected");
}

static void test_build_const_frame_i420_null_data(void) {
    printf("Testing I420 null plane data pointer...\n");
    TEST_CASE("I420 U plane null data");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, NULL), /* null data */
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "null plane data should be rejected");
}

static void test_build_const_frame_zero_negative_geometry(void) {
    printf("Testing zero/out-of-range frame geometry...\n");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;

    TEST_CASE("width=0 is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 0, 2, planes, 3, &view), YUV_VIEW_INVALID_ARGUMENT,
        "width=0 rejected");

    TEST_CASE("height=0 is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 0, planes, 3, &view), YUV_VIEW_INVALID_ARGUMENT,
        "height=0 rejected");

    TEST_CASE("width beyond INT32_MAX is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, (uint32_t)INT32_MAX + 1u, 2, planes, 3, &view),
        YUV_VIEW_INVALID_ARGUMENT, "width > INT32_MAX rejected");
}

static void test_build_const_frame_null_planes_or_out(void) {
    printf("Testing null planes array / null out pointer...\n");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;

    TEST_CASE("null planes array is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, NULL, 3, &view), YUV_VIEW_INVALID_ARGUMENT,
        "null planes rejected");

    TEST_CASE("planesLength shorter than required plane count is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 2, &view), YUV_VIEW_INVALID_ARGUMENT,
        "short planesLength rejected");

    TEST_CASE("null out pointer is rejected");
    ASSERT_STATUS(
        yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 4, 2, planes, 3, NULL), YUV_VIEW_INVALID_ARGUMENT,
        "null out rejected");
}

static void test_build_const_frame_unknown_format(void) {
    printf("Testing unknown format...\n");
    TEST_CASE("format=0 is UNSUPPORTED_FORMAT");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(0, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_UNSUPPORTED_FORMAT, "unknown format rejected");
}

static void test_build_const_frame_overflowing_span(void) {
    printf("Testing overflowing span/size...\n");
    TEST_CASE("rowStride so large that (planeHeight-1)*rowStride overflows size_t");

    /* width=2 so plane_span is small and passes; force plane_size to overflow
     * via an enormous rowStride combined with height > 1. */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane((uint64_t)SIZE_MAX, (uint64_t)SIZE_MAX, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 1, FAKE_DATA),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_I420, 2, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OVERFLOW, "overflowing plane size should report OVERFLOW");
}

/* ============================================================================
 * NV12
 * ============================================================================ */

static void test_build_const_frame_nv12_valid_and_odd(void) {
    printf("Testing NV12 valid even and odd geometry...\n");

    TEST_CASE("NV12 4x2, tight strides");
    /* Y: 4x2, rowStride=4, length=8. UV: ceil(4/2)=2x ceil(2/2)=1, sampleBytes=2,
     * pixelStride=2 -> span=(2-1)*2+2=4, rowStride=4, length=(1-1)*4+4=4 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(4, 4, 2, 2, FAKE_DATA),
        const_plane(0, 0, 0, 0, NULL), /* unused 3rd slot, ignored on input */
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_NV12, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "NV12 4x2 should validate");
    ASSERT_TRUE(view.planeCount == 2, "NV12 plane count is 2");
    ASSERT_TRUE(view.planes[2].data == NULL, "unused 3rd plane is zero-filled");
    ASSERT_TRUE(view.planes[2].length == 0 && view.planes[2].rowStride == 0, "unused 3rd plane zero fields");

    TEST_CASE("NV12 5x3 odd geometry, tight strides");
    /* Y: 5x3, rowStride=5, length=(3-1)*5+5=15. UV: ceil(5/2)=3 x ceil(3/2)=2,
     * sampleBytes=2, pixelStride=2 -> span=(3-1)*2+2=6, rowStride=6, length=(2-1)*6+6=12 */
    YuvValidatedConstPlaneIn oddPlanes[3] = {
        const_plane(15, 5, 1, 1, FAKE_DATA),
        const_plane(12, 6, 2, 2, FAKE_DATA),
        const_plane(0, 0, 0, 0, NULL),
    };
    YuvValidatedConstFrameView oddView;
    status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_NV12, 5, 3, oddPlanes, 3, &oddView);
    ASSERT_STATUS(status, YUV_VIEW_OK, "NV12 5x3 odd should validate");
}

static void test_build_const_frame_nv12_uv_pixel_stride_too_small(void) {
    printf("Testing NV12 UV pixelStride below minimum of 2...\n");
    TEST_CASE("NV12 UV pixelStride=1 rejected (minimum is 2)");

    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(2, 2, 1, 2, FAKE_DATA), /* pixelStride=1 < minimum 2 */
        const_plane(0, 0, 0, 0, NULL),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_NV12, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "NV12 UV pixelStride < 2 should be rejected");
}

static void test_build_const_frame_nv12_uv_custom_larger_pixel_stride(void) {
    printf("Testing NV12 UV pixelStride larger than minimum (padded)...\n");
    TEST_CASE("NV12 UV pixelStride=4 (padded interleave) accepted");

    /* UV: 2x1, sampleBytes=2, pixelStride=4 -> span=(2-1)*4+2=6, rowStride=6, length=6 */
    YuvValidatedConstPlaneIn planes[3] = {
        const_plane(8, 4, 1, 1, FAKE_DATA),
        const_plane(6, 6, 4, 2, FAKE_DATA),
        const_plane(0, 0, 0, 0, NULL),
    };
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_NV12, 4, 2, planes, 3, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "NV12 UV padded pixelStride should validate");
}

/* ============================================================================
 * BGRA8888 / RGBA8888
 * ============================================================================ */

static void test_build_const_frame_bgra_valid_and_padded(void) {
    printf("Testing BGRA8888 valid tight and padded rowStride...\n");

    TEST_CASE("BGRA8888 3x2 tight: rowStride=12, length=(2-1)*12+12=24");
    YuvValidatedConstPlaneIn planes[1] = {const_plane(24, 12, 4, 4, FAKE_DATA)};
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, planes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "BGRA tight should validate");
    ASSERT_TRUE(view.planeCount == 1, "BGRA plane count 1");
    ASSERT_TRUE(view.planes[1].data == NULL && view.planes[2].data == NULL, "unused BGRA planes zero-filled");

    TEST_CASE("BGRA8888 3x2 padded rowStride=32 (extra bytes), length large enough");
    YuvValidatedConstPlaneIn paddedPlanes[1] = {const_plane(64, 32, 4, 4, FAKE_DATA)};
    status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, paddedPlanes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "BGRA padded rowStride should validate");

    TEST_CASE("BGRA8888 odd 5x3 geometry, tight strides");
    /* rowStride=(5-1)*4+4=20, length=(3-1)*20+20=60 */
    YuvValidatedConstPlaneIn oddPlanes[1] = {const_plane(60, 20, 4, 4, FAKE_DATA)};
    status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_BGRA8888, 5, 3, oddPlanes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "BGRA odd geometry should validate");
}

static void test_build_const_frame_bgra_pixel_stride_too_small(void) {
    printf("Testing BGRA8888 pixelStride below minimum of 4...\n");
    TEST_CASE("BGRA8888 pixelStride=3 rejected");

    YuvValidatedConstPlaneIn planes[1] = {const_plane(24, 9, 3, 4, FAKE_DATA)};
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, planes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "BGRA pixelStride < 4 should be rejected");
}

static void test_build_const_frame_rgba_source_view(void) {
    printf("Testing RGBA8888 raw source view (convert-only format)...\n");
    TEST_CASE("RGBA8888 4x4 tight strides valid as source view");

    /* rowStride=(4-1)*4+4=16, length=(4-1)*16+16=64 */
    YuvValidatedConstPlaneIn planes[1] = {const_plane(64, 16, 4, 4, FAKE_DATA)};
    YuvValidatedConstFrameView view;
    YuvViewStatus status = yuv_validated_view_build_const_frame(YUV_VIEW_FORMAT_RGBA8888, 4, 4, planes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "RGBA8888 source view should validate");
    ASSERT_TRUE(view.format == YUV_VIEW_FORMAT_RGBA8888, "RGBA format preserved");
}

/* ============================================================================
 * Mutable frame view (destination side) + destination geometry check
 * ============================================================================ */

static void test_build_mutable_frame_valid_and_null_checks(void) {
    printf("Testing yuv_validated_view_build_mutable_frame...\n");

    TEST_CASE("BGRA8888 mutable destination, valid");
    YuvValidatedMutablePlaneIn planes[1] = {mutable_plane(24, 12, 4, 4, FAKE_MUTABLE_DATA)};
    YuvValidatedMutableFrameView view;
    YuvViewStatus status = yuv_validated_view_build_mutable_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, planes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_OK, "mutable BGRA should validate");

    TEST_CASE("mutable destination null data rejected");
    YuvValidatedMutablePlaneIn nullPlanes[1] = {mutable_plane(24, 12, 4, 4, NULL)};
    status = yuv_validated_view_build_mutable_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, nullPlanes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "null mutable data rejected");

    TEST_CASE("mutable destination zero/negative geometry rejected");
    status = yuv_validated_view_build_mutable_frame(YUV_VIEW_FORMAT_BGRA8888, 0, 2, planes, 1, &view);
    ASSERT_STATUS(status, YUV_VIEW_INVALID_ARGUMENT, "zero width rejected on mutable frame");
}

static void test_check_destination_geometry(void) {
    printf("Testing yuv_validated_view_check_destination_geometry...\n");

    YuvValidatedMutablePlaneIn planes[1] = {mutable_plane(24, 12, 4, 4, FAKE_MUTABLE_DATA)};
    YuvValidatedMutableFrameView view;
    YuvViewStatus buildStatus =
        yuv_validated_view_build_mutable_frame(YUV_VIEW_FORMAT_BGRA8888, 3, 2, planes, 1, &view);
    ASSERT_TRUE(buildStatus == YUV_VIEW_OK, "setup: mutable frame must build");

    TEST_CASE("matching destination geometry is OK");
    ASSERT_STATUS(
        yuv_validated_view_check_destination_geometry(&view, 3, 2), YUV_VIEW_OK, "matching geometry accepted");

    TEST_CASE("mismatched destination geometry is rejected (e.g. missing 90/270 transpose)");
    ASSERT_STATUS(
        yuv_validated_view_check_destination_geometry(&view, 2, 3), YUV_VIEW_INVALID_ARGUMENT,
        "transposed mismatch rejected");

    TEST_CASE("null destination pointer is rejected");
    ASSERT_STATUS(
        yuv_validated_view_check_destination_geometry(NULL, 3, 2), YUV_VIEW_INVALID_ARGUMENT,
        "null destination rejected");
}

/* ============================================================================
 * Main
 * ============================================================================ */

int main(void) {
    printf("Running validated view tests...\n\n");

    test_plane_count();
    printf("\n");
    test_plane_geometry();
    printf("\n");
    test_plane_sample_layout();
    printf("\n");

    test_build_const_frame_i420_valid_minimal();
    printf("\n");
    test_build_const_frame_i420_odd_geometry();
    printf("\n");
    test_build_const_frame_i420_padded_layout();
    printf("\n");
    test_build_const_frame_i420_custom_pixel_stride();
    printf("\n");
    test_build_const_frame_i420_undersized_stride();
    printf("\n");
    test_build_const_frame_i420_undersized_length();
    printf("\n");
    test_build_const_frame_i420_wrong_sample_bytes();
    printf("\n");
    test_build_const_frame_i420_null_data();
    printf("\n");
    test_build_const_frame_zero_negative_geometry();
    printf("\n");
    test_build_const_frame_null_planes_or_out();
    printf("\n");
    test_build_const_frame_unknown_format();
    printf("\n");
    test_build_const_frame_overflowing_span();
    printf("\n");

    test_build_const_frame_nv12_valid_and_odd();
    printf("\n");
    test_build_const_frame_nv12_uv_pixel_stride_too_small();
    printf("\n");
    test_build_const_frame_nv12_uv_custom_larger_pixel_stride();
    printf("\n");

    test_build_const_frame_bgra_valid_and_padded();
    printf("\n");
    test_build_const_frame_bgra_pixel_stride_too_small();
    printf("\n");
    test_build_const_frame_rgba_source_view();
    printf("\n");

    test_build_mutable_frame_valid_and_null_checks();
    printf("\n");
    test_check_destination_geometry();
    printf("\n");

    printf("=============================================================\n");
    printf("All %d tests passed!\n", test_pass);
    printf("=============================================================\n");

    return EXIT_SUCCESS;
}
