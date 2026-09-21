/*
 * ABI v1 blur tests (YUV-23): Gaussian, mean, box.
 *
 * YUV-11 reported 19 blur failures, and the audit behind them found the
 * causes were structural rather than numeric. The cases here target each one:
 *
 *  - results that depended on traversal order, because the kernel read the
 *    destination it was writing (probes gave 170 and 198 where the snapshot
 *    answer is 127) -- checked by blurring into a destination pre-filled with
 *    two different patterns and requiring the same output;
 *  - uninitialized bytes outside the region and destroyed alpha, from filling
 *    a scratch buffer only inside the rectangle and copying all of it back --
 *    checked by an explicit outside-region byte comparison and an alpha check;
 *  - mean and box disagreeing, though section 11 makes them one oracle --
 *    checked by requiring identical output for the same radius;
 *  - border handling, which the Engineer fixed as edge-replicate on
 *    2026-09-20: full kernel area, clamped coordinates, divisor always the
 *    full area -- checked against a flat image, where edge-replicate is the
 *    only rule that returns the flat value unchanged at the border.
 *
 * Checks use volatile locals (MSVC C4127 under /W4 /WX) and report through the
 * exit code rather than abort().
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yuv/abi/h/yuv_ops_v1.h"

static int checks = 0;
static int failures = 0;

static void expect_status(const char *label, YuvStatus actual, YuvStatus expected) {
    volatile int a = (int)actual;
    volatile int e = (int)expected;

    checks++;
    if (a == e) {
        printf("  ok    %-62s status=%d\n", label, (int)a);
    } else {
        printf("  FAIL  %-62s status=%d, expected %d\n", label, (int)a, (int)e);
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
 * ============================================================================ */

#define PAD 5
#define CANARY 0xC3
#define MAX_W 8
#define MAX_H 8
#define MAX_PLANE_BYTES ((MAX_W * 4 + PAD) * MAX_H)

typedef struct {
    uint32_t format;
    uint32_t width;
    uint32_t height;
    uint32_t planeCount;
    uint8_t planes[3][MAX_PLANE_BYTES];
    uint64_t rowStride[3];
    uint32_t pixelStride[3];
    uint32_t sampleBytes[3];
    uint64_t length[3];
} Frame;

static uint32_t plane_width(uint32_t format, uint32_t index, uint32_t width) {
    if (index == 0 || format == YUV_FORMAT_BGRA8888) {
        return width;
    }
    return (width + 1) / 2;
}

static uint32_t plane_height(uint32_t format, uint32_t index, uint32_t height) {
    if (index == 0 || format == YUV_FORMAT_BGRA8888) {
        return height;
    }
    return (height + 1) / 2;
}

static uint32_t plane_sample_bytes(uint32_t format, uint32_t index) {
    if (format == YUV_FORMAT_BGRA8888) {
        return 4;
    }
    if (format == YUV_FORMAT_NV12 && index == 1) {
        return 2;
    }
    return 1;
}

static void frame_init(Frame *frame, uint32_t format, uint32_t width, uint32_t height) {
    memset(frame, 0, sizeof(*frame));
    frame->format = format;
    frame->width = width;
    frame->height = height;
    frame->planeCount = format == YUV_FORMAT_I420 ? 3 : (format == YUV_FORMAT_NV12 ? 2 : 1);

    for (uint32_t index = 0; index < frame->planeCount; index++) {
        uint32_t sampleBytes = plane_sample_bytes(format, index);
        uint32_t pw = plane_width(format, index, width);
        uint32_t ph = plane_height(format, index, height);
        frame->sampleBytes[index] = sampleBytes;
        frame->pixelStride[index] = sampleBytes;
        frame->rowStride[index] = (uint64_t)pw * sampleBytes + PAD;
        frame->length[index] = frame->rowStride[index] * ph;
        memset(frame->planes[index], CANARY, (size_t)frame->length[index]);
    }
}

static uint8_t *frame_sample(Frame *frame, uint32_t index, uint32_t x, uint32_t y) {
    return frame->planes[index] + (size_t)(y * frame->rowStride[index] + x * frame->pixelStride[index]);
}

