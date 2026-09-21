/*
 * ABI v1 conversion tests (YUV-32).
 *
 * The defect this file exists to prevent is not a crash but a disagreement:
 * RGBA->YUV used BT.601 limited range and averaged the real 2x2 block, while
 * BGRA->YUV used a full-range matrix and took chroma from the top-left pixel
 * only. The same picture therefore encoded to different bytes depending on
 * which channel order it arrived in.
 *
 * So the central case here is a parity case: build one image, present it as
 * RGBA and as the byte-swapped BGRA, convert both, and require the two
 * results to be identical sample for sample. That check fails for either half
 * of the old defect -- a different matrix or a different chroma reducer --
 * without this test needing to know which matrix is "right".
 *
 * Separately, the absolute values are pinned against the reference oracle
 * (test/helpers/reference/test_pattern_reference.dart) recomputed here in C:
 * parity alone would also be satisfied by two paths that agree and are both
 * wrong.
 *
 * Checks use volatile locals (MSVC C4127 under /W4 /WX) and report through the
 * exit code rather than abort().
 */

#include <stdint.h>
#include <stdio.h>
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
 * Reference oracle, transcribed from test_pattern_reference.dart
 *
 * Deliberately written out again rather than calling the kernel's own
 * helpers: an oracle that shares code with the thing it checks cannot catch a
 * wrong coefficient.
 * ============================================================================ */

static int clip(int value) {
    return value < 0 ? 0 : (value > 255 ? 255 : value);
}

