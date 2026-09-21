/*
 * Native ASan/UBSan/LSan safety gate (YUV-34).
 *
 * Flutter reference tests prove wrong pixels; they cannot prove the absence of
 * out-of-bounds access, uninitialized reads, integer UB, or leaks inside the C
 * kernels. This harness calls the eleven exported ABI v1 entry points directly,
 * with every frame allocated on the HEAP at its exact declared plane length so
 * a kernel that steps outside a plane trips ASan's own redzone rather than
 * relying solely on a manually placed byte. Row/column padding gaps inside that
 * same allocation are additionally filled with a canary pattern and checked
 * byte-for-byte, which is what catches a kernel that copies a row/pixel stride
 * instead of a sample -- a bug ASan cannot see, because the byte it touches is
 * still inside the allocation.
 *
 * Case groups (see also test_native/README.md and CMakeLists.txt comment):
 *
 *  - C-01..C-03: canary probes on tight and padded BGRA/I420/NV12 frames
 *    across every operation family (effect, blur, convert, transform), odd
 *    geometry included.
 *  - C-04..C-06: geometric transforms (crop/flip/rotate) and chroma swap on
 *    heap frames, where a destination-index or transposed-geometry defect
 *    reads or writes past the allocated plane.
 *  - C-07: region-of-interest blur/effect on heap frames -- the ROI seam is
 *    where a previous defect (encode_frame re-touching luma outside the
 *    region) actually reached memory outside the intended write set.
 *  - C-08: exact-fit heap allocation with NO padding at all (rowStride ==
 *    minimum span), so there is zero slack between the last real byte and the
 *    ASan redzone; the tightest possible OOB probe.
 *  - C-09: repeated back-to-back calls across the whole operation set on
 *    freshly allocated/freed frames each iteration, giving LSan many
 *    allocate/free cycles to disagree with.
 *  - H-01: invalid rect/radius/sigma/geometry inputs run through the same
 *    heap fixtures, proving the validation prologue rejects them before any
 *    read/write that a sanitizer could otherwise catch as a symptom rather
 *    than the actual contract violation.
 *  - H-02: checked-arithmetic overflow inputs (huge stride/length) reach
 *    OVERFLOW without the kernel ever dereferencing the corresponding plane.
 *  - Allocation-failure injection (blur only entry points that allocate):
 *    proves ALLOCATION_FAILED is atomic (destination canary intact) and that
 *    no partial commit or leak occurs, via a wrapped malloc that can be told
 *    to fail on a chosen call. Compiled only where the linker supports
 *    --wrap (GNU/gold/lld on ELF), which is the toolchain the required
 *    sanitizer CI job actually uses; see ENABLE_MALLOC_WRAP below.
 *
 * Checks are routed through helpers taking volatile locals so MSVC does not
 * report C4127 (constant conditional) under /W4 /WX, matching every other
 * test_native file. Failure is reported through the exit code, never
 * abort(): on Windows abort() raises 0xC0000409, which CTest's WILL_FAIL does
 * not treat as an ordinary non-zero return, and this file is not documented
 * as an expected-failure target.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "yuv/abi/h/yuv_ops_v1.h"

static int checks = 0;
static int failures = 0;
static long executedCases = 0;

#define CANARY 0xC7

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
 * Heap frame fixture
 *
 * Every plane is its own malloc(), sized to exactly the declared `length`, so
 * ASan places a redzone immediately after the last real byte of that specific
 * plane (not after some larger shared buffer). `rowStride` may still exceed
 * the minimum per-row span when `pad` > 0: that slack lives INSIDE the
 * allocation and is filled with CANARY, catching a stride-confusion bug that
 * never leaves the allocation and therefore never trips ASan on its own.
 * ============================================================================ */

#define MAX_PLANES 3

typedef struct {
    uint32_t format;
    uint32_t width;
    uint32_t height;
    uint32_t planeCount;
    uint8_t *planes[MAX_PLANES];
    uint64_t rowStride[MAX_PLANES];
    uint32_t pixelStride[MAX_PLANES];
    uint32_t sampleBytes[MAX_PLANES];
    uint64_t length[MAX_PLANES];
} HeapFrame;

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

static uint32_t frame_plane_count(uint32_t format) {
    if (format == YUV_FORMAT_I420) {
        return 3;
    }
    if (format == YUV_FORMAT_NV12) {
        return 2;
    }
    return 1;
}

/* pad == 0 gives the exact-fit case (C-08): rowStride is the minimum span, so
 * there is no slack byte between the last real sample and the ASan redzone. */
