#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"
#include "../utils/h/checked_arithmetic.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t r;
    uint32_t g;
    uint32_t b;
} YuvMeanSumV1;

static uint32_t yuv_mean_clamp(int64_t value, uint32_t extent) {
    if (value < 0) {
        return 0;
    }
    if (value >= (int64_t)extent) {
        return extent - 1;
    }
    return (uint32_t)value;
}

static int yuv_mean_contains(const YuvRegionV1 *region, uint32_t x, uint32_t y) {
    return !region->enabled ||
        (x >= region->left && x < region->right && y >= region->top && y < region->bottom);
}

static uint8_t yuv_mean_clip(int32_t value) {
    return (uint8_t)(value < 0 ? 0 : (value > 255 ? 255 : value));
}

static YuvRgbaPixelV1 yuv_mean_read_pixel(
    const YuvValidatedConstFrameView *source, uint32_t x, uint32_t y) {
    YuvRgbaPixelV1 pixel;
    if (source->format == YUV_VIEW_FORMAT_BGRA8888) {
        const YuvValidatedConstPlaneIn *plane = &source->planes[0];
        const uint8_t *sample = (const uint8_t *)plane->data +
            (size_t)y * plane->rowStride + (size_t)x * plane->pixelStride;
        pixel.r = sample[2];
        pixel.g = sample[1];
        pixel.b = sample[0];
        pixel.a = sample[3];
        return pixel;
    }
    const YuvValidatedConstPlaneIn *luma = &source->planes[0];
    const YuvValidatedConstPlaneIn *chroma = &source->planes[1];
    const uint8_t *ySample = (const uint8_t *)luma->data +
        (size_t)y * luma->rowStride + (size_t)x * luma->pixelStride;
    const uint8_t *uSample = (const uint8_t *)chroma->data +
        (size_t)(y / 2) * chroma->rowStride + (size_t)(x / 2) * chroma->pixelStride;
    uint8_t u = uSample[0];
    uint8_t v;
    if (source->format == YUV_VIEW_FORMAT_I420) {
        const YuvValidatedConstPlaneIn *vPlane = &source->planes[2];
        v = *((const uint8_t *)vPlane->data +
            (size_t)(y / 2) * vPlane->rowStride + (size_t)(x / 2) * vPlane->pixelStride);
    } else {
        v = uSample[1];
    }
    int32_t c = (int32_t)ySample[0] - 16;
    int32_t d = (int32_t)u - 128;
    int32_t e = (int32_t)v - 128;
    pixel.r = yuv_mean_clip((298 * c + 409 * e + 128) >> 8);
    pixel.g = yuv_mean_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    pixel.b = yuv_mean_clip((298 * c + 516 * d + 128) >> 8);
    pixel.a = 255;
    return pixel;
}

static uint8_t yuv_mean_to_y(YuvRgbaPixelV1 pixel) {
    return yuv_mean_clip(((66 * (int32_t)pixel.r + 129 * (int32_t)pixel.g +
        25 * (int32_t)pixel.b + 128) >> 8) + 16);
}

static uint8_t yuv_mean_to_u(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_mean_clip(((-38 * (int32_t)r - 74 * (int32_t)g + 112 * (int32_t)b + 128) >> 8) + 128);
}

static uint8_t yuv_mean_to_v(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_mean_clip(((112 * (int32_t)r - 94 * (int32_t)g - 18 * (int32_t)b + 128) >> 8) + 128);
}

static void yuv_mean_horizontal_row(
    const YuvValidatedConstFrameView *source,
    uint32_t y,
    uint32_t radius,
    YuvRgbaPixelV1 *decoded,
    YuvMeanSumV1 *output) {
    uint32_t width = source->width;
    for (uint32_t x = 0; x < width; x++) {
        decoded[x] = yuv_mean_read_pixel(source, x, y);
    }
    YuvMeanSumV1 sum = {0, 0, 0};
    for (int64_t dx = -(int64_t)radius; dx <= (int64_t)radius; dx++) {
        YuvRgbaPixelV1 pixel = decoded[yuv_mean_clamp(dx, width)];
        sum.r += pixel.r;
        sum.g += pixel.g;
        sum.b += pixel.b;
    }
    output[0] = sum;
    for (uint32_t x = 1; x < width; x++) {
        YuvRgbaPixelV1 added = decoded[yuv_mean_clamp((int64_t)x + radius, width)];
        YuvRgbaPixelV1 removed = decoded[yuv_mean_clamp((int64_t)x - radius - 1, width)];
        sum.r += (uint32_t)added.r - removed.r;
        sum.g += (uint32_t)added.g - removed.g;
        sum.b += (uint32_t)added.b - removed.b;
        output[x] = sum;
    }
}