static int oracle_luma(int r, int g, int b) {
    return clip(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
}

static int oracle_u(int r, int g, int b) {
    return clip(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
}

static int oracle_v(int r, int g, int b) {
    return clip(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
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
    if (index == 0 || format == YUV_FORMAT_BGRA8888 || format == YUV_FORMAT_RGBA8888) {
        return width;
    }
    return (width + 1) / 2;
}

static uint32_t plane_height(uint32_t format, uint32_t index, uint32_t height) {
    if (index == 0 || format == YUV_FORMAT_BGRA8888 || format == YUV_FORMAT_RGBA8888) {
        return height;
    }
    return (height + 1) / 2;
}

static uint32_t plane_sample_bytes(uint32_t format, uint32_t index) {
    if (format == YUV_FORMAT_BGRA8888 || format == YUV_FORMAT_RGBA8888) {
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
    int packed = frame->format == YUV_FORMAT_BGRA8888 || frame->format == YUV_FORMAT_RGBA8888;
    out.colorMatrix = packed ? YUV_COLOR_MATRIX_NONE : YUV_COLOR_MATRIX_BT601;
    out.colorRange = packed ? YUV_COLOR_RANGE_NONE : YUV_COLOR_RANGE_LIMITED;
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
    int packed = frame->format == YUV_FORMAT_BGRA8888 || frame->format == YUV_FORMAT_RGBA8888;
    out.colorMatrix = packed ? YUV_COLOR_MATRIX_NONE : YUV_COLOR_MATRIX_BT601;
    out.colorRange = packed ? YUV_COLOR_RANGE_NONE : YUV_COLOR_RANGE_LIMITED;
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

static YuvConvertOptionsV1 convert_options(void) {
    YuvConvertOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

/* A deterministic test image with saturated corners, so the clamp paths in
 * the U/V encoders are actually exercised rather than assumed. */
static void image_rgb(uint32_t x, uint32_t y, int *r, int *g, int *b) {
    if (x == 0 && y == 0) {
        *r = 255;
        *g = 0;
        *b = 0;
        return;
    }
    if (x == 1 && y == 0) {
        *r = 0;
        *g = 0;
        *b = 255;
        return;
    }
    *r = (int)((37 * x + 11 * y) % 256);
    *g = (int)((17 * x + 53 * y) % 256);
    *b = (int)((71 * x + 29 * y) % 256);
}

static void fill_packed(Frame *frame, int bgra) {
    for (uint32_t y = 0; y < frame->height; y++) {
        for (uint32_t x = 0; x < frame->width; x++) {
            int r = 0;
            int g = 0;
            int b = 0;
            image_rgb(x, y, &r, &g, &b);
            uint8_t *sample = frame_sample(frame, 0, x, y);
            if (bgra) {
                sample[0] = (uint8_t)b;
                sample[1] = (uint8_t)g;
                sample[2] = (uint8_t)r;
            } else {
                sample[0] = (uint8_t)r;
                sample[1] = (uint8_t)g;
                sample[2] = (uint8_t)b;
            }
            sample[3] = (uint8_t)(200 + ((x + y) % 40));
        }
    }
}

/* ============================================================================
 * RGBA/BGRA parity
 * ============================================================================ */

static void test_channel_order_parity(void) {
    printf("RGBA and BGRA inputs agree\n");

    const uint32_t widths[3] = {4, 5, 1};
    const uint32_t heights[3] = {4, 3, 1};
    const uint32_t targets[2] = {YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *targetNames[2] = {"I420", "NV12"};

    for (uint32_t t = 0; t < 2; t++) {
        for (uint32_t g = 0; g < 3; g++) {
            Frame rgba;
            Frame bgra;
            Frame fromRgba;
            Frame fromBgra;
            frame_init(&rgba, YUV_FORMAT_RGBA8888, widths[g], heights[g]);
            frame_init(&bgra, YUV_FORMAT_BGRA8888, widths[g], heights[g]);
            fill_packed(&rgba, 0);
            fill_packed(&bgra, 1);
            frame_init(&fromRgba, targets[t], widths[g], heights[g]);
            frame_init(&fromBgra, targets[t], widths[g], heights[g]);

            YuvConstFrameV1 rgbaSource = as_source(&rgba);
            YuvConstFrameV1 bgraSource = as_source(&bgra);
            YuvMutableFrameV1 rgbaDestination = as_destination(&fromRgba);
            YuvMutableFrameV1 bgraDestination = as_destination(&fromBgra);
            YuvConvertOptionsV1 options = convert_options();

            char label[96];
            snprintf(label, sizeof(label), "RGBA->%s %ux%u", targetNames[t], widths[g], heights[g]);
            expect_status(label, yuv_convert_v1(&rgbaSource, &rgbaDestination, &options), YUV_STATUS_OK);
            snprintf(label, sizeof(label), "BGRA->%s %ux%u", targetNames[t], widths[g], heights[g]);
            expect_status(label, yuv_convert_v1(&bgraSource, &bgraDestination, &options), YUV_STATUS_OK);

            int identical = 1;
            for (uint32_t index = 0; index < fromRgba.planeCount && identical; index++) {
                uint32_t pw = plane_width(targets[t], index, widths[g]);
                uint32_t ph = plane_height(targets[t], index, heights[g]);
                for (uint32_t y = 0; y < ph && identical; y++) {
                    for (uint32_t x = 0; x < pw && identical; x++) {
                        uint8_t *a = frame_sample(&fromRgba, index, x, y);
                        uint8_t *b = frame_sample(&fromBgra, index, x, y);
                        if (memcmp(a, b, fromRgba.sampleBytes[index]) != 0) {
                            printf("  FAIL  plane %u sample (%u,%u): RGBA gave %u, BGRA gave %u\n", index, x,
                                y, a[0], b[0]);
                            identical = 0;
                        }
                    }
                }
            }
            expect_true("      identical output from both channel orders", identical);
        }
    }
}

/* ============================================================================
 * Absolute values against the oracle
 * ============================================================================ */

static void test_against_oracle(void) {
    printf("Packed to 4:2:0 matches the reference oracle\n");

    const uint32_t widths[2] = {4, 5};
    const uint32_t heights[2] = {4, 3};

    for (uint32_t g = 0; g < 2; g++) {
        uint32_t width = widths[g];
        uint32_t height = heights[g];
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_RGBA8888, width, height);
        fill_packed(&source, 0);
        frame_init(&destination, YUV_FORMAT_I420, width, height);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvConvertOptionsV1 options = convert_options();

        char label[96];
        snprintf(label, sizeof(label), "RGBA->I420 %ux%u", width, height);
        expect_status(label, yuv_convert_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int lumaOk = 1;
        for (uint32_t y = 0; y < height && lumaOk; y++) {
            for (uint32_t x = 0; x < width && lumaOk; x++) {
                int r = 0;
                int gg = 0;
                int b = 0;
                image_rgb(x, y, &r, &gg, &b);
                int expected = oracle_luma(r, gg, b);
                int actual = *frame_sample(&destination, 0, x, y);
                if (expected != actual) {
                    printf("  FAIL  Y (%u,%u) expected %d got %d\n", x, y, expected, actual);
                    lumaOk = 0;
                }
            }
        }
        expect_true("      luma matches the oracle", lumaOk);

        /* Chroma: average the RGB of the clipped 2x2 footprint, then encode
         * once. On an odd edge the divisor is the real sample count, which is
         * the rule the old top-left-pixel kernel got wrong. */
        int chromaOk = 1;
        uint32_t cw = (width + 1) / 2;
        uint32_t ch = (height + 1) / 2;
        for (uint32_t by = 0; by < ch && chromaOk; by++) {
            for (uint32_t bx = 0; bx < cw && chromaOk; bx++) {
                int sumR = 0;
                int sumG = 0;
                int sumB = 0;
                int count = 0;
                for (uint32_t oy = 0; oy < 2; oy++) {
                    for (uint32_t ox = 0; ox < 2; ox++) {
                        uint32_t x = bx * 2 + ox;
                        uint32_t y = by * 2 + oy;
                        if (x >= width || y >= height) {
                            continue;
                        }
                        int r = 0;
                        int gg = 0;
                        int b = 0;
                        image_rgb(x, y, &r, &gg, &b);
                        sumR += r;
                        sumG += gg;
                        sumB += b;
                        count++;
                    }
                }
                int averageR = sumR / count;
                int averageG = sumG / count;
                int averageB = sumB / count;
                int expectedU = oracle_u(averageR, averageG, averageB);
                int expectedV = oracle_v(averageR, averageG, averageB);
                int actualU = *frame_sample(&destination, 1, bx, by);
                int actualV = *frame_sample(&destination, 2, bx, by);
                if (expectedU != actualU || expectedV != actualV) {
                    printf("  FAIL  chroma block (%u,%u) expected U=%d V=%d got U=%d V=%d (count=%d)\n", bx,
                        by, expectedU, expectedV, actualU, actualV, count);
                    chromaOk = 0;
                }
            }
        }
        expect_true("      chroma matches the clipped 2x2 oracle", chromaOk);
        expect_true("      destination padding intact", padding_intact(&destination));
        expect_true("      source padding intact", padding_intact(&source));
    }
}

/* ============================================================================
 * Same-format deep copy
 * ============================================================================ */

static void test_same_format_deep_copy(void) {
    printf("Same-format conversion is an exact deep copy\n");

    const uint32_t formats[3] = {YUV_FORMAT_I420, YUV_FORMAT_NV12, YUV_FORMAT_BGRA8888};
    const char *names[3] = {"I420", "NV12", "BGRA"};

    for (uint32_t f = 0; f < 3; f++) {
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
                        sample[byte] = (uint8_t)(13 * index + 29 * y + 5 * x + byte + 1);
                    }
                }
            }
        }
        /* A different destination row stride, so a copy that assumed one
         * tight layout for both sides would be caught. */
        frame_init(&destination, formats[f], 5, 3);
        for (uint32_t index = 0; index < destination.planeCount; index++) {
            destination.rowStride[index] += 3;
            destination.length[index] = destination.rowStride[index] *
                plane_height(formats[f], index, 3);
            memset(destination.planes[index], CANARY, (size_t)destination.length[index]);
        }

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvConvertOptionsV1 options = convert_options();

        char label[96];
        snprintf(label, sizeof(label), "%s->%s deep copy 5x3", names[f], names[f]);
        expect_status(label, yuv_convert_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

        int exact = 1;
        for (uint32_t index = 0; index < source.planeCount && exact; index++) {
            uint32_t pw = plane_width(formats[f], index, 5);
            uint32_t ph = plane_height(formats[f], index, 3);
            for (uint32_t y = 0; y < ph && exact; y++) {
                for (uint32_t x = 0; x < pw && exact; x++) {
                    uint8_t *a = frame_sample(&source, index, x, y);
                    uint8_t *b = frame_sample(&destination, index, x, y);
                    if (memcmp(a, b, source.sampleBytes[index]) != 0) {
                        printf("  FAIL  plane %u sample (%u,%u) expected %u got %u\n", index, x, y, a[0],
                            b[0]);
                        exact = 0;
                    }
                }
            }
        }
        expect_true("      byte-exact, not re-encoded", exact);
        expect_true("      destination padding intact", padding_intact(&destination));
    }
}

/* ============================================================================
 * YUV to packed
 * ============================================================================ */

static void test_yuv_to_bgra(void) {
    printf("4:2:0 to BGRA\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_I420, 4, 4);
    for (uint32_t y = 0; y < 4; y++) {
        for (uint32_t x = 0; x < 4; x++) {
            *frame_sample(&source, 0, x, y) = (uint8_t)(16 + 20 * (x + y));
        }
    }
    for (uint32_t y = 0; y < 2; y++) {
        for (uint32_t x = 0; x < 2; x++) {
            *frame_sample(&source, 1, x, y) = (uint8_t)(90 + 10 * x);
            *frame_sample(&source, 2, x, y) = (uint8_t)(150 - 10 * y);
        }
    }
    frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvConvertOptionsV1 options = convert_options();
    expect_status("I420->BGRA 4x4", yuv_convert_v1(&sourceFrame, &destinationFrame, &options),
        YUV_STATUS_OK);

    int ok = 1;
    int alphaOk = 1;
    for (uint32_t y = 0; y < 4 && ok; y++) {
        for (uint32_t x = 0; x < 4 && ok; x++) {
            int c = *frame_sample(&source, 0, x, y) - 16;
            int d = *frame_sample(&source, 1, x / 2, y / 2) - 128;
            int e = *frame_sample(&source, 2, x / 2, y / 2) - 128;
            int expectedR = clip((298 * c + 409 * e + 128) >> 8);
            int expectedG = clip((298 * c - 100 * d - 208 * e + 128) >> 8);
            int expectedB = clip((298 * c + 516 * d + 128) >> 8);
            uint8_t *sample = frame_sample(&destination, 0, x, y);
            if (sample[0] != expectedB || sample[1] != expectedG || sample[2] != expectedR) {
                printf("  FAIL  BGRA (%u,%u) expected B=%d G=%d R=%d got B=%u G=%u R=%u\n", x, y, expectedB,
                    expectedG, expectedR, sample[0], sample[1], sample[2]);
                ok = 0;
            }
            if (sample[3] != 255) {
                alphaOk = 0;
            }
        }
    }
    expect_true("      matches the BT.601 decode oracle", ok);
    expect_true("      alpha is opaque", alphaOk);
    expect_true("      destination padding intact", padding_intact(&destination));
}

/* ============================================================================
 * Rejected pairs
 * ============================================================================ */

static void test_rejected_pairs(void) {
    printf("Unsupported pairs are rejected\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_BGRA8888, 4, 4);
    frame_init(&destination, YUV_FORMAT_RGBA8888, 4, 4);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvConvertOptionsV1 options = convert_options();
    /* RGBA is a source-only format in 0.3.0. */
    expect_status("RGBA as a destination is unsupported",
        yuv_convert_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_UNSUPPORTED_FORMAT);
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 conversion tests (YUV-32)\n");
    printf("=============================================================\n");

    test_channel_order_parity();
    test_against_oracle();
    test_same_format_deep_copy();
    test_yuv_to_bgra();
    test_rejected_pairs();

    printf("-------------------------------------------------------------\n");
    printf("checks: %d, failures: %d\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
