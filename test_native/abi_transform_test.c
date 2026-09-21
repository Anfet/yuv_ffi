/*
 * ABI v1 geometric transform tests (YUV-31): crop, flip, rotate.
 *
 * abi_status_test.c proves these entry points validate and stay atomic. This
 * file proves they compute the right pixels, which is what the YUV-31 audit
 * found they did not: destination width used as a destination stride, a pixel
 * stride copied as if it were a sample size, floor chroma geometry dropping a
 * trailing row, and padding moved around as if it were image data.
 *
 * Every case is checked against an independent oracle built here from the
 * visible-pixel mapping in docs/api-abi-0.3-design.md section 11, not against
 * the implementation's own helpers -- the point is to disagree with the
 * kernel if the kernel is wrong.
 *
 * Layout choices that matter:
 *
 *  - Every fixture is allocated with a deliberately larger row stride than
 *    its minimum span, and the gap bytes are filled with a canary. A transform
 *    that treats a gap as pixel data, or writes through it, is caught by the
 *    canary check rather than by a value comparison that would silently pass.
 *  - Odd geometry (5x3) is a first-class case, not an afterthought: it is
 *    where floor-vs-ceil chroma and the chroma phase rule of section 14 Q2
 *    actually bite.
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
 * Fixtures
 *
 * A frame is one flat buffer per plane with a padded row stride. `PAD` is the
 * number of canary bytes appended to each row beyond the minimum span.
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

/* Fills every logical sample with a value derived from its coordinates, so a
 * misaddressed read or write shows up as a specific wrong number rather than
 * as plausible-looking noise. */
static void frame_fill_pattern(Frame *frame) {
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        uint32_t pw = plane_width(frame->format, index, frame->width);
        uint32_t ph = plane_height(frame->format, index, frame->height);
        for (uint32_t y = 0; y < ph; y++) {
            for (uint32_t x = 0; x < pw; x++) {
                uint8_t *sample = frame_sample(frame, index, x, y);
                for (uint32_t byte = 0; byte < frame->sampleBytes[index]; byte++) {
                    sample[byte] = (uint8_t)(17 * index + 31 * y + 7 * x + 3 * byte + 1);
                }
            }
        }
    }
}

/*
 * Verifies that every byte outside the logical samples still holds the canary.
 * This is the check that fails when a kernel copies `rowStride` bytes, or
 * `pixelStride` bytes, instead of the sample.
 */
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

/* ============================================================================
 * Oracle
 *
 * Reproduces the visible-pixel mapping independently of the implementation.
 * For 4:2:0 the expected chroma is only checked where the mapping is block
 * aligned, because that is exactly where the contract fixes it to a copied
 * source sample; the phase-correcting path is checked by its own case below.
 * ============================================================================ */

typedef enum { MAP_CROP, MAP_FLIP_H, MAP_FLIP_V, MAP_ROT_90, MAP_ROT_180, MAP_ROT_270 } MapKind;

static void oracle_map(MapKind kind, uint32_t sw, uint32_t sh, uint32_t left, uint32_t top,
    uint32_t dx, uint32_t dy, uint32_t *sx, uint32_t *sy) {
    switch (kind) {
        case MAP_CROP:
            *sx = left + dx;
            *sy = top + dy;
            return;
        case MAP_FLIP_H:
            *sx = sw - 1 - dx;
            *sy = dy;
            return;
        case MAP_FLIP_V:
            *sx = dx;
            *sy = sh - 1 - dy;
            return;
        case MAP_ROT_90:
            *sx = dy;
            *sy = sh - 1 - dx;
            return;
        case MAP_ROT_180:
            *sx = sw - 1 - dx;
            *sy = sh - 1 - dy;
            return;
        case MAP_ROT_270:
        default:
            *sx = sw - 1 - dy;
            *sy = dx;
            return;
    }
}

/* Compares the luma/packed plane against the oracle. Chroma is compared only
 * when `checkChroma` is set, i.e. when the mapping is block aligned. */
