#include "h/yuv_kernel_v1.h"
#include "../utils/h/checked_arithmetic.h"

#include <stdlib.h>
#include <string.h>

/*
 * The integer coefficients below are the reference oracle verbatim
 * (test/helpers/reference/test_pattern_reference.dart): BT.601 limited /
 * video range. They are not a re-derivation, and they are deliberately the
 * only copy in the native tree -- YUV-32 exists because BGRA->YUV once used a
 * different (full-range 77/150/29) matrix than RGBA->YUV, so the same frame
 * encoded to two different results depending on which symbol was called.
 */

static uint8_t yuv_kernel_v1_clip(int32_t value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return (uint8_t)value;
}

const uint8_t *yuv_kernel_v1_const_sample(const YuvValidatedConstPlaneIn *plane, uint32_t x, uint32_t y) {
    YuvSizeResult offset = yuv_checked_sample_offset(y, plane->rowStride, x, plane->pixelStride);
    if (!offset.success) {
        return NULL;
    }
    return (const uint8_t *)plane->data + offset.value;
}

uint8_t *yuv_kernel_v1_mutable_sample(const YuvValidatedMutablePlaneIn *plane, uint32_t x, uint32_t y) {
    YuvSizeResult offset = yuv_checked_sample_offset(y, plane->rowStride, x, plane->pixelStride);
    if (!offset.success) {
        return NULL;
    }
    return (uint8_t *)plane->data + offset.value;
}

int yuv_kernel_v1_is_420(uint32_t format) {
    return format == YUV_VIEW_FORMAT_I420 || format == YUV_VIEW_FORMAT_NV12;
}

YuvRgbaPixelV1 yuv_kernel_v1_yuv_to_rgb(uint8_t y, uint8_t u, uint8_t v) {
    int32_t c = (int32_t)y - 16;
    int32_t d = (int32_t)u - 128;
    int32_t e = (int32_t)v - 128;
    YuvRgbaPixelV1 pixel;
    pixel.r = yuv_kernel_v1_clip((298 * c + 409 * e + 128) >> 8);
    pixel.g = yuv_kernel_v1_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    pixel.b = yuv_kernel_v1_clip((298 * c + 516 * d + 128) >> 8);
    pixel.a = 255;
    return pixel;
}

uint8_t yuv_kernel_v1_rgb_to_y(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_kernel_v1_clip(((66 * (int32_t)r + 129 * (int32_t)g + 25 * (int32_t)b + 128) >> 8) + 16);
}

uint8_t yuv_kernel_v1_rgb_to_u(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_kernel_v1_clip(((-38 * (int32_t)r - 74 * (int32_t)g + 112 * (int32_t)b + 128) >> 8) + 128);
}

uint8_t yuv_kernel_v1_rgb_to_v(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_kernel_v1_clip(((112 * (int32_t)r - 94 * (int32_t)g - 18 * (int32_t)b + 128) >> 8) + 128);
}

uint8_t yuv_kernel_v1_gray(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_kernel_v1_clip((int32_t)((299 * (int32_t)r + 587 * (int32_t)g + 114 * (int32_t)b + 500) / 1000));
}

YuvRgbaPixelV1 yuv_kernel_v1_read_pixel(const YuvValidatedConstFrameView *frame, uint32_t x, uint32_t y) {
    YuvRgbaPixelV1 pixel;
    pixel.r = 0;
    pixel.g = 0;
    pixel.b = 0;
    pixel.a = 255;

    if (frame->format == YUV_VIEW_FORMAT_BGRA8888 || frame->format == YUV_VIEW_FORMAT_RGBA8888) {
        const uint8_t *sample = yuv_kernel_v1_const_sample(&frame->planes[0], x, y);
        if (sample == NULL) {
            return pixel;
        }
        if (frame->format == YUV_VIEW_FORMAT_BGRA8888) {
            pixel.b = sample[0];
            pixel.g = sample[1];
            pixel.r = sample[2];
        } else {
            pixel.r = sample[0];
            pixel.g = sample[1];
            pixel.b = sample[2];
        }
        pixel.a = sample[3];
        return pixel;
    }

    /* 4:2:0: the chroma sample at (x/2, y/2) serves the whole 2x2 luma block.
     * Integer division is the decode side of the same footprint rule the
     * encoder averages over. */
    const uint8_t *luma = yuv_kernel_v1_const_sample(&frame->planes[0], x, y);
    if (luma == NULL) {
        return pixel;
    }

    uint8_t u = 128;
    uint8_t v = 128;
    if (frame->format == YUV_VIEW_FORMAT_I420) {
        const uint8_t *uSample = yuv_kernel_v1_const_sample(&frame->planes[1], x / 2, y / 2);
        const uint8_t *vSample = yuv_kernel_v1_const_sample(&frame->planes[2], x / 2, y / 2);
        if (uSample == NULL || vSample == NULL) {
            return pixel;
        }
        u = uSample[0];
        v = vSample[0];
    } else {
        const uint8_t *uvSample = yuv_kernel_v1_const_sample(&frame->planes[1], x / 2, y / 2);
        if (uvSample == NULL) {
            return pixel;
        }
        u = uvSample[0];
        v = uvSample[1];
    }

    return yuv_kernel_v1_yuv_to_rgb(luma[0], u, v);
}