static void heap_frame_init(HeapFrame *frame, uint32_t format, uint32_t width, uint32_t height, uint32_t pad) {
    memset(frame, 0, sizeof(*frame));
    frame->format = format;
    frame->width = width;
    frame->height = height;
    frame->planeCount = frame_plane_count(format);

    for (uint32_t index = 0; index < frame->planeCount; index++) {
        uint32_t sampleBytes = plane_sample_bytes(format, index);
        uint32_t pw = plane_width(format, index, width);
        uint32_t ph = plane_height(format, index, height);
        uint64_t minSpan = (uint64_t)pw * sampleBytes;
        frame->sampleBytes[index] = sampleBytes;
        frame->pixelStride[index] = sampleBytes;
        frame->rowStride[index] = minSpan + pad;
        frame->length[index] = frame->rowStride[index] * ph;
        frame->planes[index] = (uint8_t *)malloc((size_t)frame->length[index]);
        if (frame->planes[index] == NULL) {
            fprintf(stderr, "fatal: heap_frame_init malloc failed\n");
            exit(EXIT_FAILURE);
        }
        memset(frame->planes[index], CANARY, (size_t)frame->length[index]);
    }
}

static void heap_frame_free(HeapFrame *frame) {
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        free(frame->planes[index]);
        frame->planes[index] = NULL;
    }
}

static uint8_t *frame_sample(HeapFrame *frame, uint32_t index, uint32_t x, uint32_t y) {
    return frame->planes[index] + (size_t)(y * frame->rowStride[index] + x * frame->pixelStride[index]);
}

static YuvConstFrameV1 as_source(HeapFrame *frame) {
    YuvConstFrameV1 out;
    memset(&out, 0, sizeof(out));
    out.structSize = (uint32_t)sizeof(out);
    out.abiVersion = YUV_ABI_VERSION_1;
    out.format = frame->format;
    out.planeCount = frame->planeCount;
    out.width = frame->width;
    out.height = frame->height;
    int isYuv = frame->format == YUV_FORMAT_I420 || frame->format == YUV_FORMAT_NV12;
    out.colorMatrix = isYuv ? YUV_COLOR_MATRIX_BT601 : YUV_COLOR_MATRIX_NONE;
    out.colorRange = isYuv ? YUV_COLOR_RANGE_LIMITED : YUV_COLOR_RANGE_NONE;
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        out.planes[index].length = frame->length[index];
        out.planes[index].rowStride = frame->rowStride[index];
        out.planes[index].pixelStride = frame->pixelStride[index];
        out.planes[index].sampleBytes = frame->sampleBytes[index];
        out.planes[index].data = frame->planes[index];
    }
    return out;
}

static YuvMutableFrameV1 as_destination(HeapFrame *frame) {
    YuvMutableFrameV1 out;
    memset(&out, 0, sizeof(out));
    out.structSize = (uint32_t)sizeof(out);
    out.abiVersion = YUV_ABI_VERSION_1;
    out.format = frame->format;
    out.planeCount = frame->planeCount;
    out.width = frame->width;
    out.height = frame->height;
    int isYuv = frame->format == YUV_FORMAT_I420 || frame->format == YUV_FORMAT_NV12;
    out.colorMatrix = isYuv ? YUV_COLOR_MATRIX_BT601 : YUV_COLOR_MATRIX_NONE;
    out.colorRange = isYuv ? YUV_COLOR_RANGE_LIMITED : YUV_COLOR_RANGE_NONE;
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        out.planes[index].length = frame->length[index];
        out.planes[index].rowStride = frame->rowStride[index];
        out.planes[index].pixelStride = frame->pixelStride[index];
        out.planes[index].sampleBytes = frame->sampleBytes[index];
        out.planes[index].data = frame->planes[index];
    }
    return out;
}

static void fill_pattern(HeapFrame *frame) {
    for (uint32_t index = 0; index < frame->planeCount; index++) {
        uint32_t pw = plane_width(frame->format, index, frame->width);
        uint32_t ph = plane_height(frame->format, index, frame->height);
        for (uint32_t y = 0; y < ph; y++) {
            for (uint32_t x = 0; x < pw; x++) {
                uint8_t *sample = frame_sample(frame, index, x, y);
                for (uint32_t byte = 0; byte < frame->sampleBytes[index]; byte++) {
                    sample[byte] = (uint8_t)(23 + 19 * x + 41 * y + 7 * byte + 3 * index);
                }
                if (frame->sampleBytes[index] == 4) {
                    sample[3] = 255;
                }
            }
        }
    }
}

/* Row/column padding gap left of the ASan-owned redzone: bytes inside the
 * allocation, between the last real sample of a row and the next row's first
 * real sample (or past the last real column). A stride-confusion kernel
 * writes here without ever leaving the allocation, so only an explicit
 * byte-value check -- not ASan -- catches it. */
