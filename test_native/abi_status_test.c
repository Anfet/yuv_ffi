/* Checks reachable ABI statuses, validation of malformed descriptors, and
 * byte-for-byte destination atomicity on rejected calls. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yuv/abi/h/yuv_ops_v1.h"
#include "yuv/abi/h/yuv_validate_v1.h"

static int checks = 0;
static int failures = 0;

#define CANARY 0xA5

static void expect_status(const char *label, YuvStatus actual, YuvStatus expected) {
    volatile int a = (int)actual;
    volatile int e = (int)expected;

    checks++;
    if (a == e) {
        printf("  ok    %-58s status=%d\n", label, (int)a);
    } else {
        printf("  FAIL  %-58s status=%d, expected %d\n", label, (int)a, (int)e);
        failures++;
    }
}

static void expect_true(const char *label, int condition) {
    volatile int c = condition;

    checks++;
    if (c) {
        printf("  ok    %s\n", label);
    } else {
        printf("  FAIL  %s\n", label);
        failures++;
    }
}



#define FRAME_WIDTH 8
#define FRAME_HEIGHT 4
#define BGRA_STRIDE (FRAME_WIDTH * 4)
#define BGRA_BYTES (BGRA_STRIDE * FRAME_HEIGHT)

static uint8_t g_sourceBytes[BGRA_BYTES];
static uint8_t g_destinationBytes[BGRA_BYTES];

static YuvConstFrameV1 make_bgra_source(void) {
    YuvConstFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(YuvConstFrameV1);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_BGRA8888;
    frame.planeCount = 1;
    frame.width = FRAME_WIDTH;
    frame.height = FRAME_HEIGHT;
    frame.colorMatrix = YUV_COLOR_MATRIX_NONE;
    frame.colorRange = YUV_COLOR_RANGE_NONE;
    frame.planes[0].length = BGRA_BYTES;
    frame.planes[0].rowStride = BGRA_STRIDE;
    frame.planes[0].pixelStride = 4;
    frame.planes[0].sampleBytes = 4;
    frame.planes[0].data = g_sourceBytes;
    return frame;
}

static YuvMutableFrameV1 make_bgra_destination(void) {
    YuvMutableFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(YuvMutableFrameV1);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_BGRA8888;
    frame.planeCount = 1;
    frame.width = FRAME_WIDTH;
    frame.height = FRAME_HEIGHT;
    frame.colorMatrix = YUV_COLOR_MATRIX_NONE;
    frame.colorRange = YUV_COLOR_RANGE_NONE;
    frame.planes[0].length = BGRA_BYTES;
    frame.planes[0].rowStride = BGRA_STRIDE;
    frame.planes[0].pixelStride = 4;
    frame.planes[0].sampleBytes = 4;
    frame.planes[0].data = g_destinationBytes;
    return frame;
}

/*
 * NV12 fixtures: a full-size Y plane plus an interleaved UV plane at
 * ceil(w/2) x ceil(h/2) with 2 bytes per sample. Needed wherever a rule is
 * NV12-only, such as chroma swap.
 */
#define NV12_UV_WIDTH ((FRAME_WIDTH + 1) / 2)
#define NV12_UV_HEIGHT ((FRAME_HEIGHT + 1) / 2)
#define NV12_Y_BYTES (FRAME_WIDTH * FRAME_HEIGHT)
#define NV12_UV_STRIDE (NV12_UV_WIDTH * 2)
#define NV12_UV_BYTES (NV12_UV_STRIDE * NV12_UV_HEIGHT)

static uint8_t g_nv12Source[NV12_Y_BYTES + NV12_UV_BYTES];
static uint8_t g_nv12Destination[NV12_Y_BYTES + NV12_UV_BYTES];