void yuv_kernel_v1_write_luma(
    const YuvValidatedMutableFrameView *frame, uint32_t x, uint32_t y, YuvRgbaPixelV1 pixel) {
    if (frame->format == YUV_VIEW_FORMAT_BGRA8888) {
        uint8_t *sample = yuv_kernel_v1_mutable_sample(&frame->planes[0], x, y);
        if (sample == NULL) {
            return;
        }
        sample[0] = pixel.b;
        sample[1] = pixel.g;
        sample[2] = pixel.r;
        sample[3] = pixel.a;
        return;
    }

    uint8_t *luma = yuv_kernel_v1_mutable_sample(&frame->planes[0], x, y);
    if (luma == NULL) {
        return;
    }
    luma[0] = yuv_kernel_v1_rgb_to_y(pixel.r, pixel.g, pixel.b);
}

void yuv_kernel_v1_encode_chroma_block(
    const YuvValidatedMutableFrameView *frame,
    uint32_t blockX,
    uint32_t blockY,
    const YuvRgbaPixelV1 *pixels,
    uint32_t count) {
    if (!yuv_kernel_v1_is_420(frame->format) || count == 0) {
        return;
    }

    /* RGB is averaged first and encoded once, rather than encoding each pixel
     * and averaging the U/V samples. The two differ, and the reference oracle
     * (rgbaToI420) does the former; averaging afterwards is what made the old
     * BGRA path disagree with the RGBA path on odd edges. */
    uint32_t red = 0;
    uint32_t green = 0;
    uint32_t blue = 0;
    for (uint32_t index = 0; index < count; index++) {
        red += pixels[index].r;
        green += pixels[index].g;
        blue += pixels[index].b;
    }

    uint8_t averageRed = (uint8_t)(red / count);
    uint8_t averageGreen = (uint8_t)(green / count);
    uint8_t averageBlue = (uint8_t)(blue / count);

    uint8_t u = yuv_kernel_v1_rgb_to_u(averageRed, averageGreen, averageBlue);
    uint8_t v = yuv_kernel_v1_rgb_to_v(averageRed, averageGreen, averageBlue);

    if (frame->format == YUV_VIEW_FORMAT_I420) {
        uint8_t *uSample = yuv_kernel_v1_mutable_sample(&frame->planes[1], blockX, blockY);
        uint8_t *vSample = yuv_kernel_v1_mutable_sample(&frame->planes[2], blockX, blockY);
        if (uSample == NULL || vSample == NULL) {
            return;
        }
        uSample[0] = u;
        vSample[0] = v;
        return;
    }

    uint8_t *uvSample = yuv_kernel_v1_mutable_sample(&frame->planes[1], blockX, blockY);
    if (uvSample == NULL) {
        return;
    }
    uvSample[0] = u;
    uvSample[1] = v;
}