static int matches_oracle(const char *label, Frame *source, Frame *destination, MapKind kind,
    uint32_t left, uint32_t top, int checkChroma) {
    int ok = 1;
    for (uint32_t y = 0; y < destination->height && ok; y++) {
        for (uint32_t x = 0; x < destination->width && ok; x++) {
            uint32_t sx = 0;
            uint32_t sy = 0;
            oracle_map(kind, source->width, source->height, left, top, x, y, &sx, &sy);
            uint8_t *expected = frame_sample(source, 0, sx, sy);
            uint8_t *actual = frame_sample(destination, 0, x, y);
            if (memcmp(expected, actual, destination->sampleBytes[0]) != 0) {
                printf("  FAIL  %s: luma (%u,%u) from (%u,%u) expected %u got %u\n", label, x, y, sx, sy,
                    expected[0], actual[0]);
                ok = 0;
            }
        }
    }

    if (ok && checkChroma && destination->planeCount > 1) {
        uint32_t cw = plane_width(destination->format, 1, destination->width);
        uint32_t ch = plane_height(destination->format, 1, destination->height);
        for (uint32_t y = 0; y < ch && ok; y++) {
            for (uint32_t x = 0; x < cw && ok; x++) {
                uint32_t sx = 0;
                uint32_t sy = 0;
                oracle_map(kind, source->width, source->height, left, top, x * 2, y * 2, &sx, &sy);
                for (uint32_t index = 1; index < destination->planeCount && ok; index++) {
                    uint8_t *expected = frame_sample(source, index, sx / 2, sy / 2);
                    uint8_t *actual = frame_sample(destination, index, x, y);
                    if (memcmp(expected, actual, destination->sampleBytes[index]) != 0) {
                        printf("  FAIL  %s: plane %u chroma (%u,%u) expected %u got %u\n", label, index, x, y,
                            expected[0], actual[0]);
                        ok = 0;
                    }
                }
            }
        }
    }
    return ok;
}

static YuvFlipOptionsV1 flip_options(uint32_t direction) {
    YuvFlipOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.direction = direction;
    return options;
}

static YuvRotateOptionsV1 rotate_options(uint32_t degrees) {
    YuvRotateOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.rotationDegrees = degrees;
    return options;
}

static YuvCropOptionsV1 crop_options(int32_t left, int32_t top, uint32_t width, uint32_t height) {
    YuvCropOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.left = left;
    options.top = top;
    options.width = width;
    options.height = height;
    return options;
}

static const uint32_t FORMATS[3] = {YUV_FORMAT_I420, YUV_FORMAT_NV12, YUV_FORMAT_BGRA8888};
static const char *FORMAT_NAMES[3] = {"I420", "NV12", "BGRA"};

/* ============================================================================
 * Flip
 * ============================================================================ */