static YuvConstFrameV1 make_nv12_source(void) {
    YuvConstFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(YuvConstFrameV1);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_NV12;
    frame.planeCount = 2;
    frame.width = FRAME_WIDTH;
    frame.height = FRAME_HEIGHT;
    frame.colorMatrix = YUV_COLOR_MATRIX_BT601;
    frame.colorRange = YUV_COLOR_RANGE_LIMITED;
    frame.planes[0].length = NV12_Y_BYTES;
    frame.planes[0].rowStride = FRAME_WIDTH;
    frame.planes[0].pixelStride = 1;
    frame.planes[0].sampleBytes = 1;
    frame.planes[0].data = g_nv12Source;
    frame.planes[1].length = NV12_UV_BYTES;
    frame.planes[1].rowStride = NV12_UV_STRIDE;
    frame.planes[1].pixelStride = 2;
    frame.planes[1].sampleBytes = 2;
    frame.planes[1].data = g_nv12Source + NV12_Y_BYTES;
    return frame;
}

static YuvMutableFrameV1 make_nv12_destination(void) {
    YuvMutableFrameV1 frame;
    memset(&frame, 0, sizeof(frame));
    frame.structSize = (uint32_t)sizeof(YuvMutableFrameV1);
    frame.abiVersion = YUV_ABI_VERSION_1;
    frame.format = YUV_FORMAT_NV12;
    frame.planeCount = 2;
    frame.width = FRAME_WIDTH;
    frame.height = FRAME_HEIGHT;
    frame.colorMatrix = YUV_COLOR_MATRIX_BT601;
    frame.colorRange = YUV_COLOR_RANGE_LIMITED;
    frame.planes[0].length = NV12_Y_BYTES;
    frame.planes[0].rowStride = FRAME_WIDTH;
    frame.planes[0].pixelStride = 1;
    frame.planes[0].sampleBytes = 1;
    frame.planes[0].data = g_nv12Destination;
    frame.planes[1].length = NV12_UV_BYTES;
    frame.planes[1].rowStride = NV12_UV_STRIDE;
    frame.planes[1].pixelStride = 2;
    frame.planes[1].sampleBytes = 2;
    frame.planes[1].data = g_nv12Destination + NV12_Y_BYTES;
    return frame;
}

static YuvEffectOptionsV1 make_effect_options(void) {
    YuvEffectOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvEffectOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.region.structSize = (uint32_t)sizeof(YuvRegionOptionsV1);
    options.region.abiVersion = YUV_ABI_VERSION_1;
    options.region.enabled = 0;
    return options;
}