static YuvConstFrameV1 as_source(Frame *frame) {
    YuvConstFrameV1 out;
    memset(&out, 0, sizeof(out));
    out.structSize = (uint32_t)sizeof(out);
    out.abiVersion = YUV_ABI_VERSION_1;
    out.format = frame->format;
    out.planeCount = frame->planeCount;
    out.width = frame->width;
    out.height = frame->height;
    out.colorMatrix = frame->format == YUV_FORMAT_BGRA8888 ? YUV_COLOR_MATRIX_NONE : YUV_COLOR_MATRIX_BT601;
    out.colorRange = frame->format == YUV_FORMAT_BGRA8888 ? YUV_COLOR_RANGE_NONE : YUV_COLOR_RANGE_LIMITED;
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        out.planes[index].length = frame->length[index];
        out.planes[index].rowStride = frame->rowStride[index];
        out.planes[index].pixelStride = frame->pixelStride[index];
        out.planes[index].sampleBytes = frame->sampleBytes[index];
        out.planes[index].data = frame->planes[index];
    }
    return out;
}

static YuvMutableFrameV1 as_destination(Frame *frame) {
    YuvMutableFrameV1 out;
    memset(&out, 0, sizeof(out));
    out.structSize = (uint32_t)sizeof(out);
    out.abiVersion = YUV_ABI_VERSION_1;
    out.format = frame->format;
    out.planeCount = frame->planeCount;
    out.width = frame->width;
    out.height = frame->height;
    out.colorMatrix = frame->format == YUV_FORMAT_BGRA8888 ? YUV_COLOR_MATRIX_NONE : YUV_COLOR_MATRIX_BT601;
    out.colorRange = frame->format == YUV_FORMAT_BGRA8888 ? YUV_COLOR_RANGE_NONE : YUV_COLOR_RANGE_LIMITED;
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        out.planes[index].length = frame->length[index];
        out.planes[index].rowStride = frame->rowStride[index];
        out.planes[index].pixelStride = frame->pixelStride[index];
        out.planes[index].sampleBytes = frame->sampleBytes[index];
        out.planes[index].data = frame->planes[index];
    }
    return out;
}

static int padding_intact(Frame *frame) {
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        uint32_t pw = plane_width(frame->format, index, frame->width);
        uint32_t ph = plane_height(frame->format, index, frame->height);
        uint64_t span = (uint64_t)pw * frame->pixelStride[index];
        for (uint32_t y = 0; y < ph; y++) {
            for (uint64_t offset = span; offset < frame->rowStride[index]; offset++) {
                if (frame->planes[index][y * frame->rowStride[index] + offset] != CANARY) {
                    return 0;
                }
            }
        }
    }
    return 1;
}

static YuvBlurOptionsV1 blur_options(uint32_t radius, double sigma) {
    YuvBlurOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.radius = radius;
    options.sigma = sigma;
    options.borderMode = YUV_BORDER_CLAMP;
    options.region.structSize = (uint32_t)sizeof(YuvRegionOptionsV1);
    options.region.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

static void fill_bgra(Frame *frame, int alphaVaries) {
    for (uint32_t y = 0; y < frame->height; y++) {
        for (uint32_t x = 0; x < frame->width; x++) {
            uint8_t *sample = frame_sample(frame, 0, x, y);
            sample[0] = (uint8_t)((71 * x + 29 * y) % 256);
            sample[1] = (uint8_t)((17 * x + 53 * y) % 256);
            sample[2] = (uint8_t)((37 * x + 11 * y) % 256);
            sample[3] = alphaVaries ? (uint8_t)(100 + x + y) : 255;
        }
    }
}

/* ============================================================================
 * Edge-replicate against a flat image
 *
 * On a constant image, edge-replicate returns that constant everywhere,
 * including at the border, because every out-of-range kernel cell clamps onto
 * the same value. A shrinking-window implementation also returns it, but a
 * zero-padded one does not, and an implementation that divides by the number
 * of in-range cells while summing clamped ones does not either. This is the
 * cheapest check that separates the accepted rule from the rejected ones.
 * ============================================================================ */

static void test_flat_image_is_unchanged(void) {
    printf("Edge-replicate preserves a flat image\n");

    const uint32_t radii[3] = {1, 2, 3};
    for (uint32_t r = 0; r < 3; r++) {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 6, 5);
        for (uint32_t y = 0; y < 5; y++) {
            for (uint32_t x = 0; x < 6; x++) {
                uint8_t *sample = frame_sample(&source, 0, x, y);
                sample[0] = 90;
                sample[1] = 140;
                sample[2] = 200;
                sample[3] = 255;
            }
        }
        frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 5);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(radii[r], 0.0);

        char label[96];
        snprintf(label, sizeof(label), "mean blur radius %u on a flat image", radii[r]);
        expect_status(label, yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int ok = 1;
        for (uint32_t y = 0; y < 5 && ok; y++) {
            for (uint32_t x = 0; x < 6 && ok; x++) {
                uint8_t *sample = frame_sample(&destination, 0, x, y);
                if (sample[0] != 90 || sample[1] != 140 || sample[2] != 200) {
                    printf("  FAIL  (%u,%u) expected (90,140,200) got (%u,%u,%u)\n", x, y, sample[0],
                        sample[1], sample[2]);
                    ok = 0;
                }
            }
        }
        expect_true("      border pixels unchanged (full area, clamped reads)", ok);
        expect_true("      destination padding intact", padding_intact(&destination));
    }
}

