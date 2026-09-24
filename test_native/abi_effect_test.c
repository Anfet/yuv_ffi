/*
 * ABI v1 effect tests (YUV-22): grayscale, black-white, negate, chroma swap.
 *
 * YUV-11 reported six reference failures here, and each had a specific cause
 * that this file pins:
 *
 *  - grayscale truncated where the oracle rounds (MAE 0.264, max 1);
 *  - black-white used `> 128` where the documented threshold is `>= 128`,
 *    which flips exactly the pixels whose gray is 128 -- a 255-wide error;
 *  - negate inverted the stored Y/U/V samples, which is not RGB negation in
 *    limited range (MAE 8.152, max 134), and computed chroma as 256 - value,
 *    which is unrepresentable for an input of 0.
 *
 * The boundary cases are therefore not decoration: gray exactly 128, and a
 * chroma sample of exactly 0, are the inputs that separate the contract from
 * the defect. Both appear below as explicit vectors.
 *
 * The other half of the contract is that the three formats agree: one visible
 * image, stored as BGRA, I420, and NV12, must come back visibly equal after
 * the same effect. That is checked directly, with a tolerance that covers
 * 4:2:0 chroma quantization but nothing larger.
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
 * Oracle, transcribed from test_pattern_reference.dart
 * ============================================================================ */

static int clip(int value) {
    return value < 0 ? 0 : (value > 255 ? 255 : value);
}

static int oracle_gray(int r, int g, int b) {
    return clip((299 * r + 587 * g + 114 * b + 500) / 1000);
}