static YuvStatus yuv_mean_blur_v1_run(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    uint32_t radius) {
    uint32_t width = source->width;
    uint32_t height = source->height;
    uint32_t side = radius * 2 + 1;
    uint32_t area = side * side;
    uint32_t ringRows = height < side ? height : side;
    YuvSizeResult ringCount = yuv_checked_mul((size_t)width, (size_t)ringRows);
    YuvSizeResult ringBytes = ringCount.success
        ? yuv_checked_mul(ringCount.value, sizeof(YuvMeanSumV1)) : ringCount;
    YuvSizeResult verticalBytes = yuv_checked_mul((size_t)width, sizeof(YuvMeanSumV1));
    YuvSizeResult rowBytes = yuv_checked_mul((size_t)width, sizeof(YuvRgbaPixelV1));
    YuvSizeResult outputBytes = rowBytes.success ? yuv_checked_mul(rowBytes.value, 2) : rowBytes;
    if (!ringBytes.success || !verticalBytes.success || !rowBytes.success || !outputBytes.success) {
        return YUV_STATUS_OVERFLOW;
    }

    /* All scratch is allocated before writing destination. Even at radius 256,
     * horizontal sums (513*255) and full sums (513*513*255) fit uint32_t. */
    YuvMeanSumV1 *ring = (YuvMeanSumV1 *)malloc(ringBytes.value);
    YuvMeanSumV1 *vertical = (YuvMeanSumV1 *)malloc(verticalBytes.value);
    YuvRgbaPixelV1 *decoded = (YuvRgbaPixelV1 *)malloc(rowBytes.value);
    YuvRgbaPixelV1 *outputRows = (YuvRgbaPixelV1 *)malloc(outputBytes.value);
    if (ring == NULL || vertical == NULL || decoded == NULL || outputRows == NULL) {
        free(ring);
        free(vertical);
        free(decoded);
        free(outputRows);
        return YUV_STATUS_ALLOCATION_FAILED;
    }

    uint32_t loadedMax = radius < height ? radius : height - 1;
    for (uint32_t sourceY = 0; sourceY <= loadedMax; sourceY++) {
        yuv_mean_horizontal_row(source, sourceY, radius, decoded,
            ring + (size_t)(sourceY % ringRows) * width);
    }
    for (uint32_t x = 0; x < width; x++) {
        YuvMeanSumV1 sum = {0, 0, 0};
        for (int64_t dy = -(int64_t)radius; dy <= (int64_t)radius; dy++) {
            uint32_t sampleY = yuv_mean_clamp(dy, height);
            YuvMeanSumV1 sample = ring[(size_t)(sampleY % ringRows) * width + x];
            sum.r += sample.r;
            sum.g += sample.g;
            sum.b += sample.b;
        }
        vertical[x] = sum;
    }

    const YuvValidatedConstPlaneIn *sourceLuma = &source->planes[0];
    const YuvValidatedMutablePlaneIn *destinationLuma = &destination->planes[0];
    for (uint32_t y = 0; y < height; y++) {
        YuvRgbaPixelV1 *blurred = outputRows + (size_t)(y % 2) * width;
        const uint8_t *fromRow = (const uint8_t *)sourceLuma->data + (size_t)y * sourceLuma->rowStride;
        uint8_t *toRow = (uint8_t *)destinationLuma->data + (size_t)y * destinationLuma->rowStride;
        for (uint32_t x = 0; x < width; x++) {
            const uint8_t *from = fromRow + (size_t)x * sourceLuma->pixelStride;
            uint8_t *to = toRow + (size_t)x * destinationLuma->pixelStride;
            YuvMeanSumV1 sum = vertical[x];
            YuvRgbaPixelV1 pixel;
            pixel.r = (uint8_t)((sum.r + area / 2) / area);
            pixel.g = (uint8_t)((sum.g + area / 2) / area);
            pixel.b = (uint8_t)((sum.b + area / 2) / area);
            pixel.a = source->format == YUV_VIEW_FORMAT_BGRA8888 ? from[3] : 255;
            blurred[x] = pixel;
            if (yuv_mean_contains(region, x, y)) {
                if (source->format == YUV_VIEW_FORMAT_BGRA8888) {
                    to[0] = pixel.b;
                    to[1] = pixel.g;
                    to[2] = pixel.r;
                    to[3] = pixel.a;
                } else {
                    to[0] = yuv_mean_to_y(pixel);
                }
            } else if (source->format == YUV_VIEW_FORMAT_BGRA8888) {
                memcpy(to, from, 4);
            } else {
                to[0] = from[0];
            }
        }

        if (source->format != YUV_VIEW_FORMAT_BGRA8888 && ((y % 2) != 0 || y + 1 == height)) {
            uint32_t blockY = y / 2;
            uint32_t chromaWidth = width / 2 + width % 2;
            for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
                uint32_t red = 0;
                uint32_t green = 0;
                uint32_t blue = 0;
                uint32_t footprintCount = 0;
                int intersects = 0;
                for (uint32_t dy = 0; dy < 2; dy++) {
                    for (uint32_t dx = 0; dx < 2; dx++) {
                        uint32_t x = blockX * 2 + dx;
                        uint32_t pixelY = blockY * 2 + dy;
                        if (x >= width || pixelY >= height) {
                            continue;
                        }
                        int selected = yuv_mean_contains(region, x, pixelY);
                        YuvRgbaPixelV1 pixel = selected
                            ? outputRows[(size_t)(pixelY % 2) * width + x] : yuv_mean_read_pixel(source, x, pixelY);
                        intersects |= selected;
                        red += pixel.r;
                        green += pixel.g;
                        blue += pixel.b;
                        footprintCount++;
                    }
                }
                const YuvValidatedConstPlaneIn *sourceU = &source->planes[1];
                const YuvValidatedMutablePlaneIn *destinationU = &destination->planes[1];
                const uint8_t *fromU = (const uint8_t *)sourceU->data +
                    (size_t)blockY * sourceU->rowStride + (size_t)blockX * sourceU->pixelStride;
                uint8_t *toU = (uint8_t *)destinationU->data +
                    (size_t)blockY * destinationU->rowStride + (size_t)blockX * destinationU->pixelStride;
                if (intersects) {
                    uint8_t u = yuv_mean_to_u((uint8_t)(red / footprintCount),
                        (uint8_t)(green / footprintCount), (uint8_t)(blue / footprintCount));
                    uint8_t v = yuv_mean_to_v((uint8_t)(red / footprintCount),
                        (uint8_t)(green / footprintCount), (uint8_t)(blue / footprintCount));
                    toU[0] = u;
                    if (source->format == YUV_VIEW_FORMAT_I420) {
                        const YuvValidatedMutablePlaneIn *destinationV = &destination->planes[2];
                        uint8_t *toV = (uint8_t *)destinationV->data +
                            (size_t)blockY * destinationV->rowStride + (size_t)blockX * destinationV->pixelStride;
                        toV[0] = v;
                    } else {
                        toU[1] = v;
                    }
                } else {
                    toU[0] = fromU[0];
                    if (source->format == YUV_VIEW_FORMAT_I420) {
                        const YuvValidatedConstPlaneIn *sourceV = &source->planes[2];
                        const YuvValidatedMutablePlaneIn *destinationV = &destination->planes[2];
                        const uint8_t *fromV = (const uint8_t *)sourceV->data +
                            (size_t)blockY * sourceV->rowStride + (size_t)blockX * sourceV->pixelStride;
                        uint8_t *toV = (uint8_t *)destinationV->data +
                            (size_t)blockY * destinationV->rowStride + (size_t)blockX * destinationV->pixelStride;
                        toV[0] = fromV[0];
                    } else {
                        toU[1] = fromU[1];
                    }
                }
            }
        }

        if (y + 1 < height) {
            uint32_t removedY = yuv_mean_clamp((int64_t)y - radius, height);
            uint32_t addedY = yuv_mean_clamp((int64_t)y + radius + 1, height);
            YuvMeanSumV1 *removed = ring + (size_t)(removedY % ringRows) * width;
            for (uint32_t x = 0; x < width; x++) {
                vertical[x].r -= removed[x].r;
                vertical[x].g -= removed[x].g;
                vertical[x].b -= removed[x].b;
            }
            if (addedY > loadedMax) {
                yuv_mean_horizontal_row(source, addedY, radius, decoded,
                    ring + (size_t)(addedY % ringRows) * width);
                loadedMax = addedY;
            }
            YuvMeanSumV1 *added = ring + (size_t)(addedY % ringRows) * width;
            for (uint32_t x = 0; x < width; x++) {
                vertical[x].r += added[x].r;
                vertical[x].g += added[x].g;
                vertical[x].b += added[x].b;
            }
        }
    }

    free(outputRows);
    free(decoded);
    free(vertical);
    free(ring);
    return YUV_STATUS_OK;
}