/* ============================================================================
 * Explicit edge-replicate vector
 *
 * A hand-computed case, so the rule is pinned by an arithmetic result and not
 * only by an invariant. Image is 3x1, radius 1, values 10, 20, 30 in one
 * channel. For x=0 the kernel row is clamp(-1),clamp(0),clamp(1) = 10,10,20
 * and, being 1-D in a 1-row image, each of the 3 kernel rows repeats it:
 * sum = 3*(10+10+20) = 120, area = 9, (120 + 4) / 9 = 13.
 * ============================================================================ */

static void test_edge_replicate_vector(void) {
    printf("Edge-replicate arithmetic\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_BGRA8888, 3, 1);
    const uint8_t values[3] = {10, 20, 30};
    for (uint32_t x = 0; x < 3; x++) {
        uint8_t *sample = frame_sample(&source, 0, x, 0);
        sample[0] = values[x];
        sample[1] = values[x];
        sample[2] = values[x];
        sample[3] = 255;
    }
    frame_init(&destination, YUV_FORMAT_BGRA8888, 3, 1);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvBlurOptionsV1 options = blur_options(1, 0.0);
    expect_status("mean blur radius 1 on 3x1", yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options),
        YUV_STATUS_OK);

    /* x=0: 3*(10+10+20)=120, (120+4)/9 = 13
     * x=1: 3*(10+20+30)=180, (180+4)/9 = 20
     * x=2: 3*(20+30+30)=240, (240+4)/9 = 27 */
    const uint8_t expected[3] = {13, 20, 27};
    int ok = 1;
    for (uint32_t x = 0; x < 3; x++) {
        uint8_t actual = *frame_sample(&destination, 0, x, 0);
        if (actual != expected[x]) {
            printf("  FAIL  x=%u expected %u got %u\n", x, expected[x], actual);
            ok = 0;
        }
    }
    expect_true("      matches the hand-computed half-up result", ok);
}

/* ============================================================================
 * Mean and box are one oracle
 * ============================================================================ */