static int oracle_luma(int r, int g, int b) {
    return clip(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
}

static void oracle_decode(int y, int u, int v, int *r, int *g, int *b) {
    int c = y - 16;
    int d = u - 128;
    int e = v - 128;
    *r = clip((298 * c + 409 * e + 128) >> 8);
    *g = clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    *b = clip((298 * c + 516 * d + 128) >> 8);
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

static YuvEffectOptionsV1 effect_options(void) {
    YuvEffectOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.region.structSize = (uint32_t)sizeof(YuvRegionOptionsV1);
    options.region.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

static YuvEffectOptionsV1 region_options(int32_t left, int32_t top, int32_t right, int32_t bottom) {
    YuvEffectOptionsV1 options = effect_options();
    options.region.enabled = 1;
    options.region.left = left;
    options.region.top = top;
    options.region.right = right;
    options.region.bottom = bottom;
    return options;
}

/* Reads a frame back as visible RGB, so results in different storage formats
 * can be compared to each other on equal terms. */
static void read_visible(Frame *frame, uint32_t x, uint32_t y, int *r, int *g, int *b, int *a) {
    if (frame->format == YUV_FORMAT_BGRA8888) {
        uint8_t *sample = frame_sample(frame, 0, x, y);
        *b = sample[0];
        *g = sample[1];
        *r = sample[2];
        *a = sample[3];
        return;
    }
    int luma = *frame_sample(frame, 0, x, y);
    int u;
    int v;
    if (frame->format == YUV_FORMAT_I420) {
        u = *frame_sample(frame, 1, x / 2, y / 2);
        v = *frame_sample(frame, 2, x / 2, y / 2);
    } else {
        uint8_t *uv = frame_sample(frame, 1, x / 2, y / 2);
        u = uv[0];
        v = uv[1];
    }
    oracle_decode(luma, u, v, r, g, b);
    *a = 255;
}

static void image_rgb(uint32_t x, uint32_t y, int *r, int *g, int *b) {
    *r = (int)((37 * x + 11 * y) % 256);
    *g = (int)((17 * x + 53 * y) % 256);
    *b = (int)((71 * x + 29 * y) % 256);
}

/* Builds the same visible image in the requested storage format. The YUV
 * variants are encoded with the oracle, flat across each 2x2 block so that
 * decoding them back is lossless and a format-parity comparison measures the
 * effect rather than the subsampling. */
static void fill_image(Frame *frame) {
    if (frame->format == YUV_FORMAT_BGRA8888) {
        for (uint32_t y = 0; y < frame->height; y++) {
            for (uint32_t x = 0; x < frame->width; x++) {
                int r;
                int g;
                int b;
                image_rgb(x - x % 2, y - y % 2, &r, &g, &b);
                uint8_t *sample = frame_sample(frame, 0, x, y);
                sample[0] = (uint8_t)b;
                sample[1] = (uint8_t)g;
                sample[2] = (uint8_t)r;
                sample[3] = 255;
            }
        }
        return;
    }

    for (uint32_t y = 0; y < frame->height; y++) {
        for (uint32_t x = 0; x < frame->width; x++) {
            int r;
            int g;
            int b;
            image_rgb(x - x % 2, y - y % 2, &r, &g, &b);
            *frame_sample(frame, 0, x, y) = (uint8_t)oracle_luma(r, g, b);
        }
    }
    uint32_t cw = (frame->width + 1) / 2;
    uint32_t ch = (frame->height + 1) / 2;
    for (uint32_t y = 0; y < ch; y++) {
        for (uint32_t x = 0; x < cw; x++) {
            int r;
            int g;
            int b;
            image_rgb(x * 2, y * 2, &r, &g, &b);
            int u = clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
            int v = clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
            if (frame->format == YUV_FORMAT_I420) {
                *frame_sample(frame, 1, x, y) = (uint8_t)u;
                *frame_sample(frame, 2, x, y) = (uint8_t)v;
            } else {
                uint8_t *uv = frame_sample(frame, 1, x, y);
                uv[0] = (uint8_t)u;
                uv[1] = (uint8_t)v;
            }
        }
    }
}

typedef enum { EFFECT_GRAYSCALE, EFFECT_BLACK_WHITE, EFFECT_NEGATE } EffectKind;

static YuvStatus run_effect(
    EffectKind kind, const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options) {
    switch (kind) {
        case EFFECT_GRAYSCALE:
            return yuv_grayscale_v1(source, destination, options);
        case EFFECT_BLACK_WHITE:
            return yuv_black_white_v1(source, destination, options);
        case EFFECT_NEGATE:
        default:
            return yuv_negate_v1(source, destination, options);
    }
}

static void expected_rgb(EffectKind kind, int r, int g, int b, int *outR, int *outG, int *outB) {
    switch (kind) {
        case EFFECT_GRAYSCALE: {
            int gray = oracle_gray(r, g, b);
            *outR = gray;
            *outG = gray;
            *outB = gray;
            return;
        }
        case EFFECT_BLACK_WHITE: {
            int value = oracle_gray(r, g, b) >= 128 ? 255 : 0;
            *outR = value;
            *outG = value;
            *outB = value;
            return;
        }
        case EFFECT_NEGATE:
        default:
            *outR = 255 - r;
            *outG = 255 - g;
            *outB = 255 - b;
            return;
    }
}

static const EffectKind KINDS[3] = {EFFECT_GRAYSCALE, EFFECT_BLACK_WHITE, EFFECT_NEGATE};
static const char *KIND_NAMES[3] = {"grayscale", "black-white", "negate"};

/* ============================================================================
 * BGRA against the oracle, exactly
 *
 * BGRA has no subsampling, so the result must match the oracle with zero
 * tolerance. This is where the rounding and threshold defects show up
 * undiluted.
 * ============================================================================ */

static void test_bgra_exact(void) {
    printf("BGRA effects match the oracle exactly\n");

    for (uint32_t k = 0; k < 3; k++) {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 8, 8);
        for (uint32_t y = 0; y < 8; y++) {
            for (uint32_t x = 0; x < 8; x++) {
                int r;
                int g;
                int b;
                image_rgb(x, y, &r, &g, &b);
                uint8_t *sample = frame_sample(&source, 0, x, y);
                sample[0] = (uint8_t)b;
                sample[1] = (uint8_t)g;
                sample[2] = (uint8_t)r;
                sample[3] = (uint8_t)(100 + x + y);
            }
        }
        frame_init(&destination, YUV_FORMAT_BGRA8888, 8, 8);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();

        char label[96];
        snprintf(label, sizeof(label), "BGRA %s", KIND_NAMES[k]);
        expect_status(label, run_effect(KINDS[k], &sourceFrame, &destinationFrame, &options),
            YUV_STATUS_OK);

        int ok = 1;
        int alphaOk = 1;
        for (uint32_t y = 0; y < 8 && ok; y++) {
            for (uint32_t x = 0; x < 8 && ok; x++) {
                int r;
                int g;
                int b;
                image_rgb(x, y, &r, &g, &b);
                int expectedR;
                int expectedG;
                int expectedB;
                expected_rgb(KINDS[k], r, g, b, &expectedR, &expectedG, &expectedB);
                uint8_t *sample = frame_sample(&destination, 0, x, y);
                if (sample[0] != expectedB || sample[1] != expectedG || sample[2] != expectedR) {
                    printf("  FAIL  %s (%u,%u) expected B=%d G=%d R=%d got B=%u G=%u R=%u\n", KIND_NAMES[k],
                        x, y, expectedB, expectedG, expectedR, sample[0], sample[1], sample[2]);
                    ok = 0;
                }
                if (sample[3] != (uint8_t)(100 + x + y)) {
                    alphaOk = 0;
                }
            }
        }
        expect_true("      matches the oracle", ok);
        expect_true("      alpha preserved byte-exact", alphaOk);
        expect_true("      destination padding intact", padding_intact(&destination));
    }
}

/* ============================================================================
 * Boundary vectors
 * ============================================================================ */

static void test_boundaries(void) {
    printf("Boundary vectors\n");

    /* A pixel whose rounded gray is exactly 128 must become white, not black.
     * Grey 128 comes from R=G=B=128: (299+587+114)*128 = 128000, +500, /1000
     * = 128. The legacy `> 128` test made this pixel black. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 2, 1);
        uint8_t *first = frame_sample(&source, 0, 0, 0);
        first[0] = 128;
        first[1] = 128;
        first[2] = 128;
        first[3] = 255;
        /* And one step below, which must stay black. */
        uint8_t *second = frame_sample(&source, 0, 1, 0);
        second[0] = 127;
        second[1] = 127;
        second[2] = 127;
        second[3] = 255;
        frame_init(&destination, YUV_FORMAT_BGRA8888, 2, 1);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();
        expect_status("black-white at the 128 threshold",
            yuv_black_white_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
        expect_true("      gray 128 becomes white (>= 128, not > 128)",
            *frame_sample(&destination, 0, 0, 0) == 255);
        expect_true("      gray 127 stays black", *frame_sample(&destination, 0, 1, 0) == 0);
    }

    /* Negate of a chroma sample of 0. The legacy kernels computed 256 - value
     * for chroma, which is 256 for an input of 0 and wraps to 0 in a uint8_t
     * -- leaving the sample unchanged where it should have moved. Going
     * through RGB has no such hole, so the check is simply that the visible
     * result is the RGB negation. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_I420, 2, 2);
        for (uint32_t y = 0; y < 2; y++) {
            for (uint32_t x = 0; x < 2; x++) {
                *frame_sample(&source, 0, x, y) = 128;
            }
        }
        *frame_sample(&source, 1, 0, 0) = 0;
        *frame_sample(&source, 2, 0, 0) = 255;
        frame_init(&destination, YUV_FORMAT_I420, 2, 2);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();
        expect_status("negate with chroma 0 and 255",
            yuv_negate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int r;
        int g;
        int b;
        int a;
        read_visible(&source, 0, 0, &r, &g, &b, &a);
        int expectedR = 255 - r;
        int expectedG = 255 - g;
        int expectedB = 255 - b;
        int actualR;
        int actualG;
        int actualB;
        int actualA;
        read_visible(&destination, 0, 0, &actualR, &actualG, &actualB, &actualA);
        int close = abs(actualR - expectedR) <= 3 && abs(actualG - expectedG) <= 3 &&
            abs(actualB - expectedB) <= 3;
        if (!close) {
            printf("  FAIL  negate chroma-0: expected ~(%d,%d,%d) got (%d,%d,%d)\n", expectedR, expectedG,
                expectedB, actualR, actualG, actualB);
        }
        expect_true("      visible result is the RGB negation", close);
    }
}

/* ============================================================================
 * Cross-format visible parity
 * ============================================================================ */

static void test_format_parity(void) {
    printf("Formats agree on the visible result\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};

    for (uint32_t k = 0; k < 3; k++) {
        Frame results[3];
        int ran = 1;
        for (uint32_t f = 0; f < 3; f++) {
            Frame source;
            frame_init(&source, formats[f], 8, 8);
            fill_image(&source);
            frame_init(&results[f], formats[f], 8, 8);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&results[f]);
            YuvEffectOptionsV1 options = effect_options();
            char label[96];
            snprintf(label, sizeof(label), "%s %s", names[f], KIND_NAMES[k]);
            YuvStatus status = run_effect(KINDS[k], &sourceFrame, &destinationFrame, &options);
            expect_status(label, status, YUV_STATUS_OK);
            if (status != YUV_STATUS_OK) {
                ran = 0;
            }
        }
        if (!ran) {
            continue;
        }

        /* Tolerance covers one 4:2:0 encode/decode round trip of the chroma
         * channels, which is unavoidable for a YUV frame and is not what
         * these tests are looking for. The old negate defect was max 134,
         * far outside it. */
        int maxDelta = 0;
        for (uint32_t y = 0; y < 8; y++) {
            for (uint32_t x = 0; x < 8; x++) {
                int reference[4];
                read_visible(&results[0], x, y, &reference[0], &reference[1], &reference[2], &reference[3]);
                for (uint32_t f = 1; f < 3; f++) {
                    int actual[4];
                    read_visible(&results[f], x, y, &actual[0], &actual[1], &actual[2], &actual[3]);
                    for (uint32_t channel = 0; channel < 3; channel++) {
                        int delta = abs(actual[channel] - reference[channel]);
                        if (delta > maxDelta) {
                            maxDelta = delta;
                        }
                    }
                }
            }
        }
        char label[96];
        snprintf(label, sizeof(label), "      %s: BGRA/I420/NV12 agree (max delta %d)", KIND_NAMES[k],
            maxDelta);
        expect_true(label, maxDelta <= 8);
    }
}

/* ============================================================================
 * Region of interest
 * ============================================================================ */

static void test_region(void) {
    printf("Region of interest\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_BGRA8888, 8, 8);
    for (uint32_t y = 0; y < 8; y++) {
        for (uint32_t x = 0; x < 8; x++) {
            int r;
            int g;
            int b;
            image_rgb(x, y, &r, &g, &b);
            uint8_t *sample = frame_sample(&source, 0, x, y);
            sample[0] = (uint8_t)b;
            sample[1] = (uint8_t)g;
            sample[2] = (uint8_t)r;
            sample[3] = 255;
        }
    }
    frame_init(&destination, YUV_FORMAT_BGRA8888, 8, 8);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvEffectOptionsV1 options = region_options(2, 2, 6, 6);
    expect_status("negate inside a 4x4 region",
        yuv_negate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

    int ok = 1;
    for (uint32_t y = 0; y < 8 && ok; y++) {
        for (uint32_t x = 0; x < 8 && ok; x++) {
            uint8_t *from = frame_sample(&source, 0, x, y);
            uint8_t *to = frame_sample(&destination, 0, x, y);
            int inside = x >= 2 && x < 6 && y >= 2 && y < 6;
            if (inside) {
                if (to[0] != (uint8_t)(255 - from[0]) || to[1] != (uint8_t)(255 - from[1]) ||
                    to[2] != (uint8_t)(255 - from[2])) {
                    printf("  FAIL  inside region (%u,%u) not negated\n", x, y);
                    ok = 0;
                }
            } else if (memcmp(from, to, 4) != 0) {
                printf("  FAIL  outside region (%u,%u) was modified\n", x, y);
                ok = 0;
            }
        }
    }
    expect_true("      inside negated, outside byte-identical", ok);
    expect_true("      destination padding intact", padding_intact(&destination));
}

/* ============================================================================
 * Chroma swap (YUV-31, section 14 Q1)
 * ============================================================================ */

static void test_chroma_swap(void) {
    printf("Chroma swap\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_NV12, 5, 3);
    for (uint32_t y = 0; y < 3; y++) {
        for (uint32_t x = 0; x < 5; x++) {
            *frame_sample(&source, 0, x, y) = (uint8_t)(40 + 7 * x + 11 * y);
        }
    }
    for (uint32_t y = 0; y < 2; y++) {
        for (uint32_t x = 0; x < 3; x++) {
            uint8_t *uv = frame_sample(&source, 1, x, y);
            uv[0] = (uint8_t)(60 + x);
            uv[1] = (uint8_t)(200 - y);
        }
    }
    frame_init(&destination, YUV_FORMAT_NV12, 5, 3);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvEffectOptionsV1 options = effect_options();
    expect_status("NV12 5x3 chroma swap", yuv_chroma_swap_v1(&sourceFrame, &destinationFrame, &options),
        YUV_STATUS_OK);

    int lumaOk = 1;
    for (uint32_t y = 0; y < 3 && lumaOk; y++) {
        for (uint32_t x = 0; x < 5 && lumaOk; x++) {
            if (*frame_sample(&source, 0, x, y) != *frame_sample(&destination, 0, x, y)) {
                printf("  FAIL  luma (%u,%u) changed\n", x, y);
                lumaOk = 0;
            }
        }
    }
    expect_true("      luma copied unchanged", lumaOk);

    int chromaOk = 1;
    for (uint32_t y = 0; y < 2 && chromaOk; y++) {
        for (uint32_t x = 0; x < 3 && chromaOk; x++) {
            uint8_t *from = frame_sample(&source, 1, x, y);
            uint8_t *to = frame_sample(&destination, 1, x, y);
            if (to[0] != from[1] || to[1] != from[0]) {
                printf("  FAIL  chroma (%u,%u) expected (%u,%u) got (%u,%u)\n", x, y, from[1], from[0],
                    to[0], to[1]);
                chromaOk = 0;
            }
        }
    }
    expect_true("      every UV pair swapped, including the odd trailing block", chromaOk);
    expect_true("      destination padding intact", padding_intact(&destination));

    /* Swapping twice is the identity, which no partial or order-dependent
     * implementation satisfies. */
    Frame twice;
    frame_init(&twice, YUV_FORMAT_NV12, 5, 3);
    YuvConstFrameV1 once = as_source(&destination);
    YuvMutableFrameV1 back = as_destination(&twice);
    expect_status("swapping twice", yuv_chroma_swap_v1(&once, &back, &options), YUV_STATUS_OK);
    int identity = 1;
    for (uint32_t y = 0; y < 2 && identity; y++) {
        for (uint32_t x = 0; x < 3 && identity; x++) {
            if (memcmp(frame_sample(&source, 1, x, y), frame_sample(&twice, 1, x, y), 2) != 0) {
                identity = 0;
            }
        }
    }
    expect_true("      is the identity", identity);
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 effect tests (YUV-22)\n");
    printf("=============================================================\n");

    test_bgra_exact();
    test_boundaries();
    test_format_parity();
    test_region();
    test_chroma_swap();

    printf("-------------------------------------------------------------\n");
    printf("checks: %d, failures: %d\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