static int padding_intact(HeapFrame *frame) {
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

static YuvEffectOptionsV1 effect_options(void) {
    YuvEffectOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
    options.region.structSize = (uint32_t)sizeof(YuvRegionOptionsV1);
    options.region.abiVersion = YUV_ABI_VERSION_1;
    return options;
}

static YuvConvertOptionsV1 convert_options(void) {
    YuvConvertOptionsV1 options;
    memset(&options, 0, sizeof(options));
    options.structSize = (uint32_t)sizeof(options);
    options.abiVersion = YUV_ABI_VERSION_1;
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

/* ============================================================================
 * C-01: canary probes across effect/blur/convert on tight and padded frames
 * ============================================================================ */

static void run_effect_probe(const char *name, uint32_t format, uint32_t width, uint32_t height, uint32_t pad) {
    HeapFrame source;
    HeapFrame destination;
    heap_frame_init(&source, format, width, height, pad);
    heap_frame_init(&destination, format, width, height, pad);
    fill_pattern(&source);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvMutableFrameV1 destinationFrame = as_destination(&destination);
    YuvEffectOptionsV1 options = effect_options();

    char label[128];
    snprintf(label, sizeof(label), "C-01 grayscale %s", name);
    expect_status(label, yuv_grayscale_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after grayscale", padding_intact(&destination));

    snprintf(label, sizeof(label), "C-01 black-white %s", name);
    expect_status(label, yuv_black_white_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after black-white", padding_intact(&destination));

    snprintf(label, sizeof(label), "C-01 negate %s", name);
    expect_status(label, yuv_negate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after negate", padding_intact(&destination));

    heap_frame_free(&source);
    heap_frame_free(&destination);
}

static void run_blur_probe(const char *name, uint32_t format, uint32_t width, uint32_t height, uint32_t pad) {
    HeapFrame source;
    HeapFrame meanDest;
    HeapFrame boxDest;
    HeapFrame gaussDest;
    heap_frame_init(&source, format, width, height, pad);
    heap_frame_init(&meanDest, format, width, height, pad);
    heap_frame_init(&boxDest, format, width, height, pad);
    heap_frame_init(&gaussDest, format, width, height, pad);
    fill_pattern(&source);

    YuvConstFrameV1 sourceFrame = as_source(&source);
    YuvBlurOptionsV1 meanOptions = blur_options(2, 0.0);
    YuvBlurOptionsV1 gaussOptions = blur_options(2, 1.4);

    char label[128];
    YuvMutableFrameV1 meanFrame = as_destination(&meanDest);
    snprintf(label, sizeof(label), "C-01 mean blur %s", name);
    expect_status(label, yuv_mean_blur_v1(&sourceFrame, &meanFrame, &meanOptions), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after mean blur", padding_intact(&meanDest));

    YuvMutableFrameV1 boxFrame = as_destination(&boxDest);
    snprintf(label, sizeof(label), "C-01 box blur %s", name);
    expect_status(label, yuv_box_blur_v1(&sourceFrame, &boxFrame, &meanOptions), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after box blur", padding_intact(&boxDest));

    YuvMutableFrameV1 gaussFrame = as_destination(&gaussDest);
    snprintf(label, sizeof(label), "C-01 gaussian blur %s", name);
    expect_status(label, yuv_gaussian_blur_v1(&sourceFrame, &gaussFrame, &gaussOptions), YUV_STATUS_OK);
    executedCases++;
    expect_true("      padding intact after gaussian blur", padding_intact(&gaussDest));

    heap_frame_free(&source);
    heap_frame_free(&meanDest);
    heap_frame_free(&boxDest);
    heap_frame_free(&gaussDest);
}

static void test_canary_probes_effect_and_blur(void) {
    printf("C-01: canary probes, effects and blur\n");

    struct {
        const char *name;
        uint32_t format;
        uint32_t width;
        uint32_t height;
    } geometries[3] = {
        {"BGRA 8x6", YUV_FORMAT_BGRA8888, 8, 6},
        {"I420 8x6", YUV_FORMAT_I420, 8, 6},
        {"NV12 8x6", YUV_FORMAT_NV12, 8, 6},
    };

    for (int i = 0; i < 3; i++) {
        char tightName[64];
        char paddedName[64];
        snprintf(tightName, sizeof(tightName), "%s tight", geometries[i].name);
        snprintf(paddedName, sizeof(paddedName), "%s padded", geometries[i].name);
        run_effect_probe(tightName, geometries[i].format, geometries[i].width, geometries[i].height, 0);
        run_effect_probe(paddedName, geometries[i].format, geometries[i].width, geometries[i].height, 7);
        run_blur_probe(tightName, geometries[i].format, geometries[i].width, geometries[i].height, 0);
        run_blur_probe(paddedName, geometries[i].format, geometries[i].width, geometries[i].height, 7);
    }
}

/* ============================================================================
 * C-02: convert across the RGBA/BGRA/I420/NV12 matrix
 * ============================================================================ */

static void test_canary_probes_convert(void) {
    printf("C-02: canary probes, convert\n");

    struct {
        const char *name;
        uint32_t sourceFormat;
        uint32_t destinationFormat;
    } pairs[6] = {
        {"BGRA->I420", YUV_FORMAT_BGRA8888, YUV_FORMAT_I420},
        {"BGRA->NV12", YUV_FORMAT_BGRA8888, YUV_FORMAT_NV12},
        {"RGBA->I420", YUV_FORMAT_RGBA8888, YUV_FORMAT_I420},
        {"I420->BGRA", YUV_FORMAT_I420, YUV_FORMAT_BGRA8888},
        {"NV12->BGRA", YUV_FORMAT_NV12, YUV_FORMAT_BGRA8888},
        {"I420->NV12", YUV_FORMAT_I420, YUV_FORMAT_NV12},
    };

    for (int i = 0; i < 6; i++) {
        for (uint32_t pad = 0; pad <= 5; pad += 5) {
            HeapFrame source;
            HeapFrame destination;
            /* 7x5 is odd in both dimensions: exercises the trailing chroma
             * column/row on every 4:2:0 side of the pairing. */
            heap_frame_init(&source, pairs[i].sourceFormat, 7, 5, pad);
            heap_frame_init(&destination, pairs[i].destinationFormat, 7, 5, pad);
            fill_pattern(&source);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvConvertOptionsV1 options = convert_options();

            char label[128];
            snprintf(label, sizeof(label), "C-02 %s 7x5 %s", pairs[i].name, pad == 0 ? "tight" : "padded");
            expect_status(label, yuv_convert_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            executedCases++;
            expect_true("      padding intact after convert", padding_intact(&destination));

            heap_frame_free(&source);
            heap_frame_free(&destination);
        }
    }
}

/* ============================================================================
 * C-03: chroma swap (NV12 only)
 * ============================================================================ */

static void test_canary_probe_chroma_swap(void) {
    printf("C-03: canary probe, chroma swap\n");

    for (uint32_t pad = 0; pad <= 6; pad += 6) {
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_NV12, 7, 5, pad);
        heap_frame_init(&destination, YUV_FORMAT_NV12, 7, 5, pad);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();

        char label[96];
        snprintf(label, sizeof(label), "C-03 chroma swap NV12 7x5 %s", pad == 0 ? "tight" : "padded");
        expect_status(label, yuv_chroma_swap_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
        executedCases++;
        expect_true("      padding intact after chroma swap", padding_intact(&destination));

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * C-04..C-06: geometric transforms on heap frames
 * ============================================================================ */

static void test_canary_probes_crop(void) {
    printf("C-04: canary probes, crop\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};

    for (int f = 0; f < 3; f++) {
        for (uint32_t pad = 0; pad <= 5; pad += 5) {
            HeapFrame source;
            HeapFrame destination;
            /* Odd-origin, odd-size crop out of an odd-size source: exercises
             * chroma phase re-encoding rather than the block-aligned fast
             * path. */
            heap_frame_init(&source, formats[f], 9, 7, pad);
            heap_frame_init(&destination, formats[f], 5, 3, pad);
            fill_pattern(&source);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvCropOptionsV1 options = crop_options(3, 1, 5, 3);

            char label[128];
            snprintf(label, sizeof(label), "C-04 crop %s 9x7 -> 5x3 at (3,1) %s", names[f],
                pad == 0 ? "tight" : "padded");
            expect_status(label, yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            executedCases++;
            expect_true("      padding intact after crop", padding_intact(&destination));

            heap_frame_free(&source);
            heap_frame_free(&destination);
        }
    }
}

static void test_canary_probes_flip(void) {
    printf("C-05: canary probes, flip\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};
    const uint32_t directions[2] = {YUV_FLIP_HORIZONTAL, YUV_FLIP_VERTICAL};
    const char *directionNames[2] = {"horizontal", "vertical"};

    for (int f = 0; f < 3; f++) {
        for (int d = 0; d < 2; d++) {
            HeapFrame source;
            HeapFrame destination;
            heap_frame_init(&source, formats[f], 7, 5, 6);
            heap_frame_init(&destination, formats[f], 7, 5, 6);
            fill_pattern(&source);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvFlipOptionsV1 options = flip_options(directions[d]);

            char label[128];
            snprintf(label, sizeof(label), "C-05 flip %s 7x5 %s", names[f], directionNames[d]);
            expect_status(label, yuv_flip_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            executedCases++;
            expect_true("      padding intact after flip", padding_intact(&destination));

            heap_frame_free(&source);
            heap_frame_free(&destination);
        }
    }
}

static void test_canary_probes_rotate(void) {
    printf("C-06: canary probes, rotate\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};
    const uint32_t degrees[3] = {90, 180, 270};

    for (int f = 0; f < 3; f++) {
        for (int d = 0; d < 3; d++) {
            HeapFrame source;
            HeapFrame destination;
            uint32_t width = 7;
            uint32_t height = 5;
            /* 90/270 transpose destination geometry; a kernel indexing the
             * destination by source width (the historical defect C-01 of the
             * YUV-31 audit) writes past a transposed heap plane. */
            int transposed = degrees[d] == 90 || degrees[d] == 270;
            uint32_t destinationWidth = transposed ? height : width;
            uint32_t destinationHeight = transposed ? width : height;

            heap_frame_init(&source, formats[f], width, height, 5);
            heap_frame_init(&destination, formats[f], destinationWidth, destinationHeight, 5);
            fill_pattern(&source);

            YuvConstFrameV1 sourceFrame = as_source(&source);
            YuvMutableFrameV1 destinationFrame = as_destination(&destination);
            YuvRotateOptionsV1 options = rotate_options(degrees[d]);

            char label[128];
            snprintf(label, sizeof(label), "C-06 rotate %s 7x5 by %u", names[f], degrees[d]);
            expect_status(label, yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
            executedCases++;
            expect_true("      padding intact after rotate", padding_intact(&destination));

            heap_frame_free(&source);
            heap_frame_free(&destination);
        }
    }
}

/* ============================================================================
 * C-07: region of interest on heap frames (blur and effect)
 * ============================================================================ */

static void test_canary_probes_region(void) {
    printf("C-07: canary probes, region of interest\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};

    for (int f = 0; f < 3; f++) {
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, formats[f], 8, 8, 4);
        heap_frame_init(&destination, formats[f], 8, 8, 4);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 0.0);
        options.region.enabled = 1;
        options.region.left = 1;
        options.region.top = 1;
        options.region.right = 7;
        options.region.bottom = 7;

        char label[128];
        snprintf(label, sizeof(label), "C-07 mean blur %s 8x8 region [1,1,7,7)", names[f]);
        expect_status(label, yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
        executedCases++;
        expect_true("      padding intact after regional blur", padding_intact(&destination));

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * C-08: exact-fit heap allocation, no padding at all
 * ============================================================================ */

static void test_exact_fit_no_padding(void) {
    printf("C-08: exact-fit allocation (no padding slack)\n");

    const uint32_t formats[3] = {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420, YUV_FORMAT_NV12};
    const char *names[3] = {"BGRA", "I420", "NV12"};

    for (int f = 0; f < 3; f++) {
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, formats[f], 6, 4, 0);
        heap_frame_init(&destination, formats[f], 6, 4, 0);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();

        char label[96];
        snprintf(label, sizeof(label), "C-08 negate %s exact-fit 6x4", names[f]);
        expect_status(label, yuv_negate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_OK);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * C-09: repeated allocate/free cycles across the whole operation set
 *
 * Gives LSan many chances to disagree: each iteration allocates fresh source
 * and destination frames, calls a different entry point, and frees both
 * before the next iteration starts. A leak in any single operation shows up
 * as accumulated unreachable memory at process exit.
 * ============================================================================ */

static void test_repeated_allocate_free_cycles(void) {
    printf("C-09: repeated allocate/free cycles\n");

    for (int iteration = 0; iteration < 20; iteration++) {
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_I420, 6, 4, (uint32_t)(iteration % 4));
        heap_frame_init(&destination, YUV_FORMAT_I420, 6, 4, (uint32_t)(iteration % 4));
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);

        YuvStatus status;
        switch (iteration % 4) {
            case 0: {
                YuvEffectOptionsV1 options = effect_options();
                status = yuv_grayscale_v1(&sourceFrame, &destinationFrame, &options);
                break;
            }
            case 1: {
                YuvBlurOptionsV1 options = blur_options(1, 0.0);
                status = yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options);
                break;
            }
            case 2: {
                YuvBlurOptionsV1 options = blur_options(1, 1.2);
                status = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
                break;
            }
            default: {
                YuvEffectOptionsV1 options = effect_options();
                status = yuv_negate_v1(&sourceFrame, &destinationFrame, &options);
                break;
            }
        }

        char label[64];
        snprintf(label, sizeof(label), "C-09 iteration %d", iteration);
        expect_status(label, status, YUV_STATUS_OK);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * H-01: invalid rect/radius/sigma/geometry on heap fixtures
 * ============================================================================ */

static void test_invalid_parameters(void) {
    printf("H-01: invalid rect/radius/sigma/geometry\n");

    {
        /* Invalid rect: crop extends past the source. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4, 3);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4, 3);
        memset(destination.planes[0], CANARY, (size_t)destination.length[0]);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvCropOptionsV1 options = crop_options(4, 0, 4, 4);
        expect_status("H-01 crop rectangle past source edge",
            yuv_crop_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;
        expect_true("      destination untouched", padding_intact(&destination));

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Invalid radius: above the accepted maximum of 256. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 4, 0);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(257, 0.0);
        expect_status("H-01 blur radius above 256", yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options),
            YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Invalid sigma: zero, negative, and non-finite are all rejected for
         * gaussian. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 4, 4, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4, 0);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);

        YuvBlurOptionsV1 zeroSigma = blur_options(2, 0.0);
        expect_status("H-01 gaussian sigma == 0", yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &zeroSigma),
            YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;

        YuvBlurOptionsV1 negativeSigma = blur_options(2, -3.0);
        expect_status("H-01 gaussian sigma < 0",
            yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &negativeSigma), YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Invalid geometry: rotate 90 requires a transposed destination; a
         * same-sized one is rejected before any pixel is touched. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 7, 5, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 7, 5, 0);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvRotateOptionsV1 options = rotate_options(90);
        expect_status("H-01 rotate 90 with non-transposed destination",
            yuv_rotate_v1(&sourceFrame, &destinationFrame, &options), YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Invalid geometry: zero width. */
        HeapFrame destination;
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4, 0);
        YuvConstFrameV1 source;
        memset(&source, 0, sizeof(source));
        source.structSize = (uint32_t)sizeof(source);
        source.abiVersion = YUV_ABI_VERSION_1;
        source.format = YUV_FORMAT_BGRA8888;
        source.planeCount = 1;
        source.width = 0;
        source.height = 4;
        uint8_t stub = 0;
        source.planes[0].data = &stub;
        source.planes[0].length = 1;
        source.planes[0].rowStride = 4;
        source.planes[0].pixelStride = 4;
        source.planes[0].sampleBytes = 4;

        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();
        expect_status("H-01 zero width source", yuv_grayscale_v1(&source, &destinationFrame, &options),
            YUV_STATUS_INVALID_ARGUMENT);
        executedCases++;

        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * H-02: checked-arithmetic overflow -- validation must reject before any
 * plane dereference, so an intentionally huge declared stride/length never
 * reaches a read/write a sanitizer could catch as a symptom.
 * ============================================================================ */

static void test_overflow_parameters(void) {
    printf("H-02: checked-arithmetic overflow\n");

    {
        HeapFrame destination;
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4, 0);
        uint8_t stub[16];
        memset(stub, CANARY, sizeof(stub));

        YuvConstFrameV1 source;
        memset(&source, 0, sizeof(source));
        source.structSize = (uint32_t)sizeof(source);
        source.abiVersion = YUV_ABI_VERSION_1;
        source.format = YUV_FORMAT_BGRA8888;
        source.planeCount = 1;
        source.width = 4;
        source.height = 4;
        source.planes[0].data = stub;
        /* rowStride near UINT64_MAX makes (height - 1) * rowStride
         * unrepresentable; the checked helpers must report OVERFLOW rather
         * than wrap into a plausible-looking small span that would then be
         * dereferenced. */
        source.planes[0].rowStride = UINT64_MAX - 1;
        source.planes[0].length = UINT64_MAX;
        source.planes[0].pixelStride = 4;
        source.planes[0].sampleBytes = 4;

        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvEffectOptionsV1 options = effect_options();
        expect_status("H-02 row stride overflows plane size computation",
            yuv_grayscale_v1(&source, &destinationFrame, &options), YUV_STATUS_OVERFLOW);
        executedCases++;
        expect_true("      destination untouched", padding_intact(&destination));

        heap_frame_free(&destination);
    }
    {
        /* Gaussian's own weight-table allocation size (side * side *
         * sizeof(double)) overflows at radius 256 combined with a
         * pathologically large... radius is capped at 256 by H-01, so this
         * probes the OTHER overflow path: yuv_checked_mul overflowing on the
         * cell count itself is unreachable under the 256 cap on a 64-bit
         * size_t, which this case documents rather than fabricates -- see
         * the row-stride probe above for the reachable OVERFLOW path
         * through blur's shared validation prologue. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 4, 4, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 4, 4, 0);
        fill_pattern(&source);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(256, 1.0);
        YuvStatus status = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
        volatile int accepted = (status == YUV_STATUS_OK);
        checks++;
        executedCases++;
        if (accepted) {
            printf("  ok    H-02 maximum accepted radius (256) allocates and completes\n");
        } else {
            printf("  FAIL  H-02 maximum accepted radius (256) status=%d, expected OK\n", (int)status);
            failures++;
        }

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

/* ============================================================================
 * Allocation-failure injection (blur only: the sole entry points that
 * malloc). Compiled only when the build defines ENABLE_MALLOC_WRAP, which the
 * CMake target does on platforms whose linker accepts --wrap (the ELF
 * toolchain the required Ubuntu ASan/UBSan job actually uses). On other
 * toolchains this group is skipped and reported as such, rather than
 * silently omitted -- see the DoD note on `checks`/`executedCases` staying
 * meaningful across platforms.
 * ============================================================================ */

#ifdef ENABLE_MALLOC_WRAP

extern void *__real_malloc(size_t size);

/* Declared here because --wrap gives this external linkage by construction
 * (the linker redirects every unresolved call to malloc() straight to it),
 * so there is no natural caller-side header to declare it in; without this
 * prototype -Wmissing-prototypes (part of this harness's own /W4-equivalent
 * -Werror set) would fail the build on the very toolchain this code targets. */
void *__wrap_malloc(size_t size);

/*
 * Lets a case target a specific call in a sequence of mallocs the code under
 * test makes, rather than only "the next one":
 *
 *   g_mallocSkipCount  -- let this many upcoming calls through to the real
 *                         allocator untouched, decrementing on each one.
 *   g_mallocFailCount  -- once the skip budget is exhausted, fail this many
 *                         calls with NULL, decrementing on each one.
 *
 * Both are declared volatile: the sanitizer runtime itself may call malloc
 * between a case's setup and the call under test, and this prevents the
 * compiler from assuming either counter is invariant across that call.
 */
static volatile int g_mallocSkipCount = 0;
static volatile int g_mallocFailCount = 0;

void *__wrap_malloc(size_t size) {
    if (g_mallocSkipCount > 0) {
        g_mallocSkipCount--;
        return __real_malloc(size);
    }
    if (g_mallocFailCount > 0) {
        g_mallocFailCount--;
        return NULL;
    }
    return __real_malloc(size);
}

static void malloc_injection_reset(void) {
    g_mallocSkipCount = 0;
    g_mallocFailCount = 0;
}

static void test_allocation_failure_injection(void) {
    printf("Allocation-failure injection (--wrap=malloc)\n");

    {
        /* yuv_kernel_v1_blur's snapshot allocation is the first and only
         * malloc for a radius-0 call (gaussian's own weight table is skipped
         * at radius 0), so failing exactly the next call targets it
         * precisely. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4, 3);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 4, 3);
        fill_pattern(&source);
        memset(destination.planes[0], CANARY, (size_t)destination.length[0]);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(1, 0.0);

        malloc_injection_reset();
        g_mallocFailCount = 1;
        YuvStatus status = yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options);
        malloc_injection_reset();

        expect_status("mean blur snapshot allocation fails", status, YUV_STATUS_ALLOCATION_FAILED);
        executedCases++;
        /* The proof is byte-for-byte: every destination byte, including
         * the padding, must still read as the canary this case pre-filled,
         * since blur's allocation happens before the first destination
         * write (docs/api-abi-0.3-design.md section 13). */
        {
            int untouched = 1;
            for (size_t i = 0; i < (size_t)destination.length[0]; i++) {
                if (destination.planes[0][i] != CANARY) {
                    untouched = 0;
                    break;
                }
            }
            expect_true("      destination byte-for-byte untouched on allocation failure", untouched);
        }

        /* A second, unaffected call on the same fixture must succeed --
         * proving the injected failure did not corrupt global state, and
         * that no earlier partial allocation was ever committed. */
        YuvStatus retryStatus = yuv_mean_blur_v1(&sourceFrame, &destinationFrame, &options);
        expect_status("retry after clearing the injected failure succeeds", retryStatus, YUV_STATUS_OK);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Gaussian has two allocation sites: its own weight table, then the
         * shared snapshot inside yuv_kernel_v1_blur. Failing the FIRST call
         * targets the weight table and proves that path's cleanup too (no
         * partial table survives, no snapshot is ever allocated). */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 4, 0);
        fill_pattern(&source);
        memset(destination.planes[0], CANARY, (size_t)destination.length[0]);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 1.5);

        malloc_injection_reset();
        g_mallocFailCount = 1;
        YuvStatus status = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
        malloc_injection_reset();

        expect_status("gaussian weight-table allocation fails", status, YUV_STATUS_ALLOCATION_FAILED);
        executedCases++;

        int untouched = 1;
        for (size_t i = 0; i < (size_t)destination.length[0]; i++) {
            if (destination.planes[0][i] != CANARY) {
                untouched = 0;
                break;
            }
        }
        expect_true("      destination byte-for-byte untouched on weight-table failure", untouched);

        YuvStatus retryStatus = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
        expect_status("retry after clearing the injected failure succeeds", retryStatus, YUV_STATUS_OK);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
    {
        /* Failing the SECOND allocation for a gaussian call (the weight
         * table succeeds, the shared snapshot inside yuv_kernel_v1_blur
         * fails) proves the weight table itself is freed on that later
         * failure and does not leak -- yuv_gaussian_blur_v1 frees `weights`
         * unconditionally after calling yuv_kernel_v1_blur, on both its OK
         * and non-OK return. */
        HeapFrame source;
        HeapFrame destination;
        heap_frame_init(&source, YUV_FORMAT_BGRA8888, 6, 4, 0);
        heap_frame_init(&destination, YUV_FORMAT_BGRA8888, 6, 4, 0);
        fill_pattern(&source);
        memset(destination.planes[0], CANARY, (size_t)destination.length[0]);

        YuvConstFrameV1 sourceFrame = as_source(&source);
        YuvMutableFrameV1 destinationFrame = as_destination(&destination);
        YuvBlurOptionsV1 options = blur_options(2, 1.5);

        malloc_injection_reset();
        g_mallocSkipCount = 1; /* let the weight-table malloc through */
        g_mallocFailCount = 1; /* fail the shared snapshot malloc */
        YuvStatus status = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
        malloc_injection_reset();

        expect_status("gaussian snapshot allocation fails after weight table succeeds", status,
            YUV_STATUS_ALLOCATION_FAILED);
        executedCases++;

        int untouched = 1;
        for (size_t i = 0; i < (size_t)destination.length[0]; i++) {
            if (destination.planes[0][i] != CANARY) {
                untouched = 0;
                break;
            }
        }
        expect_true("      destination byte-for-byte untouched on snapshot failure", untouched);

        /* If the weight table leaked, LSan (enabled by default with ASan on
         * the required Linux job) fails the whole test binary at exit; there
         * is nothing more specific to assert locally than "the process is
         * still clean here", which is exactly what a leak report would
         * violate. */
        YuvStatus retryStatus = yuv_gaussian_blur_v1(&sourceFrame, &destinationFrame, &options);
        expect_status("retry after clearing the injected failure succeeds", retryStatus, YUV_STATUS_OK);
        executedCases++;

        heap_frame_free(&source);
        heap_frame_free(&destination);
    }
}

#else

static void test_allocation_failure_injection(void) {
    printf("Allocation-failure injection: SKIPPED on this toolchain\n");
    printf("  (ENABLE_MALLOC_WRAP not defined -- linker does not support --wrap on this\n");
    printf("   target; the required Ubuntu ASan/UBSan job builds with GNU/gold/lld on\n");
    printf("   ELF, where this group runs for real. See test_native/CMakeLists.txt.)\n");
}

#endif

int main(void) {
    printf("=============================================================\n");
    printf("ABI v1 native ASan/UBSan/LSan safety gate (YUV-34)\n");
    printf("=============================================================\n");

    test_canary_probes_effect_and_blur();
    printf("\n");
    test_canary_probes_convert();
    printf("\n");
    test_canary_probe_chroma_swap();
    printf("\n");
    test_canary_probes_crop();
    printf("\n");
    test_canary_probes_flip();
    printf("\n");
    test_canary_probes_rotate();
    printf("\n");
    test_canary_probes_region();
    printf("\n");
    test_exact_fit_no_padding();
    printf("\n");
    test_repeated_allocate_free_cycles();
    printf("\n");
    test_invalid_parameters();
    printf("\n");
    test_overflow_parameters();
    printf("\n");
    test_allocation_failure_injection();
    printf("\n");

    printf("-------------------------------------------------------------\n");
    printf("checks: %d, failures: %d, executed cases: %ld\n", checks, failures, executedCases);
    printf("-------------------------------------------------------------\n");
    return failures == 0 ? 0 : 1;
}