static void test_mean_and_box_agree(void) {
    printf("Mean and box agree\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};

    for (uint32_t f = 0; f < 3; f++) {
        Frame source;
        Frame mean;
        Frame box;
        frame_init(&source, formats[f], 5, 3);
        for (uint32_t index = 0; index < source.planeCount; index++) {
            uint32_t pw = plane_width(formats[f], index, 5);
            uint32_t ph = plane_height(formats[f], index, 3);
            for (uint32_t y = 0; y < ph; y++) {
                for (uint32_t x = 0; x < pw; x++) {
                    uint8_t *sample = frame_sample(&source, index, x, y);
                    for (uint32_t byte = 0; byte < source.sampleBytes[index]; byte++) {
                        sample[byte] = (uint8_t)(30 + 19 * x + 43 * y + 7 * byte);
                    }
                }
            }
        }
        frame_init(&mean, formats[f], 5, 3);
        frame_init(&box, formats[f], 5, 3);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 meanFrame = as_destination(&mean);
        YuvMutableFrameV1 boxFrame = as_destination(&box);
        YuvBlurOptionsV1 options = blur_options(2, 0.0);

        char label[96];
        snprintf(label, sizeof(label), "%s mean blur", names[f]);
        expect_status(label, yuv_mean_blur_v1(&sourceFrame, &meanFrame, &options), YUV_STATUS_OK);
        snprintf(label, sizeof(label), "%s box blur", names[f]);
        expect_status(label, yuv_box_blur_v1(&sourceFrame, &boxFrame, &options), YUV_STATUS_OK);

        int identical = 1;
        for (uint32_t index = 0; index < mean.planeCount && identical; index++) {
            uint32_t pw = plane_width(formats[f], index, 5);
            uint32_t ph = plane_height(formats[f], index, 3);
            for (uint32_t y = 0; y < ph && identical; y++) {
                for (uint32_t x = 0; x < pw && identical; x++) {
                    if (memcmp(frame_sample(&mean, index, x, y), frame_sample(&box, index, x, y),
                            mean.sampleBytes[index]) != 0) {
                        printf("  FAIL  %s plane %u (%u,%u) differs\n", names[f], index, x, y);
                        identical = 0;
                    }
                }
            }
        }
        expect_true("      identical for the same radius", identical);
        expect_true("      destination padding intact", padding_intact(&mean));
    }
}

/* ============================================================================
 * Order independence
 *
 * Blurring the same source into two destinations that start from different
 * contents must give the same answer. A kernel reading its own output as it
 * goes fails this; one reading an immutable snapshot cannot.
 * ============================================================================ */

static void test_order_independence(void) {
    printf("Result does not depend on destination contents\n");

    Frame source;
    Frame first;
    Frame second;
    frame_init(&source, YUV_FORMAT_BGRA8888, 6, 6);
    fill_bgra(&source, 0);
    frame_init(&first, YUV_FORMAT_BGRA8888, 6, 6);
    frame_init(&second, YUV_FORMAT_BGRA8888, 6, 6);

    /* Two different starting states for the destination. */
    for (uint32_t y = 0; y < 6; y++) {
        for (uint32_t x = 0; x < 6; x++) {
            memset(frame_sample(&first, 0, x, y), 0x00, 4);
            memset(frame_sample(&second, 0, x, y), 0xFF, 4);
        }
    }

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 firstFrame = as_destination(&first);
    YuvMutableFrameV1 secondFrame = as_destination(&second);
    YuvBlurOptionsV1 options = blur_options(2, 0.0);

    expect_status("blur into a zeroed destination",
        yuv_mean_blur_v1(&sourceFrame, &firstFrame, &options), YUV_STATUS_OK);
    expect_status("blur into a saturated destination",
        yuv_mean_blur_v1(&sourceFrame, &secondFrame, &options), YUV_STATUS_OK);

    int identical = 1;
    for (uint32_t y = 0; y < 6 && identical; y++) {
        for (uint32_t x = 0; x < 6 && identical; x++) {
            if (memcmp(frame_sample(&first, 0, x, y), frame_sample(&second, 0, x, y), 4) != 0) {
                printf("  FAIL  (%u,%u) depends on prior destination contents\n", x, y);
                identical = 0;
            }
        }
    }
    expect_true("      same result from both", identical);
}

/* ============================================================================
 * Alpha and region
 * ============================================================================ */

static void test_alpha_and_region(void) {
    printf("Alpha and region\n");

    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 6, 6);
        fill_bgra(&source, 1);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 6);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 0.0);
        expect_status("mean blur with varying alpha",
            yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int alphaOk = 1;
        for (uint32_t y = 0; y < 6 && alphaOk; y++) {
            for (uint32_t x = 0; x < 6 && alphaOk; x++) {
                uint8_t expected = *(frame_sample(&source, 0, x, y) + 3);
                uint8_t actual = *(frame_sample(&destination, 0, x, y) + 3);
                if (expected != actual) {
                    printf("  FAIL  alpha (%u,%u) expected %u got %u\n", x, y, expected, actual);
                    alphaOk = 0;
                }
            }
        }
        expect_true("      alpha copied, never convolved", alphaOk);
    }

    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 8, 8);
        fill_bgra(&source, 1);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 8, 8);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 0.0);
        options.region.enabled = 1;
        options.region.left = 2;
        options.region.top = 2;
        options.region.right = 6;
        options.region.bottom = 6;
        expect_status("mean blur inside a 4x4 region",
            yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int outsideOk = 1;
        for (uint32_t y = 0; y < 8 && outsideOk; y++) {
            for (uint32_t x = 0; x < 8 && outsideOk; x++) {
                int inside = x >= 2 && x < 6 && y >= 2 && y < 6;
                if (inside) {
                    continue;
                }
                if (memcmp(frame_sample(&source, 0, x, y), frame_sample(&destination, 0, x, y), 4) != 0) {
                    printf("  FAIL  outside region (%u,%u) not byte-identical to source\n", x, y);
                    outsideOk = 0;
                }
            }
        }
        expect_true("      outside the region is byte-identical, alpha included", outsideOk);
        expect_true("      destination padding intact", padding_intact(&destination));
    }
}