void yuv_kernel_v1_copy_pixel(
    const YuvValidatedConstFrameView *source,
    uint32_t sourceX,
    uint32_t sourceY,
    const YuvValidatedMutableFrameView *destination,
    uint32_t destinationX,
    uint32_t destinationY) {
    if (destination->format == YUV_VIEW_FORMAT_BGRA8888) {
        const uint8_t *from = yuv_kernel_v1_const_sample(&source->planes[0], sourceX, sourceY);
        uint8_t *to = yuv_kernel_v1_mutable_sample(&destination->planes[0], destinationX, destinationY);
        if (from == NULL || to == NULL) {
            return;
        }
        /* Four bytes, not pixelStride bytes: a larger pixel stride is a gap
         * between samples, and copying across it would both read and write
         * padding. That confusion is defect C-03 in the YUV-31 audit. */
        memcpy(to, from, 4);
        return;
    }

    const uint8_t *fromLuma = yuv_kernel_v1_const_sample(&source->planes[0], sourceX, sourceY);
    uint8_t *toLuma = yuv_kernel_v1_mutable_sample(&destination->planes[0], destinationX, destinationY);
    if (fromLuma == NULL || toLuma == NULL) {
        return;
    }
    toLuma[0] = fromLuma[0];

    /* Chroma is written once per destination 2x2 block, by the pixel that
     * lands on that block's top-left corner. Writing it for every luma pixel
     * would be three redundant stores whose result depends on traversal
     * order. */
    if ((destinationX % 2) != 0 || (destinationY % 2) != 0) {
        return;
    }

    uint32_t sourceChromaX = sourceX / 2;
    uint32_t sourceChromaY = sourceY / 2;
    uint32_t destinationChromaX = destinationX / 2;
    uint32_t destinationChromaY = destinationY / 2;

    if (destination->format == YUV_VIEW_FORMAT_I420) {
        const uint8_t *fromU = yuv_kernel_v1_const_sample(&source->planes[1], sourceChromaX, sourceChromaY);
        const uint8_t *fromV = yuv_kernel_v1_const_sample(&source->planes[2], sourceChromaX, sourceChromaY);
        uint8_t *toU = yuv_kernel_v1_mutable_sample(&destination->planes[1], destinationChromaX, destinationChromaY);
        uint8_t *toV = yuv_kernel_v1_mutable_sample(&destination->planes[2], destinationChromaX, destinationChromaY);
        if (fromU == NULL || fromV == NULL || toU == NULL || toV == NULL) {
            return;
        }
        toU[0] = fromU[0];
        toV[0] = fromV[0];
        return;
    }

    const uint8_t *fromUv = yuv_kernel_v1_const_sample(&source->planes[1], sourceChromaX, sourceChromaY);
    uint8_t *toUv = yuv_kernel_v1_mutable_sample(&destination->planes[1], destinationChromaX, destinationChromaY);
    if (fromUv == NULL || toUv == NULL) {
        return;
    }
    toUv[0] = fromUv[0];
    toUv[1] = fromUv[1];
}

void yuv_kernel_v1_transform(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    YuvPixelMapV1 map,
    void *context,
    int blockAligned) {
    uint32_t width = destination->width;
    uint32_t height = destination->height;

    if (!yuv_kernel_v1_is_420(destination->format) || blockAligned) {
        for (uint32_t y = 0; y < height; y++) {
            for (uint32_t x = 0; x < width; x++) {
                uint32_t sourceX = 0;
                uint32_t sourceY = 0;
                map(context, x, y, &sourceX, &sourceY);
                yuv_kernel_v1_copy_pixel(source, sourceX, sourceY, destination, x, y);
            }
        }
        return;
    }

    /* Phase-correcting path. Luma still moves as stored bytes -- it is a 1:1
     * mapping and re-encoding it would quantize a second time for nothing --
     * but each destination chroma sample is rebuilt from the visible RGB of
     * the destination 2x2 footprint it actually covers. */
    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            uint32_t sourceX = 0;
            uint32_t sourceY = 0;
            map(context, x, y, &sourceX, &sourceY);

            const uint8_t *fromLuma = yuv_kernel_v1_const_sample(&source->planes[0], sourceX, sourceY);
            uint8_t *toLuma = yuv_kernel_v1_mutable_sample(&destination->planes[0], x, y);
            if (fromLuma == NULL || toLuma == NULL) {
                continue;
            }
            toLuma[0] = fromLuma[0];

            if ((x % 2) != 0 || (y % 2) != 0) {
                continue;
            }

            YuvRgbaPixelV1 footprint[4];
            uint32_t count = 0;
            for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                    uint32_t blockX = x + offsetX;
                    uint32_t blockY = y + offsetY;
                    if (blockX >= width || blockY >= height) {
                        continue;
                    }
                    uint32_t mappedX = 0;
                    uint32_t mappedY = 0;
                    map(context, blockX, blockY, &mappedX, &mappedY);
                    footprint[count] = yuv_kernel_v1_read_pixel(source, mappedX, mappedY);
                    count++;
                }
            }
            yuv_kernel_v1_encode_chroma_block(destination, x / 2, y / 2, footprint, count);
        }
    }
}