/*
 * Uniform mean blur: every kernel cell has weight 1/(2*radius+1)^2. Shares its
 * oracle with box blur, so both must produce the same logical result for the
 * same radius and ROI. Edge-replicate at the border.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_mean_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvBlurOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvBlurOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0 || options->reserved[1] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* radius 0 is a defined no-op rather than an error, but a radius past
     * 256 would make the kernel area exceed what the accumulators and the
     * reference oracle are defined for. */
    if (options->radius > 256) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (options->borderMode != YUV_BORDER_CLAMP) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Uniform-weight blur ignores sigma entirely, so a caller that set one
     * has misunderstood which operation they are calling; saying so beats
     * silently producing a differently-blurred frame than they expect. */
    if (options->sigma != 0.0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView sourceView;
    YuvValidatedMutableFrameView destinationView;
    YuvStatus framesStatus = yuv_validate_v1_frames(
        source, destination, YUV_GEOMETRY_V1_SAME, 0, 0, &sourceView, &destinationView);
    if (framesStatus != YUV_STATUS_OK) {
        return framesStatus;
    }

    YuvStatus pairStatus = yuv_validate_v1_format_pair(
        sourceView.format, destinationView.format, YUV_SAME_FORMAT_PAIRS_V1, 3);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    YuvStatus regionStatus = yuv_validate_v1_region(&options->region, sourceView.width, sourceView.height);
    if (regionStatus != YUV_STATUS_OK) {
        return regionStatus;
    }

    YuvRegionV1 region = yuv_kernel_v1_region(&options->region);

    return yuv_mean_blur_v1_run(&sourceView, &destinationView, &region, options->radius);
}