/* ============================================================================
 * Radius 0 and Gaussian
 * ============================================================================ */

static void test_radius_zero(void) {
    printf("Radius 0\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_BGRA8888, 5, 4);
    fill_bgra(&source, 1);
    frame_init(&destination, YUV_FORMAT_BGRA8888, 5, 4);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvBlurOptionsV1 options = blur_options(0, 0.0);
    expect_status("mean blur radius 0", yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options),
        YUV_STATUS_OK);

    int identical = 1;
    for (uint32_t y = 0; y < 4 && identical; y++) {
        for (uint32_t x = 0; x < 5 && identical; x++) {
            if (memcmp(frame_sample(&source, 0, x, y), frame_sample(&destination, 0, x, y), 4) != 0) {
                identical = 0;
            }
        }
    }
    expect_true("      is an exact copy", identical);
}

static void test_gaussian(void) {
    printf("Gaussian\n");

    /* A flat image is preserved by any correctly normalized weighted mean,
     * whatever the weights are, so this checks normalization and the border
     * rule together. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 6, 5);
        for (uint32_t y = 0; y < 5; y++) {
            for (uint32_t x = 0; x < 6; x++) {
                uint8_t *sample = frame_sample(&source, 0, x, y);
                sample[0] = 70;
                sample[1] = 70;
                sample[2] = 70;
                sample[3] = 255;
            }
        }
        frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 5);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 1.5);
        expect_status("gaussian blur on a flat image",
            yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int ok = 1;
        for (uint32_t y = 0; y < 5 && ok; y++) {
            for (uint32_t x = 0; x < 6 && ok; x++) {
                uint8_t *sample = frame_sample(&destination, 0, x, y);
                if (sample[0] != 70 || sample[1] != 70 || sample[2] != 70) {
                    printf("  FAIL  (%u,%u) expected 70 got %u\n", x, y, sample[0]);
                    ok = 0;
                }
            }
        }
        expect_true("      weights normalized, border replicated", ok);
        expect_true("      destination padding intact", padding_intact(&destination));
    }

    /* A large sigma makes the Gaussian approach uniform weights, so its
     * result must converge towards the mean blur's. Checking the direction of
     * that relationship catches a kernel built with the wrong exponent sign,
     * which would instead concentrate all weight on the centre. */
    {
        Frame source;
        Frame gaussian;
        Frame mean;
        frame_init(&source, YUV_FORMAT_BGRA8888, 6, 6);
        fill_bgra(&source, 0);
        frame_init(&gaussian, YUV_FORMAT_BGRA8888, 6, 6);
        frame_init(&mean, YUV_FORMAT_BGRA8888, 6, 6);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 gaussianFrame = as_destination(&gaussian);
        YuvMutableFrameV1 meanFrame = as_destination(&mean);
        YuvBlurOptionsV1 gaussianOptions = blur_options(2, 60.0);
        YuvBlurOptionsV1 meanOptions = blur_options(2, 0.0);

        expect_status("gaussian with a large sigma",
            yuv_gaussian_blur_v1(&sourceFrame, &gaussianFrame, &gaussianOptions), YUV_STATUS_OK);
        expect_status("mean for comparison", yuv_mean_blur_v1(&sourceFrame, &meanFrame, &meanOptions),
            YUV_STATUS_OK);

        int maxDelta = 0;
        for (uint32_t y = 0; y < 6; y++) {
            for (uint32_t x = 0; x < 6; x++) {
                for (uint32_t channel = 0; channel < 3; channel++) {
                    int delta = abs((int)frame_sample(&gaussian, 0, x, y)[channel] -
                        (int)frame_sample(&mean, 0, x, y)[channel]);
                    if (delta > maxDelta) {
                        maxDelta = delta;
                    }
                }
            }
        }
        char label[96];
        snprintf(label, sizeof(label), "      converges to the uniform mean (max delta %d)", maxDelta);
        expect_true(label, maxDelta <= 2);
    }

    /* sigma must be strictly positive and finite for a weighted kernel. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 4, 4);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 0.0);
        expect_status("gaussian rejects sigma 0",
            yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);

        options.sigma = -1.0;
        expect_status("gaussian rejects a negative sigma",
            yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
    }
}

/* ============================================================================
 * Odd geometry
 * ============================================================================ */

static void test_odd_geometry(void) {
    printf("Odd geometry\n");

    const uint32_t formats[2] = {YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[2] = {"I420", "NV12"};

    for (uint32_t f = 0; f < 2; f++) {
        Frame source;
        Frame destination;
        frame_init(&source, formats[f], 5, 3);
        for (uint32_t index = 0; index < source.planeCount; index++) {
            uint32_t pw = plane_width(formats[f], index, 5);
            uint32_t ph = plane_height(formats[f], index, 3);
            for (uint32_t y = 0; y < ph; y++) {
                for (uint32_t x = 0; x < pw; x++) {
                    uint8_t *sample = frame_sample(&source, index, x, y);
                    for (uint32_t byte = 0; byte < source.sampleBytes[index]; byte++) {
                        sample[byte] = (uint8_t)(50 + 23 * x + 37 * y + byte);
                    }
                }
            }
        }
        frame_init(&destination, formats[f], 5, 3);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(1, 0.0);

        char label[96];
        snprintf(label, sizeof(label), "%s 5x3 mean blur", names[f]);
        expect_status(label, yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        /* Every chroma sample, including the trailing odd column and row,
         * must have been written: a floor-geometry kernel leaves the last one
         * at its canary. */
        int written = 1;
        uint32_t cw = (5 + 1) / 2;
        uint32_t ch = (3 + 1) / 2;
        for (uint32_t index = 1; index < destination.planeCount && written; index++) {
            for (uint32_t y = 0; y < ch && written; y++) {
                for (uint32_t x = 0; x < cw && written; x++) {
                    uint8_t *sample = frame_sample(&destination, index, x, y);
                    for (uint32_t byte = 0; byte < destination.sampleBytes[index]; byte++) {
                        if (sample[byte] == CANARY) {
                            printf("  FAIL  %s plane %u chroma (%u,%u) never written\n", names[f], index, x,
                                y);
                            written = 0;
                            break;
                        }
                    }
                }
            }
        }
        expect_true("      every chroma sample written, trailing row/column included", written);
        expect_true("      destination padding intact", padding_intact(&destination));
    }
}

/* ============================================================================
 * Region of interest on 4:2:0
 *
 * The defect the reviewer of the first YUV-23 submission caught. The BGRA
 * region case above passed while this one would not have: blur wrote the
 * whole destination through the frame encoder, which re-derives every luma
 * sample from the decoded snapshot. For BGRA that round trip happens to be
 * lossless, so nothing showed; for I420 and NV12 it re-quantizes, and a Y
 * sample outside the region came back changed (the reviewer reproduced
 * 17 -> 25).
 *
 * Luma outside the region must therefore be byte-identical. Chroma is a
 * separate matter: a chroma sample whose 2x2 footprint intersects the region
 * is re-encoded by contract (section 14 Q2), so only blocks entirely outside
 * the region are required to be untouched.
 * ============================================================================ */

static void test_region_on_420(void) {
    printf("Region of interest on 4:2:0\n");

    const uint32_t formats[2] = {YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[2] = {"I420", "NV12"};

    for (uint32_t f = 0; f < 2; f++) {
        Frame source;
        Frame destination;
        frame_init(&source, formats[f], 8, 8);
        for (uint32_t index = 0; index < source.planeCount; index++) {
            uint32_t pw = plane_width(formats[f], index, 8);
            uint32_t ph = plane_height(formats[f], index, 8);
            for (uint32_t y = 0; y < ph; y++) {
                for (uint32_t x = 0; x < pw; x++) {
                    uint8_t *sample = frame_sample(&source, index, x, y);
                    for (uint32_t byte = 0; byte < source.sampleBytes[index]; byte++) {
                        sample[byte] = (uint8_t)(16 + 13 * x + 29 * y + 5 * byte);
                    }
                }
            }
        }
        frame_init(&destination, formats[f], 8, 8);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(1, 0.0);
        options.region.enabled = 1;
        options.region.left = 2;
        options.region.top = 2;
        options.region.right = 6;
        options.region.bottom = 6;

        char label[96];
        snprintf(label, sizeof(label), "%s mean blur inside a 4x4 region", names[f]);
        expect_status(label, yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int lumaOk = 1;
        for (uint32_t y = 0; y < 8 && lumaOk; y++) {
            for (uint32_t x = 0; x < 8 && lumaOk; x++) {
                int inside = x >= 2 && x < 6 && y >= 2 && y < 6;
                if (inside) {
                    continue;
                }
                uint8_t expected = *frame_sample(&source, 0, x, y);
                uint8_t actual = *frame_sample(&destination, 0, x, y);
                if (expected != actual) {
                    printf("  FAIL  %s luma (%u,%u) outside region: %u -> %u\n", names[f], x, y, expected,
                        actual);
                    lumaOk = 0;
                }
            }
        }
        expect_true("      luma outside the region is byte-identical", lumaOk);

        /* A chroma block is entirely outside the region when none of its four
         * luma pixels is selected. Those must be copied verbatim. */
        int chromaOk = 1;
        for (uint32_t blockY = 0; blockY < 4 && chromaOk; blockY++) {
            for (uint32_t blockX = 0; blockX < 4 && chromaOk; blockX++) {
                int intersects = 0;
                for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                    for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                        uint32_t x = blockX * 2 + offsetX;
                        uint32_t y = blockY * 2 + offsetY;
                        if (x >= 2 && x < 6 && y >= 2 && y < 6) {
                            intersects = 1;
                        }
                    }
                }
                if (intersects) {
                    continue;
                }
                for (uint32_t index = 1; index < destination.planeCount && chromaOk; index++) {
                    if (memcmp(frame_sample(&source, index, blockX, blockY),
                            frame_sample(&destination, index, blockX, blockY),
                            destination.sampleBytes[index]) != 0) {
                        printf("  FAIL  %s plane %u chroma block (%u,%u) outside region changed\n",
                            names[f], index, blockX, blockY);
                        chromaOk = 0;
                    }
                }
            }
        }
        expect_true("      chroma blocks fully outside the region are untouched", chromaOk);
        expect_true("      destination padding intact", padding_intact(&destination));
    }

    /* The reviewer's exact shape: a 1x1 region, where every other sample of
     * the frame must survive unchanged. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_I420, 4, 4);
        for (uint32_t y = 0; y < 4; y++) {
            for (uint32_t x = 0; x < 4; x++) {
                *frame_sample(&source, 0, x, y) = (uint8_t)(16 + y * 4 + x);
            }
        }
        for (uint32_t y = 0; y < 2; y++) {
            for (uint32_t x = 0; x < 2; x++) {
                *frame_sample(&source, 1, x, y) = (uint8_t)(100 + y * 2 + x);
                *frame_sample(&source, 2, x, y) = (uint8_t)(140 + y * 2 + x);
            }
        }
        frame_init(&destination, YUV_FORMAT_I420, 4, 4);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(1, 0.0);
        options.region.enabled = 1;
        options.region.left = 1;
        options.region.top = 1;
        options.region.right = 2;
        options.region.bottom = 2;
        expect_status("I420 mean blur with a 1x1 region",
            yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int ok = 1;
        for (uint32_t y = 0; y < 4 && ok; y++) {
            for (uint32_t x = 0; x < 4 && ok; x++) {
                if (x == 1 && y == 1) {
                    continue;
                }
                uint8_t expected = *frame_sample(&source, 0, x, y);
                uint8_t actual = *frame_sample(&destination, 0, x, y);
                if (expected != actual) {
                    printf("  FAIL  luma (%u,%u) outside a 1x1 region: %u -> %u\n", x, y, expected, actual);
                    ok = 0;
                }
            }
        }
        expect_true("      only the single selected luma sample changed", ok);
    }
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 blur tests (YUV-23)\n");
    printf("=============================================================\n");

    test_flat_image_is_unchanged();
    test_edge_replicate_vector();
    test_mean_and_box_agree();
    test_order_independence();
    test_alpha_and_region();
    test_region_on_420();
    test_radius_zero();
    test_gaussian();
    test_odd_geometry();

    printf("-------------------------------------------------------------\n");
    printf("checks: %d, failures: %d\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