void yuv_kernel_v1_encode_frame(
    const YuvValidatedMutableFrameView *destination, YuvPixelSourceV1 produce, void *context) {
    uint32_t width = destination->width;
    uint32_t height = destination->height;

    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            yuv_kernel_v1_write_luma(destination, x, y, produce(context, x, y));
        }
    }

    if (!yuv_kernel_v1_is_420(destination->format)) {
        return;
    }

    /* Chroma is a second pass rather than an inline write inside the luma
     * loop: a chroma sample covers four luma pixels, so writing it once per
     * block from the block's average is the only order-independent way to do
     * it. The legacy kernels wrote it from whichever pixel happened to be
     * last, which made the result depend on the traversal direction. */
    for (uint32_t blockY = 0; blockY * 2 < height; blockY++) {
        for (uint32_t blockX = 0; blockX * 2 < width; blockX++) {
            YuvRgbaPixelV1 footprint[4];
            uint32_t count = 0;
            for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                    uint32_t x = blockX * 2 + offsetX;
                    uint32_t y = blockY * 2 + offsetY;
                    if (x >= width || y >= height) {
                        continue;
                    }
                    footprint[count] = produce(context, x, y);
                    count++;
                }
            }
            yuv_kernel_v1_encode_chroma_block(destination, blockX, blockY, footprint, count);
        }
    }
}

YuvRegionV1 yuv_kernel_v1_region(const YuvRegionOptionsV1 *options) {
    YuvRegionV1 region;
    region.enabled = options->enabled != 0;
    region.left = (uint32_t)options->left;
    region.top = (uint32_t)options->top;
    region.right = (uint32_t)options->right;
    region.bottom = (uint32_t)options->bottom;
    return region;
}

static int yuv_kernel_v1_region_contains(const YuvRegionV1 *region, uint32_t x, uint32_t y) {
    if (!region->enabled) {
        return 1;
    }
    return x >= region->left && x < region->right && y >= region->top && y < region->bottom;
}

typedef struct {
    const YuvValidatedConstFrameView *source;
    const YuvRegionV1 *region;
    YuvRgbEffectV1 effect;
    void *context;
} YuvEffectDriverV1;

/* The post-effect visible pixel at (x, y): transformed inside the region,
 * the untouched source pixel outside it. Alpha always comes from the source,
 * so an effect cannot alter it even by returning a different one. */
static YuvRgbaPixelV1 yuv_kernel_v1_effect_pixel(void *context, uint32_t x, uint32_t y) {
    YuvEffectDriverV1 *driver = (YuvEffectDriverV1 *)context;
    YuvRgbaPixelV1 pixel = yuv_kernel_v1_read_pixel(driver->source, x, y);
    if (!yuv_kernel_v1_region_contains(driver->region, x, y)) {
        return pixel;
    }
    uint8_t alpha = pixel.a;
    YuvRgbaPixelV1 result = driver->effect(driver->context, pixel, x, y);
    result.a = alpha;
    return result;
}

/*
 * Writes a destination frame from a visible-pixel producer while honouring a
 * region of interest.
 *
 * The rule that makes this non-trivial for 4:2:0 is that a sample outside the
 * region must come back byte-identical, and a chroma sample is shared by four
 * luma pixels. So:
 *
 *  - luma/packed outside the region is copied from the stored source sample,
 *    never decoded and re-encoded, because a round trip would quantize a
 *    pixel the caller asked not to touch;
 *  - a chroma block is re-encoded only when its 2x2 footprint intersects the
 *    region (section 14 Q2), and is otherwise copied. A boundary block is
 *    re-encoded from the post-operation RGB of its whole footprint, which is
 *    the documented shared-chroma influence.
 */