static YuvBlurOptionsV1 make_blur_options(uint32_t radius, double sigma) {
    YuvBlurOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvBlurOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.radius = radius;
    options.borderMode = YUV_BORDER_CLAMP;
    options.sigma = sigma;
    options.region.structSize = (uint32_t)sizeof(YuvRegionOptionsV1);
    options.region.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

static YuvConvertOptionsV1 make_convert_options(void) {
    YuvConvertOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvConvertOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

static YuvCropOptionsV1 make_crop_options(int32_t left, int32_t top, uint32_t width, uint32_t height) {
    YuvCropOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvCropOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.left = left;
    options.top = top;
    options.width = width;
    options.height = height;
    return options;
}

static YuvFlipOptionsV1 make_flip_options(uint32_t direction) {
    YuvFlipOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvFlipOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.direction = direction;
    return options;
}

static YuvRotateOptionsV1 make_rotate_options(uint32_t degrees) {
    YuvRotateOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(YuvRotateOptionsV1);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.rotationDegrees = degrees;
    return options;
}

static void reset_buffers(void) {
    memset(g_sourceBytes, 0x11, sizeof(g_sourceBytes));
    memset(g_destinationBytes, CANARY, sizeof(g_destinationBytes));
    memset(g_nv12Source, 0x11, sizeof(g_nv12Source));
    memset(g_nv12Destination, CANARY, sizeof(g_nv12Destination));
}

static int destination_untouched(void) {
    for (size_t i = 0; i < sizeof(g_destinationBytes); i++) {
        if (g_destinationBytes[i] != CANARY) {
            return 0;
        }
    }
    for (size_t i = 0; i < sizeof(g_nv12Destination); i++) {
        if (g_nv12Destination[i] != CANARY) {
            return 0;
        }
    }
    return 1;
}

/*
 * Runs one grayscale call against fresh buffers, asserts the status, and
 * asserts the destination canary survived. Grayscale stands in for the whole
 * effect family here because all four effect entry points share one prologue;
 * the per-operation rules get their own cases further down.
 */
static void check_effect_case(const char *label, YuvConstFrameV1 source, YuvMutableFrameV1 destination,
    YuvEffectOptionsV1 options, YuvStatus expected) {
    reset_buffers();
    YuvStatus status = yuv_grayscale_v1(&source, &destination, &options);
    expect_status(label, status, expected);
    expect_true("      destination canary intact", destination_untouched());
}

/* ============================================================================
 * Status 1: INVALID_ARGUMENT
 * ============================================================================ */

static void test_invalid_argument(void) {
    printf("INVALID_ARGUMENT (1)\n");

    {
        reset_buffers();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_grayscale_v1(NULL, &destination, &options);
        expect_status("null source", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_grayscale_v1(&source, NULL, &options);
        expect_status("null destination", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvStatus status = yuv_grayscale_v1(&source, &destination, NULL);
        expect_status("null options", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }

    {
        YuvConstFrameV1 source = make_bgra_source();
        source.abiVersion = 2;
        check_effect_case("source abiVersion != 1", source, make_bgra_destination(), make_effect_options(),
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.structSize = (uint32_t)sizeof(YuvConstFrameV1) - 1;
        check_effect_case("source structSize below full v1 type", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.reserved[2] = 1;
        check_effect_case("source reserved field set", source, make_bgra_destination(), make_effect_options(),
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.planeCount = 3;
        check_effect_case("planeCount disagrees with format", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.width = 0;
        check_effect_case("zero width", source, make_bgra_destination(), make_effect_options(),
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.planes[0].data = NULL;
        check_effect_case("null plane data", source, make_bgra_destination(), make_effect_options(),
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.planes[0].length = BGRA_BYTES - 1;
        check_effect_case("plane length below minimum span", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.planes[0].rowStride = BGRA_STRIDE - 1;
        check_effect_case("rowStride below minimum span", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.width = FRAME_WIDTH + 1;
        check_effect_case("destination geometry mismatch", make_bgra_source(), destination,
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvEffectOptionsV1 options = make_effect_options();
        options.abiVersion = 7;
        check_effect_case("options abiVersion != 1", make_bgra_source(), make_bgra_destination(), options,
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvEffectOptionsV1 options = make_effect_options();
        options.reserved[1] = 1;
        check_effect_case("options reserved field set", make_bgra_source(), make_bgra_destination(), options,
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        /* A disabled region must be fully zeroed, so a leftover rectangle is
         * rejected rather than quietly ignored. */
        YuvEffectOptionsV1 options = make_effect_options();
        options.region.enabled = 0;
        options.region.right = 4;
        check_effect_case("disabled region with leftover coordinates", make_bgra_source(),
            make_bgra_destination(), options, YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvEffectOptionsV1 options = make_effect_options();
        options.region.enabled = 2;
        check_effect_case("region enabled is neither 0 nor 1", make_bgra_source(), make_bgra_destination(),
            options, YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvEffectOptionsV1 options = make_effect_options();
        options.region.enabled = 1;
        options.region.left = 0;
        options.region.top = 0;
        options.region.right = FRAME_WIDTH + 1;
        options.region.bottom = FRAME_HEIGHT;
        check_effect_case("enabled region extends past the frame", make_bgra_source(),
            make_bgra_destination(), options, YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvEffectOptionsV1 options = make_effect_options();
        options.region.enabled = 1;
        options.region.left = 4;
        options.region.top = 0;
        options.region.right = 4;
        options.region.bottom = FRAME_HEIGHT;
        check_effect_case("enabled region is empty", make_bgra_source(), make_bgra_destination(), options,
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {

        YuvConstFrameV1 source = make_bgra_source();
        source.format = 99;
        check_effect_case("unknown numeric format", source, make_bgra_destination(), make_effect_options(),
            YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        /* Likewise an unknown matrix or range value: unknown numeric value,
         * not an unsupported-but-known color space. */
        YuvConstFrameV1 source = make_bgra_source();
        source.colorMatrix = 99;
        check_effect_case("unknown numeric colorMatrix", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.colorRange = 99;
        check_effect_case("unknown numeric colorRange", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        /* Source and destination naming the same buffer is the aliasing case
         * ABI v1 forbids outright. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.planes[0].data = g_sourceBytes;
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_grayscale_v1(&source, &destination, &options);
        expect_status("source and destination spans overlap", status, YUV_STATUS_INVALID_ARGUMENT);
    }
}

/* ============================================================================
 * Status 2: UNSUPPORTED_FORMAT
 * ============================================================================ */

static void test_unsupported_format(void) {
    printf("UNSUPPORTED_FORMAT (2)\n");

    {
        /* RGBA is a valid format, but only as a source to yuv_convert_v1;
         * effects do not accept it. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        source.format = YUV_FORMAT_RGBA8888;
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_grayscale_v1(&source, &destination, &options);
        expect_status("RGBA source rejected by an effect", status, YUV_STATUS_UNSUPPORTED_FORMAT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* RGBA is not a publishable destination anywhere in ABI v1. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.format = YUV_FORMAT_RGBA8888;
        YuvConvertOptionsV1 options = make_convert_options();
        YuvStatus status = yuv_convert_v1(&source, &destination, &options);
        expect_status("RGBA destination rejected by convert", status, YUV_STATUS_UNSUPPORTED_FORMAT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* Chroma swap is NV12-only. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_chroma_swap_v1(&source, &destination, &options);
        expect_status("chroma swap rejects BGRA", status, YUV_STATUS_UNSUPPORTED_FORMAT);
        expect_true("      destination canary intact", destination_untouched());
    }
}

/* ============================================================================
 * Status 7: UNSUPPORTED_COLOR
 * ============================================================================ */

static void test_unsupported_color(void) {
    printf("UNSUPPORTED_COLOR (7)\n");

    {
        /* A structurally perfect BGRA frame that declares a YUV matrix. */
        YuvConstFrameV1 source = make_bgra_source();
        source.colorMatrix = YUV_COLOR_MATRIX_BT601;
        check_effect_case("BGRA declaring BT601 matrix", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_UNSUPPORTED_COLOR);
    }
    {
        YuvConstFrameV1 source = make_bgra_source();
        source.colorRange = YUV_COLOR_RANGE_LIMITED;
        check_effect_case("BGRA declaring limited range", source, make_bgra_destination(),
            make_effect_options(), YUV_STATUS_UNSUPPORTED_COLOR);
    }
    {
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.colorMatrix = YUV_COLOR_MATRIX_BT601;
        check_effect_case("destination BGRA declaring BT601 matrix", make_bgra_source(), destination,
            make_effect_options(), YUV_STATUS_UNSUPPORTED_COLOR);
    }
}

/* ============================================================================
 * Status 4: OVERFLOW
 *
 * Distinguished from INVALID_ARGUMENT on purpose: an undersized buffer is the
 * caller passing too little, while an overflowing span is arithmetic that
 * cannot be carried out at all on this target.
 * ============================================================================ */

static void test_overflow(void) {
    printf("OVERFLOW (4)\n");

    {
        /* A row stride near UINT64_MAX makes (height - 1) * rowStride
         * unrepresentable, which the checked helpers must report as overflow
         * rather than wrap into a plausible-looking small number. */
        YuvConstFrameV1 source = make_bgra_source();
        source.planes[0].rowStride = UINT64_MAX - 1;
        source.planes[0].length = UINT64_MAX;
        check_effect_case("row stride overflows the plane size computation", source,
            make_bgra_destination(), make_effect_options(), YUV_STATUS_OVERFLOW);
    }
}



static void test_unsupported_layout_unreachable(void) {
    printf("UNSUPPORTED_LAYOUT (3)\n");

    expect_status("constant value is pinned at 3", (YuvStatus)(YUV_STATUS_UNSUPPORTED_LAYOUT),
        (YuvStatus)3);
    printf("        NOTE: no ABI v1 entry point can return 3. Section 11 requires every\n");
    printf("        structurally valid layout to be SUPPORTED, so the set this status\n");
    printf("        describes is empty. The Dart-side mapping for 3 is covered directly\n");
    printf("        by YUV-36d; producing it here would mean rejecting a layout the\n");
    printf("        contract requires this build to accept.\n");
}

/* ============================================================================
 * Per-operation options rules
 * ============================================================================ */

static void test_blur_options(void) {
    printf("Blur options\n");

    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(257, 0.0);
        YuvStatus status = yuv_mean_blur_v1(&source, &destination, &options);
        expect_status("radius above 256", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 1.5);
        YuvStatus status = yuv_mean_blur_v1(&source, &destination, &options);
        expect_status("mean blur rejects a non-zero sigma", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 1.5);
        YuvStatus status = yuv_box_blur_v1(&source, &destination, &options);
        expect_status("box blur rejects a non-zero sigma", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 0.0);
        YuvStatus status = yuv_gaussian_blur_v1(&source, &destination, &options);
        expect_status("gaussian rejects sigma == 0", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, -1.0);
        YuvStatus status = yuv_gaussian_blur_v1(&source, &destination, &options);
        expect_status("gaussian rejects a negative sigma", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 1.5);
        options.borderMode = 99;
        YuvStatus status = yuv_gaussian_blur_v1(&source, &destination, &options);
        expect_status("unknown border mode", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
}

static void test_transform_options(void) {
    printf("Transform options\n");

    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvFlipOptionsV1 options = make_flip_options(0);
        YuvStatus status = yuv_flip_v1(&source, &destination, &options);
        expect_status("flip direction 0", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* The two flip constants are not a bit field in ABI v1. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvFlipOptionsV1 options = make_flip_options(YUV_FLIP_HORIZONTAL | YUV_FLIP_VERTICAL);
        YuvStatus status = yuv_flip_v1(&source, &destination, &options);
        expect_status("flip direction combining both axes", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvRotateOptionsV1 options = make_rotate_options(45);
        YuvStatus status = yuv_rotate_v1(&source, &destination, &options);
        expect_status("rotation by 45 degrees", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* 90 degrees requires a transposed destination; a same-sized one is a
         * geometry mismatch. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvRotateOptionsV1 options = make_rotate_options(90);
        YuvStatus status = yuv_rotate_v1(&source, &destination, &options);
        expect_status("rotate 90 with a non-transposed destination", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvCropOptionsV1 options = make_crop_options(0, 0, 0, FRAME_HEIGHT);
        YuvStatus status = yuv_crop_v1(&source, &destination, &options);
        expect_status("crop with zero width", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* The destination matches the crop rectangle, but the rectangle runs
         * past the right edge of the source. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvCropOptionsV1 options = make_crop_options(4, 0, FRAME_WIDTH, FRAME_HEIGHT);
        YuvStatus status = yuv_crop_v1(&source, &destination, &options);
        expect_status("crop rectangle extends past the source", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* An otherwise valid NV12 call, so the format check passes and the
         * region rule is the thing actually under test. */
        reset_buffers();
        YuvConstFrameV1 source = make_nv12_source();
        YuvMutableFrameV1 destination = make_nv12_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        options.region.enabled = 1;
        options.region.left = 0;
        options.region.top = 0;
        options.region.right = FRAME_WIDTH;
        options.region.bottom = FRAME_HEIGHT;
        YuvStatus status = yuv_chroma_swap_v1(&source, &destination, &options);
        expect_status("chroma swap rejects an enabled region", status, YUV_STATUS_INVALID_ARGUMENT);
        expect_true("      destination canary intact", destination_untouched());
    }
    {
        /* The same call with a disabled region is valid and must reach the
         * kernel, which proves the rejection above was the region and not the
         * NV12 descriptor. */
        reset_buffers();
        YuvConstFrameV1 source = make_nv12_source();
        YuvMutableFrameV1 destination = make_nv12_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        YuvStatus status = yuv_chroma_swap_v1(&source, &destination, &options);
        expect_status("chroma swap accepts NV12 with a disabled region", status,
            YUV_STATUS_OK);
    }
}

/* ============================================================================
 * Valid descriptors reach the kernel boundary
 * ============================================================================ */

static void test_valid_descriptor_reaches_kernel(void) {
    printf("Valid descriptors pass validation\n");


    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("grayscale succeeds", yuv_grayscale_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("black-white succeeds", yuv_black_white_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("negate succeeds", yuv_negate_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvConvertOptionsV1 options = make_convert_options();
        expect_status("convert succeeds", yuv_convert_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 0.0);
        expect_status("mean blur succeeds", yuv_mean_blur_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 0.0);
        expect_status("box blur succeeds", yuv_box_blur_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 1.5);
        expect_status("gaussian blur reaches the kernel",
            yuv_gaussian_blur_v1(&source, &destination, &options), YUV_STATUS_OK);
    }
    {
        /* radius 0 is a defined no-op, not an error, so it must pass
         * validation like any other accepted radius. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(0, 0.0);
        expect_status("blur radius 0 is accepted", yuv_mean_blur_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvFlipOptionsV1 options = make_flip_options(YUV_FLIP_HORIZONTAL);
        expect_status("flip succeeds", yuv_flip_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvRotateOptionsV1 options = make_rotate_options(180);
        expect_status("rotate 180 succeeds", yuv_rotate_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        /* A crop whose destination geometry matches the rectangle. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.width = 4;
        destination.height = 2;
        destination.planes[0].rowStride = 4 * 4;
        destination.planes[0].length = 4 * 4 * 2;
        YuvCropOptionsV1 options = make_crop_options(1, 1, 4, 2);
        expect_status("crop succeeds", yuv_crop_v1(&source, &destination, &options),
            YUV_STATUS_OK);
    }
    {
        /* A larger structSize must be accepted and its unknown tail ignored:
         * this is the forward-compatibility rule that lets a newer caller talk
         * to an older binary. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        source.structSize = (uint32_t)sizeof(YuvConstFrameV1) + 64;
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("larger source structSize is accepted",
            yuv_grayscale_v1(&source, &destination, &options), YUV_STATUS_OK);
    }
    {
        /* A destination sharing the allocation but sitting past the source's
         * last active byte does not alias, so it must be accepted. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        source.height = 2;
        source.planes[0].length = BGRA_STRIDE * 2;
        YuvMutableFrameV1 destination = make_bgra_destination();
        destination.height = 2;
        destination.planes[0].data = g_sourceBytes + (BGRA_STRIDE * 2);
        destination.planes[0].length = BGRA_STRIDE * 2;
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("adjacent non-overlapping spans in one allocation",
            yuv_grayscale_v1(&source, &destination, &options), YUV_STATUS_OK);
    }
}

/* One direct-ABI table: positives compare the entire allocation (padding
 * included); negatives must leave the entire allocation untouched through
 * both conversion and a transform. */
static void test_destination_sample_collisions(void) {
    static const struct {
        const char *name;
        uint32_t format, yPixel, uOffset, uPixel, uRow, vOffset, vPixel, vRow;
        YuvStatus status;
    } cases[] = {
        {"U equals V", 1, 1, 64, 1, 3, 64, 1, 3, YUV_STATUS_INVALID_ARGUMENT},
        {"partial chroma collision", 1, 1, 64, 1, 3, 66, 1, 3, YUV_STATUS_INVALID_ARGUMENT},
        {"Y and U collision", 1, 1, 20, 1, 3, 80, 1, 3, YUV_STATUS_INVALID_ARGUMENT},
        {"adjacent planes", 1, 1, 25, 1, 3, 34, 1, 3, YUV_STATUS_OK},
        {"interleaved chroma", 1, 1, 64, 2, 6, 65, 2, 6, YUV_STATUS_OK},
        {"shared row padding", 1, 1, 64, 1, 12, 67, 1, 12, YUV_STATUS_OK},
        {"different row strides disjoint", 1, 1, 64, 1, 12, 67, 1, 13, YUV_STATUS_OK},
        {"different rows collide", 1, 1, 64, 1, 12, 69, 1, 8, YUV_STATUS_INVALID_ARGUMENT},
        {"coprime strides disjoint", 1, 1, 64, 5, 32, 65, 7, 32, YUV_STATUS_OK},
        {"coprime strides collide", 1, 1, 64, 5, 32, 67, 7, 32, YUV_STATUS_INVALID_ARGUMENT},
        {"NV12 gaps disjoint", 2, 3, 1, 3, 15, 0, 0, 0, YUV_STATUS_OK},
        {"NV12 second sample byte collides", 2, 3, 2, 3, 15, 0, 0, 0, YUV_STATUS_INVALID_ARGUMENT},
    };
    for (size_t c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
        uint8_t input[3][32], output[256], expected[256];
        YuvConstFrameV1 source = {0};
        YuvMutableFrameV1 destination = {0};
        source.structSize = (uint32_t)sizeof(source);
        destination.structSize = (uint32_t)sizeof(destination);
        source.abiVersion = destination.abiVersion = YUV_ABI_VERSION_1;
        source.format = destination.format = cases[c].format;
        source.planeCount = destination.planeCount = cases[c].format == YUV_FORMAT_I420 ? 3 : 2;
        source.width = destination.width = 5;
        source.height = destination.height = 5;
        source.colorMatrix = destination.colorMatrix = YUV_COLOR_MATRIX_BT601;
        source.colorRange = destination.colorRange = YUV_COLOR_RANGE_LIMITED;
        for (uint32_t p = 0; p < source.planeCount; p++) {
            uint32_t w = p == 0 ? 5 : 3;
            uint32_t bytes = p == 1 && cases[c].format == YUV_FORMAT_NV12 ? 2 : 1;
            uint32_t offset = p == 0 ? 0 : p == 1 ? cases[c].uOffset : cases[c].vOffset;
            memset(input[p], (int)(30 + 40 * p), sizeof(input[p]));
            source.planes[p].data = input[p];
            source.planes[p].length = sizeof(input[p]);
            source.planes[p].rowStride = w * bytes;
            source.planes[p].pixelStride = source.planes[p].sampleBytes = bytes;
            destination.planes[p].data = output + offset;
            destination.planes[p].length = sizeof(output) - offset;
            destination.planes[p].sampleBytes = bytes;
            destination.planes[p].pixelStride = p == 0 ? cases[c].yPixel : p == 1 ? cases[c].uPixel : cases[c].vPixel;
            destination.planes[p].rowStride = p == 0 ? 5 * cases[c].yPixel : p == 1 ? cases[c].uRow : cases[c].vRow;
        }
        for (int operation = 0; operation < (cases[c].status == YUV_STATUS_OK ? 1 : 2); operation++) {
            memset(output, CANARY, sizeof(output));
            memset(expected, CANARY, sizeof(expected));
            YuvConvertOptionsV1 convert = make_convert_options();
            YuvFlipOptionsV1 flip = make_flip_options(YUV_FLIP_HORIZONTAL);
            YuvStatus actual = operation == 0 ? yuv_convert_v1(&source, &destination, &convert)
                                            : yuv_flip_v1(&source, &destination, &flip);
            if (actual == YUV_STATUS_OK && cases[c].status == YUV_STATUS_OK) {
                for (uint32_t p = 0; p < source.planeCount; p++) {
                    const YuvMutablePlaneV1 *plane = &destination.planes[p];
                    size_t offset = (size_t)(plane->data - output);
                    for (uint32_t y = 0; y < (p == 0 ? 5u : 3u); y++) {
                        for (uint32_t x = 0; x < (p == 0 ? 5u : 3u); x++) {
                            memset(expected + offset + y * (size_t)plane->rowStride + x * plane->pixelStride,
                                (int)(30 + 40 * p), plane->sampleBytes);
                        }
                    }
                }
            }
            checks++;
            if (actual != cases[c].status || memcmp(output, expected, sizeof(output)) != 0) {
                failures++;
                printf("FAIL destination %s (%s): status %d expected %d, output/padding %s\n",
                    cases[c].name, operation == 0 ? "convert" : "flip", (int)actual, (int)cases[c].status,
                    memcmp(output, expected, sizeof(output)) == 0 ? "equal" : "differ");
            }
        }
    }
    /* No dereference: malformed addresses and huge valid strides reach only
     * the mutable descriptor validator, exercising native32/native64 bounds. */
    YuvMutableFrameV1 destination = make_bgra_destination();
    YuvValidatedMutableFrameView view;
    destination.planes[0].data = (uint8_t *)(uintptr_t)(UINTPTR_MAX - 1);
    expect_status("destination address wraps", yuv_validate_v1_mutable_frame(&destination, &view), YUV_STATUS_OVERFLOW);
    destination.width = 1;
    destination.height = 1;
    destination.planes[0].data = (uint8_t *)(uintptr_t)(UINTPTR_MAX - 3);
    expect_status("destination last byte at address limit", yuv_validate_v1_mutable_frame(&destination, &view), YUV_STATUS_OK);
    destination.format = YUV_FORMAT_I420;
    destination.colorMatrix = YUV_COLOR_MATRIX_BT601;
    destination.colorRange = YUV_COLOR_RANGE_LIMITED;
    destination.planeCount = 3;
    destination.width = 3;
    for (uint32_t p = 0; p < 3; p++) {
        destination.planes[p].data = (uint8_t *)(uintptr_t)(p == 0 ? 16 : p == 1 ? 4096 : 4097);
        destination.planes[p].length = SIZE_MAX;
        destination.planes[p].pixelStride = p == 0 ? 1 : UINT32_MAX - (p - 1);
        destination.planes[p].sampleBytes = 1;
        destination.planes[p].rowStride = p == 0 ? 3 : (uint64_t)UINT32_MAX + 1;
    }
    expect_status("large coprime strides collide", yuv_validate_v1_mutable_frame(&destination, &view),
        SIZE_MAX > UINT32_MAX ? YUV_STATUS_INVALID_ARGUMENT : YUV_STATUS_OVERFLOW);
    destination.planes[2].data = (uint8_t *)(uintptr_t)4098;
    expect_status("large coprime strides disjoint", yuv_validate_v1_mutable_frame(&destination, &view),
        SIZE_MAX > UINT32_MAX ? YUV_STATUS_OK : YUV_STATUS_OVERFLOW);
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 status and atomicity tests\n");
    printf("=============================================================\n");

    test_invalid_argument();
    printf("\n");
    test_unsupported_format();
    printf("\n");
    test_unsupported_color();
    printf("\n");
    test_overflow();
    printf("\n");
    test_unsupported_layout_unreachable();
    printf("\n");
    test_blur_options();
    printf("\n");
    test_transform_options();
    printf("\n");
    test_valid_descriptor_reaches_kernel();
    test_destination_sample_collisions();
    printf("\n");

    printf("=============================================================\n");
    if (failures != 0) {
        printf("%d of %d checks FAILED\n", failures, checks);
        printf("=============================================================\n");
        return EXIT_FAILURE;
    }
    printf("All %d checks passed!\n", checks);
    printf("=============================================================\n");
    return EXIT_SUCCESS;
}