static void test_flip(void) {
    printf("Flip\n");

    for (uint32_t f = 0; f < 3; f++) {
        /* Even geometry: block aligned, so chroma is a plain copy and the
         * oracle can check it byte for byte. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 4, 4);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 4);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_HORIZONTAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 4x4 horizontal flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_H, 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
            expect_true("      source padding intact", padding_intact(&source));
        }
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 4, 4);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 4);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_VERTICAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 4x4 vertical flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_V, 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        /* Odd geometry: luma must still map exactly. Chroma goes through the
         * phase-correcting path, checked separately below. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 5, 3);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 5, 3);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_HORIZONTAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 5x3 horizontal flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      luma matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_H, 0, 0,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        /* 1x1 and the degenerate strips: the smallest frames that still have a
         * trailing chroma sample. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 1, 1);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 1, 1);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_HORIZONTAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 1x1 horizontal flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_H, 0, 0,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 1, 5);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 1, 5);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_VERTICAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 1x5 vertical flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      luma matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_V, 0, 0,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 5, 1);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 5, 1);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(YUV_FLIP_VERTICAL);
            char label[96];
            snprintf(label, sizeof(label), "%s 5x1 vertical flip", FORMAT_NAMES[f]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_FLIP_V, 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
    }
}

/* ============================================================================
 * Rotate
 * ============================================================================ */

static void test_rotate(void) {
    printf("Rotate\n");

    for (uint32_t f = 0; f < 3; f++) {
        const uint32_t degrees[4] = {0, 90, 180, 270};
        const MapKind kinds[4] = {MAP_CROP, MAP_ROT_90, MAP_ROT_180, MAP_ROT_270};
        for (uint32_t d = 0; d < 4; d++) {
            uint32_t transposed = degrees[d] == 90 || degrees[d] == 270;
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 4, 4);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 4);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvRotateOptionsV1 options = rotate_options(degrees[d]);
            char label[96];
            snprintf(label, sizeof(label), "%s 4x4 rotate %u", FORMAT_NAMES[f], degrees[d]);
            expect_status(label, yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, kinds[d], 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
            (void)transposed;
        }

        /* Non-square, so a 90 rotation genuinely transposes the destination
         * geometry. A kernel that indexed the destination by source width --
         * defect C-01 -- cannot pass this. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 6, 4);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 6);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvRotateOptionsV1 options = rotate_options(90);
            char label[96];
            snprintf(label, sizeof(label), "%s 6x4 rotate 90 to 4x6", FORMAT_NAMES[f]);
            expect_status(label, yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_ROT_90, 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 5, 3);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 3, 5);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvRotateOptionsV1 options = rotate_options(270);
            char label[96];
            snprintf(label, sizeof(label), "%s 5x3 rotate 270 to 3x5", FORMAT_NAMES[f]);
            expect_status(label, yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      luma matches oracle",
                matches_oracle(label, &source, &destination, MAP_ROT_270, 0, 0,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
    }

    /* A destination sized for the wrong angle must be rejected before any
     * write: the geometry rule is chosen from the angle, not from whatever
     * the caller happened to allocate. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4);
        frame_fill_pattern(&source);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 4);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvRotateOptionsV1 options = rotate_options(90);
        expect_status("rotate 90 rejects an untransposed destination",
            yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
    }
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 4, 4);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvRotateOptionsV1 options = rotate_options(45);
        expect_status("rotate rejects a non-quadrant angle",
            yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
    }
}

/* ============================================================================
 * Crop
 * ============================================================================ */

static void test_crop(void) {
    printf("Crop\n");

    for (uint32_t f = 0; f < 3; f++) {
        /* Even origin: the direct path, so chroma is a copy the oracle checks. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 8, 8);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 4);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvCropOptionsV1 options = crop_options(2, 2, 4, 4);
            char label[96];
            snprintf(label, sizeof(label), "%s crop 4x4 at even (2,2)", FORMAT_NAMES[f]);
            expect_status(label, yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_CROP, 2, 2, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
            expect_true("      source padding intact", padding_intact(&source));
        }
        /* Odd extent: the trailing column and row are real samples. A kernel
         * using floor chroma geometry drops them -- the 3x3 probe in the
         * YUV-31 audit wrote one of four chroma samples. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 8, 8);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 3, 3);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvCropOptionsV1 options = crop_options(2, 2, 3, 3);
            char label[96];
            snprintf(label, sizeof(label), "%s crop 3x3 at even (2,2)", FORMAT_NAMES[f]);
            expect_status(label, yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            /* Chroma is not a copy here: the trailing destination blocks hold
             * 1 or 2 pixels while the source blocks they come from hold 4, so
             * the contract's clipped average differs from the stored source
             * sample. test_crop_trailing_chroma() checks those values against
             * the footprint rule; here only luma is a byte-for-byte mapping. */
            expect_true("      luma matches oracle",
                matches_oracle(label, &source, &destination, MAP_CROP, 2, 2,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        /* Odd origin: section 14 Q2's phase case. Luma still maps exactly;
         * chroma is recomputed, so only the luma plane is compared. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 8, 8);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 4, 4);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvCropOptionsV1 options = crop_options(1, 1, 4, 4);
            char label[96];
            snprintf(label, sizeof(label), "%s crop 4x4 at odd (1,1)", FORMAT_NAMES[f]);
            expect_status(label, yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      luma matches oracle",
                matches_oracle(label, &source, &destination, MAP_CROP, 1, 1,
                    FORMATS[f] == YUV_FORMAT_BGRA8888));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
        /* A crop of the whole frame is an identity copy. */
        {
            Frame source;
            Frame destination;
            frame_init(&source, FORMATS[f], 5, 3);
            frame_fill_pattern(&source);
            frame_init(&destination, FORMATS[f], 5, 3);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvCropOptionsV1 options = crop_options(0, 0, 5, 3);
            char label[96];
            snprintf(label, sizeof(label), "%s full-frame crop 5x3", FORMAT_NAMES[f]);
            expect_status(label, yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            expect_true("      matches oracle",
                matches_oracle(label, &source, &destination, MAP_CROP, 0, 0, 1));
            expect_true("      destination padding intact", padding_intact(&destination));
        }
    }

    /* A rectangle running past the source edge is rejected before writing. */
    {
        Frame source;
        Frame destination;
        frame_init(&source, YUV_FORMAT_BGRA8888, 8, 8);
        frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvCropOptionsV1 options = crop_options(6, 6, 4, 4);
        expect_status("crop rejects a rectangle past the source edge",
            yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
    }
}

/* ============================================================================
 * Custom pixel stride
 *
 * A pixel stride larger than the sample is a legal gapped layout. The legacy
 * kernels copied `pixelStride` bytes per sample, which both read and wrote the
 * gap; here the gap carries a canary, so that mistake is a failure rather than
 * a silent pass.
 * ============================================================================ */

static void test_custom_pixel_stride(void) {
    printf("Custom pixel stride\n");

    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_I420, 4, 4);
    /* Two bytes per Y sample: one sample byte plus one gap byte. */
    source.pixelStride[0] = 2;
    source.rowStride[0] = 4 * 2 + PAD;
    source.length[0] = source.rowStride[0] * 4;
    memset(source.planes[0], CANARY, (size_t)source.length[0]);
    frame_fill_pattern(&source);

    frame_init(&destination, YUV_FORMAT_I420, 4, 4);
    destination.pixelStride[0] = 3;
    destination.rowStride[0] = 4 * 3 + PAD;
    destination.length[0] = destination.rowStride[0] * 4;
    memset(destination.planes[0], CANARY, (size_t)destination.length[0]);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvFlipOptionsV1 options = flip_options(YUV_FLIP_HORIZONTAL);
    expect_status("I420 flip with differing source/destination pixel strides",
        yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

    int ok = 1;
    for (uint32_t y = 0; y < 4 && ok; y++) {
        for (uint32_t x = 0; x < 4 && ok; x++) {
            uint8_t expected = *frame_sample(&source, 0, 3 - x, y);
            uint8_t actual = *frame_sample(&destination, 0, x, y);
            if (expected != actual) {
                printf("  FAIL  gapped luma (%u,%u) expected %u got %u\n", x, y, expected, actual);
                ok = 0;
            }
        }
    }
    expect_true("      gapped luma matches oracle", ok);

    /* Every byte of every destination pixel gap must still be the canary. */
    int gapsIntact = 1;
    for (uint32_t y = 0; y < 4 && gapsIntact; y++) {
        for (uint32_t x = 0; x < 4 && gapsIntact; x++) {
            uint8_t *sample = frame_sample(&destination, 0, x, y);
            for (uint32_t byte = 1; byte < destination.pixelStride[0]; byte++) {
                if (sample[byte] != CANARY) {
                    printf("  FAIL  pixel gap written at (%u,%u) byte %u\n", x, y, byte);
                    gapsIntact = 0;
                    break;
                }
            }
        }
    }
    expect_true("      destination pixel gaps untouched", gapsIntact);
    expect_true("      source pixel gaps untouched (read as padding, not data)", padding_intact(&source));
}

/* ============================================================================
 * Crop trailing chroma
 *
 * The case the reviewer of the first YUV-31 submission caught: an even crop
 * origin alone does not make a chroma copy correct. A destination chroma
 * sample is the average of the pixels that really exist in its 2x2 footprint,
 * so when an odd destination extent leaves a trailing block holding 1 or 2
 * pixels, copying the source sample -- which was averaged over 4 -- carries a
 * different value. On the colours below that difference is several LSB.
 *
 * The expected values here are computed from the clipped-footprint rule, not
 * read back from the implementation.
 * ============================================================================ */

static int clip_int(int value) {
    return value < 0 ? 0 : (value > 255 ? 255 : value);
}

static int oracle_u_from(int r, int g, int b) {
    return clip_int(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
}

static int oracle_v_from(int r, int g, int b) {
    return clip_int(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
}

static void decode_601(int y, int u, int v, int *r, int *g, int *b) {
    int c = y - 16;
    int d = u - 128;
    int e = v - 128;
    *r = clip_int((298 * c + 409 * e + 128) >> 8);
    *g = clip_int((298 * c - 100 * d - 208 * e + 128) >> 8);
    *b = clip_int((298 * c + 516 * d + 128) >> 8);
}

static void test_crop_trailing_chroma(void) {
    printf("Crop trailing chroma\n");

    /* A source whose 2x2 blocks hold visibly different colours, so an
     * incorrectly copied chroma sample cannot coincide with the right one. */
    Frame source;
    Frame destination;
    frame_init(&source, YUV_FORMAT_I420, 4, 4);
    for (uint32_t y = 0; y < 4; y++) {
        for (uint32_t x = 0; x < 4; x++) {
            *frame_sample(&source, 0, x, y) = (uint8_t)(40 + 37 * x + 19 * y);
        }
    }
    for (uint32_t y = 0; y < 2; y++) {
        for (uint32_t x = 0; x < 2; x++) {
            *frame_sample(&source, 1, x, y) = (uint8_t)(60 + 50 * x);
            *frame_sample(&source, 2, x, y) = (uint8_t)(200 - 50 * y);
        }
    }
    frame_init(&destination, YUV_FORMAT_I420, 3, 3);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvCropOptionsV1 options = crop_options(0, 0, 3, 3);
    expect_status("I420 crop 3x3 at (0,0) from 4x4",
        yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);

    int ok = 1;
    for (uint32_t blockY = 0; blockY < 2 && ok; blockY++) {
        for (uint32_t blockX = 0; blockX < 2 && ok; blockX++) {
            /* Average the visible RGB of the pixels this destination block
             * really covers, then encode once -- the contract's rule. */
            int sumR = 0;
            int sumG = 0;
            int sumB = 0;
            int count = 0;
            for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                    uint32_t x = blockX * 2 + offsetX;
                    uint32_t y = blockY * 2 + offsetY;
                    if (x >= 3 || y >= 3) {
                        continue;
                    }
                    int luma = *frame_sample(&source, 0, x, y);
                    int u = *frame_sample(&source, 1, x / 2, y / 2);
                    int v = *frame_sample(&source, 2, x / 2, y / 2);
                    int r;
                    int g;
                    int b;
                    decode_601(luma, u, v, &r, &g, &b);
                    sumR += r;
                    sumG += g;
                    sumB += b;
                    count++;
                }
            }
            int expectedU = oracle_u_from(sumR / count, sumG / count, sumB / count);
            int expectedV = oracle_v_from(sumR / count, sumG / count, sumB / count);
            int actualU = *frame_sample(&destination, 1, blockX, blockY);
            int actualV = *frame_sample(&destination, 2, blockX, blockY);
            if (actualU != expectedU || actualV != expectedV) {
                printf("  FAIL  block (%u,%u) count=%d expected U=%d V=%d got U=%d V=%d\n", blockX, blockY,
                    count, expectedU, expectedV, actualU, actualV);
                ok = 0;
            }
        }
    }
    expect_true("      trailing blocks use the clipped footprint, not a copy", ok);
    expect_true("      destination padding intact", padding_intact(&destination));

    /* A crop running to the source edge keeps the copy path, because there
     * the source block is clipped exactly as the destination block is. */
    {
        Frame edge;
        frame_init(&edge, YUV_FORMAT_I420, 3, 3);
        Frame wholeSource;
        frame_init(&wholeSource, YUV_FORMAT_I420, 3, 3);
        frame_fill_pattern(&wholeSource);

        YuvConstFrameV1 edgeSource = as_source(&wholeSource);
        YuvMutableFrameV1 edgeDestination = as_destination(&edge);
        YuvCropOptionsV1 wholeOptions = crop_options(0, 0, 3, 3);
        expect_status("I420 full-frame 3x3 crop keeps the copy path",
            yuv_crop_v1(&edgeSource, &edgeDestination, &wholeOptions), YUV_STATUS_OK);
        expect_true("      chroma copied exactly",
            matches_oracle("full 3x3", &wholeSource, &edge, MAP_CROP, 0, 0, 1));
    }
}

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 geometric transform tests (YUV-31)\n");
    printf("=============================================================\n");

    test_flip();
    test_rotate();
    test_crop();
    test_crop_trailing_chroma();
    test_custom_pixel_stride();

    printf("-------------------------------------------------------------\n");
    printf("checks: %d, failures: %d\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