static void yuv_kernel_v1_write_region(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    YuvPixelSourceV1 produce,
    void *context) {
    uint32_t width = destination->width;
    uint32_t height = destination->height;

    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            if (!yuv_kernel_v1_region_contains(region, x, y)) {
                yuv_kernel_v1_copy_pixel(source, x, y, destination, x, y);
                continue;
            }
            yuv_kernel_v1_write_luma(destination, x, y, produce(context, x, y));
        }
    }

    if (!yuv_kernel_v1_is_420(destination->format)) {
        return;
    }

    for (uint32_t blockY = 0; blockY * 2 < height; blockY++) {
        for (uint32_t blockX = 0; blockX * 2 < width; blockX++) {
            YuvRgbaPixelV1 footprint[4];
            uint32_t count = 0;
            int intersects = 0;
            for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                    uint32_t x = blockX * 2 + offsetX;
                    uint32_t y = blockY * 2 + offsetY;
                    if (x >= width || y >= height) {
                        continue;
                    }
                    if (yuv_kernel_v1_region_contains(region, x, y)) {
                        intersects = 1;
                        footprint[count] = produce(context, x, y);
                    } else {
                        /* A pixel outside the region contributes its
                         * untouched visible value, so the shared chroma of a
                         * boundary block reflects what that pixel still is
                         * rather than what the operation would have made it. */
                        footprint[count] = yuv_kernel_v1_read_pixel(source, x, y);
                    }
                    count++;
                }
            }
            if (!intersects) {
                /* Nothing in this block was selected, so the luma pass has
                 * already copied its chroma across unchanged. */
                continue;
            }
            yuv_kernel_v1_encode_chroma_block(destination, blockX, blockY, footprint, count);
        }
    }
}

void yuv_kernel_v1_apply_effect(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    YuvRgbEffectV1 effect,
    void *context) {
    YuvEffectDriverV1 driver;
    driver.source = source;
    driver.region = region;
    driver.effect = effect;
    driver.context = context;

    yuv_kernel_v1_write_region(source, destination, region, yuv_kernel_v1_effect_pixel, &driver);
}

/*
 * The decoded source snapshot the blur convolves over.
 *
 * Blur reads a neighbourhood, so it cannot read the destination it is
 * writing: the legacy kernels did, which made the result depend on traversal
 * order (probes produced 170 and 198 where the snapshot answer was 127). One
 * decoded copy of the visible image removes that, and decoding once also
 * avoids re-running the BT.601 decode (2*radius+1)^2 times per pixel.
 */
typedef struct {
    uint32_t width;
    uint32_t height;
    YuvRgbaPixelV1 *pixels;
} YuvSnapshotV1;

static YuvRgbaPixelV1 yuv_snapshot_at(const YuvSnapshotV1 *snapshot, uint32_t x, uint32_t y) {
    return snapshot->pixels[(size_t)y * snapshot->width + x];
}

/* Clamps a signed coordinate into [0, extent-1]: the edge-replicate rule. */
static uint32_t yuv_clamp_coordinate(int64_t value, uint32_t extent) {
    if (value < 0) {
        return 0;
    }
    if (value >= (int64_t)extent) {
        return extent - 1;
    }
    return (uint32_t)value;
}

typedef struct {
    const YuvSnapshotV1 *snapshot;
    const YuvRegionV1 *region;
    uint32_t radius;
    const double *weights;
} YuvBlurContextV1;

