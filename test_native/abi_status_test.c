/*
 * ABI v1 status and atomicity tests (YUV-36b).
 *
 * Covers two things the design document treats as contract, not detail:
 *
 *  1. Each status reachable through ABI v1 validation has a concrete case.
 *     Status 3 is reserved for a future unsupported layout and its numeric
 *     value is pinned here; YUV-36d tests its Dart exception mapping directly.
 *
 *  2. Rejected descriptors leave the destination byte-for-byte untouched.
 *     Negative cases use a destination pre-filled with a canary pattern and
 *     check that pattern after the call. Valid calls separately confirm that
 *     validation reaches the temporary kernel stub.
 *
 * The kernels themselves are not implemented yet (YUV-31/32/22/23), so a fully
 * valid call currently returns YUV_STATUS_INTERNAL_ERROR. That is deliberate,
 * and the tests below assert exactly that for a valid descriptor: it proves
 * validation was passed rather than short-circuited, and it will start failing
 * the moment a kernel lands without this file being updated -- which is the
 * intended reminder.
 *
 * Checks are routed through helpers taking volatile locals so MSVC does not
 * report C4127 (constant conditional) under /W4 /WX, and failures are reported
 * through the exit code rather than abort(), whose 0xC0000409 on Windows CTest
 * does not treat as an ordinary non-zero return.
 */

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

/* ============================================================================
 * Fixtures
 *
 * A BGRA8888 frame is the simplest useful case: one plane, 4 bytes per sample,
 * no chroma subsampling to reason about. I420 is used where a multi-plane or
 * YUV-only rule is under test.
 * ============================================================================ */

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
        /* Section 9 groups an unknown numeric format with null pointers and bad
         * ABI versions: the descriptor is malformed, so INVALID_ARGUMENT.
         * UNSUPPORTED_FORMAT is reserved for a KNOWN format in a pairing an
         * operation does not accept. */
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

/* ============================================================================
 * Status 3: UNSUPPORTED_LAYOUT -- not reachable in ABI v1, by construction
 *
 * Section 11 defines status 3 as "the unsupported but structurally valid
 * layout". In ABI v1 that set is empty, and it is empty deliberately rather
 * than by omission:
 *
 *   - the same section states "Positive larger pixel/row strides are
 *     supported", so every structurally valid stride combination is accepted;
 *   - a plane that is too small, or whose sampleBytes/pixelStride disagree
 *     with its format, is not structurally valid -- that is INVALID_ARGUMENT;
 *   - a span whose arithmetic does not fit is OVERFLOW;
 *   - a known format in a pairing an operation does not accept is
 *     UNSUPPORTED_FORMAT.
 *
 * That partition leaves no input which is simultaneously structurally valid
 * and unimplementable, so no entry point can return 3 without first rejecting
 * a layout the contract explicitly requires it to support.
 *
 * The accepted YUV-33c foundation reached the same conclusion independently:
 * YuvViewStatus defines 0, 1, 2 and 4, with no layout status at all.
 *
 * This is therefore reported as a contract gap for the Engineer rather than
 * silently satisfied with a fabricated case. The check below pins the
 * constant so a renumbering still breaks a test, and states the reachability
 * fact in the output where a reviewer will see it.
 * ============================================================================ */

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
            YUV_STATUS_INTERNAL_ERROR);
        expect_true("      destination canary intact", destination_untouched());
    }
}

/* ============================================================================
 * Valid descriptors reach the kernel boundary
 * ============================================================================ */

static void test_valid_descriptor_reaches_kernel(void) {
    printf("Valid descriptors pass validation\n");

    /* Each of these is a fully valid call. Today the kernel is a stub, so the
     * expected status is INTERNAL_ERROR: reaching it proves validation
     * accepted the descriptor rather than rejecting it early. When YUV-31/32/
     * 22/23 land, these expectations become OK -- that is the intended signal
     * that this file needs updating alongside the kernel. */
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("grayscale reaches the kernel", yuv_grayscale_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
        expect_true("      destination still untouched by the stub", destination_untouched());
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("black-white reaches the kernel", yuv_black_white_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvEffectOptionsV1 options = make_effect_options();
        expect_status("negate reaches the kernel", yuv_negate_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvConvertOptionsV1 options = make_convert_options();
        expect_status("convert reaches the kernel", yuv_convert_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 0.0);
        expect_status("mean blur reaches the kernel", yuv_mean_blur_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 0.0);
        expect_status("box blur reaches the kernel", yuv_box_blur_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(2, 1.5);
        expect_status("gaussian blur reaches the kernel",
            yuv_gaussian_blur_v1(&source, &destination, &options), YUV_STATUS_INTERNAL_ERROR);
    }
    {
        /* radius 0 is a defined no-op, not an error, so it must pass
         * validation like any other accepted radius. */
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvBlurOptionsV1 options = make_blur_options(0, 0.0);
        expect_status("blur radius 0 is accepted", yuv_mean_blur_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvFlipOptionsV1 options = make_flip_options(YUV_FLIP_HORIZONTAL);
        expect_status("flip reaches the kernel", yuv_flip_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
    }
    {
        reset_buffers();
        YuvConstFrameV1 source = make_bgra_source();
        YuvMutableFrameV1 destination = make_bgra_destination();
        YuvRotateOptionsV1 options = make_rotate_options(180);
        expect_status("rotate 180 reaches the kernel", yuv_rotate_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
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
        expect_status("crop reaches the kernel", yuv_crop_v1(&source, &destination, &options),
            YUV_STATUS_INTERNAL_ERROR);
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
            yuv_grayscale_v1(&source, &destination, &options), YUV_STATUS_INTERNAL_ERROR);
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
            yuv_grayscale_v1(&source, &destination, &options), YUV_STATUS_INTERNAL_ERROR);
    }
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