static YuvRgbaPixelV1 yuv_blur_pixel(void *context, uint32_t x, uint32_t y) {
    YuvBlurContextV1 *blur = (YuvBlurContextV1 *)context;
    YuvRgbaPixelV1 centre = yuv_snapshot_at(blur->snapshot, x, y);

    /* Outside the region of interest the pixel is reproduced exactly. Kernel
     * reads from inside the region may still cross the boundary, which is the
     * documented direction of influence. */
    if (blur->region->enabled &&
        !(x >= blur->region->left && x < blur->region->right && y >= blur->region->top &&
            y < blur->region->bottom)) {
        return centre;
    }

    int64_t radius = (int64_t)blur->radius;
    uint32_t side = blur->radius * 2 + 1;

    if (blur->weights == NULL) {
        /* Uniform weights. The sum of at most 513x513 samples of at most 255
         * fits far inside int64_t, so no intermediate can overflow. */
        int64_t red = 0;
        int64_t green = 0;
        int64_t blue = 0;
        int64_t area = (int64_t)side * (int64_t)side;
        for (int64_t offsetY = -radius; offsetY <= radius; offsetY++) {
            uint32_t sampleY = yuv_clamp_coordinate((int64_t)y + offsetY, blur->snapshot->height);
            for (int64_t offsetX = -radius; offsetX <= radius; offsetX++) {
                uint32_t sampleX = yuv_clamp_coordinate((int64_t)x + offsetX, blur->snapshot->width);
                YuvRgbaPixelV1 sample = yuv_snapshot_at(blur->snapshot, sampleX, sampleY);
                red += sample.r;
                green += sample.g;
                blue += sample.b;
            }
        }
        YuvRgbaPixelV1 result;
        /* Half-up rounding, as (sum + area/2) / area on non-negative sums. */
        result.r = (uint8_t)((red + area / 2) / area);
        result.g = (uint8_t)((green + area / 2) / area);
        result.b = (uint8_t)((blue + area / 2) / area);
        result.a = centre.a;
        return result;
    }

    double red = 0.0;
    double green = 0.0;
    double blue = 0.0;
    double total = 0.0;
    for (int64_t offsetY = -radius; offsetY <= radius; offsetY++) {
        uint32_t sampleY = yuv_clamp_coordinate((int64_t)y + offsetY, blur->snapshot->height);
        for (int64_t offsetX = -radius; offsetX <= radius; offsetX++) {
            uint32_t sampleX = yuv_clamp_coordinate((int64_t)x + offsetX, blur->snapshot->width);
            double weight = blur->weights[(size_t)(offsetY + radius) * side + (size_t)(offsetX + radius)];
            YuvRgbaPixelV1 sample = yuv_snapshot_at(blur->snapshot, sampleX, sampleY);
            red += weight * sample.r;
            green += weight * sample.g;
            blue += weight * sample.b;
            total += weight;
        }
    }

    YuvRgbaPixelV1 result;
    result.r = yuv_kernel_v1_clip((int32_t)(red / total + 0.5));
    result.g = yuv_kernel_v1_clip((int32_t)(green / total + 0.5));
    result.b = yuv_kernel_v1_clip((int32_t)(blue / total + 0.5));
    result.a = centre.a;
    return result;
}

YuvStatus yuv_kernel_v1_blur(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    uint32_t radius,
    const double *weights) {
    uint32_t width = source->width;
    uint32_t height = source->height;

    /* The one allocation, sized with checked arithmetic and taken before any
     * destination byte is written, so a failure here is an atomic no-op. */
    YuvSizeResult pixelCount = yuv_checked_mul((size_t)width, (size_t)height);
    if (!pixelCount.success) {
        return YUV_STATUS_OVERFLOW;
    }
    YuvSizeResult bytes = yuv_checked_mul(pixelCount.value, sizeof(YuvRgbaPixelV1));
    if (!bytes.success) {
        return YUV_STATUS_OVERFLOW;
    }

    YuvRgbaPixelV1 *pixels = (YuvRgbaPixelV1 *)malloc(bytes.value);
    if (pixels == NULL) {
        return YUV_STATUS_ALLOCATION_FAILED;
    }

    for (uint32_t y = 0; y < height; y++) {
        for (uint32_t x = 0; x < width; x++) {
            pixels[(size_t)y * width + x] = yuv_kernel_v1_read_pixel(source, x, y);
        }
    }

    YuvSnapshotV1 snapshot;
    snapshot.width = width;
    snapshot.height = height;
    snapshot.pixels = pixels;

    YuvBlurContextV1 context;
    context.snapshot = &snapshot;
    context.region = region;
    context.radius = radius;
    context.weights = weights;

    /* The region-aware writer, not encode_frame: blur must leave samples
     * outside the region byte-identical, and for 4:2:0 re-encoding a whole
     * frame changes luma the caller asked to keep. */
    yuv_kernel_v1_write_region(source, destination, region, yuv_blur_pixel, &context);

    free(pixels);
    return YUV_STATUS_OK;
}
