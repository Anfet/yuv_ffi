#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/*
 * Visible RGB negate: each channel becomes 255 - channel, with alpha preserved.
 * I420->I420, NV12->NV12, BGRA->BGRA at identical geometry.
 */
/* Section 11: negate is an RGB operation, (255-R, 255-G, 255-B). Inverting
 * the stored Y/U/V samples instead is not equivalent in limited range -- that
 * is the MAE 8.152 in EFFECT-NEGATE-I420 -- and the legacy chroma form
 * 256 - value had no representable result for 0, wrapping back to 0 in a
 * uint8_t. Going through RGB removes both problems by construction. */
static YuvRgbaPixelV1 yuv_negate_v1_effect(void *context, YuvRgbaPixelV1 pixel, uint32_t x, uint32_t y) {
    (void)context;
    (void)x;
    (void)y;
    pixel.r = (uint8_t)(255 - pixel.r);
    pixel.g = (uint8_t)(255 - pixel.g);
    pixel.b = (uint8_t)(255 - pixel.b);
    return pixel;
}

static int yuv_negate_v1_is_tight_bgra(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    uint64_t rowBytes = (uint64_t)source->width * 4;
    return source->format == YUV_VIEW_FORMAT_BGRA8888 &&
        source->planes[0].pixelStride == 4 && destination->planes[0].pixelStride == 4 &&
        source->planes[0].rowStride == rowBytes && destination->planes[0].rowStride == rowBytes &&
        source->planes[0].data != destination->planes[0].data;
}

static void yuv_negate_v1_apply_tight_bgra(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region) {
    const uint8_t *input = (const uint8_t *)source->planes[0].data;
    uint8_t *output = (uint8_t *)destination->planes[0].data;
    size_t rowBytes = (size_t)source->width * 4;
    if (region->enabled) {
        memcpy(output, input, rowBytes * source->height);
    }
    uint32_t left = region->enabled ? region->left : 0;
    uint32_t top = region->enabled ? region->top : 0;
    uint32_t right = region->enabled ? region->right : source->width;
    uint32_t bottom = region->enabled ? region->bottom : source->height;
    for (uint32_t y = top; y < bottom; y++) {
        const uint8_t *from = input + (size_t)y * rowBytes + (size_t)left * 4;
        uint8_t *to = output + (size_t)y * rowBytes + (size_t)left * 4;
        for (uint32_t x = left; x < right; x++, from += 4, to += 4) {
            to[0] = (uint8_t)(255 - from[0]);
            to[1] = (uint8_t)(255 - from[1]);
            to[2] = (uint8_t)(255 - from[2]);
            to[3] = from[3];
        }
    }
}

static uint8_t yuv_negate_v1_clip(int32_t value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return (uint8_t)value;
}

static void yuv_negate_v1_decode(uint8_t y, uint8_t u, uint8_t v, uint8_t *red, uint8_t *green, uint8_t *blue) {
    int32_t c = (int32_t)y - 16;
    int32_t d = (int32_t)u - 128;
    int32_t e = (int32_t)v - 128;
    *red = yuv_negate_v1_clip((298 * c + 409 * e + 128) >> 8);
    *green = yuv_negate_v1_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    *blue = yuv_negate_v1_clip((298 * c + 516 * d + 128) >> 8);
}

static uint8_t yuv_negate_v1_encode_y(uint8_t red, uint8_t green, uint8_t blue) {
    return yuv_negate_v1_clip(((66 * (int32_t)red + 129 * (int32_t)green + 25 * (int32_t)blue + 128) >> 8) + 16);
}

static uint8_t yuv_negate_v1_encode_u(uint8_t red, uint8_t green, uint8_t blue) {
    return yuv_negate_v1_clip(((-38 * (int32_t)red - 74 * (int32_t)green + 112 * (int32_t)blue + 128) >> 8) + 128);
}

static uint8_t yuv_negate_v1_encode_v(uint8_t red, uint8_t green, uint8_t blue) {
    return yuv_negate_v1_clip(((112 * (int32_t)red - 94 * (int32_t)green - 18 * (int32_t)blue + 128) >> 8) + 128);
}

static int yuv_negate_v1_is_tight_420(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    if (source->format != YUV_VIEW_FORMAT_I420 && source->format != YUV_VIEW_FORMAT_NV12) {
        return 0;
    }

    uint64_t chromaWidth = source->width / 2 + source->width % 2;
    uint64_t chromaHeight = source->height / 2 + source->height % 2;
    if (source->planes[0].pixelStride != 1 || destination->planes[0].pixelStride != 1 ||
        source->planes[0].rowStride != source->width || destination->planes[0].rowStride != source->width) {
        return 0;
    }
    if (source->format == YUV_VIEW_FORMAT_I420) {
        return source->planes[1].pixelStride == 1 && source->planes[2].pixelStride == 1 &&
            destination->planes[1].pixelStride == 1 && destination->planes[2].pixelStride == 1 &&
            source->planes[1].rowStride == chromaWidth && source->planes[2].rowStride == chromaWidth &&
            destination->planes[1].rowStride == chromaWidth && destination->planes[2].rowStride == chromaWidth &&
            chromaHeight != 0;
    }
    return source->planes[1].pixelStride == 2 && destination->planes[1].pixelStride == 2 &&
        source->planes[1].rowStride == chromaWidth * 2 && destination->planes[1].rowStride == chromaWidth * 2 &&
        chromaHeight != 0;
}

static int yuv_negate_v1_region_contains(const YuvRegionV1 *region, uint32_t x, uint32_t y) {
    return !region->enabled || (x >= region->left && x < region->right && y >= region->top && y < region->bottom);
}

static void yuv_negate_v1_apply_tight_420(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region) {
    uint32_t width = source->width;
    uint32_t height = source->height;
    uint32_t chromaWidth = width / 2 + width % 2;
    uint32_t chromaHeight = height / 2 + height % 2;
    const uint8_t *sourceY = (const uint8_t *)source->planes[0].data;
    uint8_t *destinationY = (uint8_t *)destination->planes[0].data;
    const uint8_t *sourceU = (const uint8_t *)source->planes[1].data;
    uint8_t *destinationU = (uint8_t *)destination->planes[1].data;
    const uint8_t *sourceV = source->format == YUV_VIEW_FORMAT_I420 ? (const uint8_t *)source->planes[2].data : NULL;
    uint8_t *destinationV = destination->format == YUV_VIEW_FORMAT_I420 ? (uint8_t *)destination->planes[2].data : NULL;

    if (!region->enabled) {
        for (uint32_t blockY = 0; blockY < chromaHeight; blockY++) {
            uint32_t y = blockY * 2;
            const uint8_t *sourceURow = sourceU + (size_t)blockY *
                (source->format == YUV_VIEW_FORMAT_I420 ? chromaWidth : chromaWidth * 2);
            const uint8_t *sourceVRow = source->format == YUV_VIEW_FORMAT_I420 ?
                sourceV + (size_t)blockY * chromaWidth : NULL;
            for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
                uint32_t x = blockX * 2;
                uint8_t u = source->format == YUV_VIEW_FORMAT_I420 ? sourceURow[blockX] : sourceURow[blockX * 2];
                uint8_t v = source->format == YUV_VIEW_FORMAT_I420 ? sourceVRow[blockX] : sourceURow[blockX * 2 + 1];
                uint32_t red = 0;
                uint32_t green = 0;
                uint32_t blue = 0;
                uint32_t count = 0;
                for (uint32_t offsetY = 0; offsetY < 2 && y + offsetY < height; offsetY++) {
                    const uint8_t *sourceYRow = sourceY + (size_t)(y + offsetY) * width;
                    uint8_t *destinationYRow = destinationY + (size_t)(y + offsetY) * width;
                    for (uint32_t offsetX = 0; offsetX < 2 && x + offsetX < width; offsetX++) {
                        uint8_t pixelRed;
                        uint8_t pixelGreen;
                        uint8_t pixelBlue;
                        yuv_negate_v1_decode(sourceYRow[x + offsetX], u, v, &pixelRed, &pixelGreen, &pixelBlue);
                        pixelRed = (uint8_t)(255 - pixelRed);
                        pixelGreen = (uint8_t)(255 - pixelGreen);
                        pixelBlue = (uint8_t)(255 - pixelBlue);
                        destinationYRow[x + offsetX] = yuv_negate_v1_encode_y(pixelRed, pixelGreen, pixelBlue);
                        red += pixelRed;
                        green += pixelGreen;
                        blue += pixelBlue;
                        count++;
                    }
                }
                uint8_t averageRed = (uint8_t)(red / count);
                uint8_t averageGreen = (uint8_t)(green / count);
                uint8_t averageBlue = (uint8_t)(blue / count);
                if (source->format == YUV_VIEW_FORMAT_I420) {
                    destinationU[(size_t)blockY * chromaWidth + blockX] =
                        yuv_negate_v1_encode_u(averageRed, averageGreen, averageBlue);
                    destinationV[(size_t)blockY * chromaWidth + blockX] =
                        yuv_negate_v1_encode_v(averageRed, averageGreen, averageBlue);
                } else {
                    uint8_t *destinationUv = destinationU + (size_t)blockY * chromaWidth * 2 + blockX * 2;
                    destinationUv[0] = yuv_negate_v1_encode_u(averageRed, averageGreen, averageBlue);
                    destinationUv[1] = yuv_negate_v1_encode_v(averageRed, averageGreen, averageBlue);
                }
            }
        }
        return;
    }

    size_t lumaBytes = (size_t)width * height;
    size_t chromaBytes = (size_t)chromaWidth * chromaHeight;
    memcpy(destinationY, sourceY, lumaBytes);
    memcpy(destinationU, sourceU, source->format == YUV_VIEW_FORMAT_I420 ? chromaBytes : chromaBytes * 2);
    if (source->format == YUV_VIEW_FORMAT_I420) {
        memcpy(destinationV, sourceV, chromaBytes);
    }

    uint32_t left = region->left;
    uint32_t top = region->top;
    uint32_t right = region->right;
    uint32_t bottom = region->bottom;
    for (uint32_t y = top; y < bottom; y++) {
        const uint8_t *sourceYRow = sourceY + (size_t)y * width;
        uint8_t *destinationYRow = destinationY + (size_t)y * width;
        uint32_t chromaY = y / 2;
        const uint8_t *sourceURow = sourceU + (size_t)chromaY * (source->format == YUV_VIEW_FORMAT_I420 ? chromaWidth : chromaWidth * 2);
        const uint8_t *sourceVRow = source->format == YUV_VIEW_FORMAT_I420 ? sourceV + (size_t)chromaY * chromaWidth : NULL;
        for (uint32_t x = left; x < right; x++) {
            uint32_t chromaX = x / 2;
            uint8_t u = source->format == YUV_VIEW_FORMAT_I420 ? sourceURow[chromaX] : sourceURow[chromaX * 2];
            uint8_t v = source->format == YUV_VIEW_FORMAT_I420 ? sourceVRow[chromaX] : sourceURow[chromaX * 2 + 1];
            uint8_t red;
            uint8_t green;
            uint8_t blue;
            yuv_negate_v1_decode(sourceYRow[x], u, v, &red, &green, &blue);
            destinationYRow[x] = yuv_negate_v1_encode_y((uint8_t)(255 - red), (uint8_t)(255 - green), (uint8_t)(255 - blue));
        }
    }

    for (uint32_t blockY = 0; blockY < chromaHeight; blockY++) {
        uint32_t y = blockY * 2;
        for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
            uint32_t x = blockX * 2;
            if (region->enabled && (x >= region->right || y >= region->bottom || x + 2 <= region->left || y + 2 <= region->top)) {
                continue;
            }

            const uint8_t *sourceURow = sourceU + (size_t)blockY * (source->format == YUV_VIEW_FORMAT_I420 ? chromaWidth : chromaWidth * 2);
            const uint8_t *sourceVRow = source->format == YUV_VIEW_FORMAT_I420 ? sourceV + (size_t)blockY * chromaWidth : NULL;
            uint8_t u = source->format == YUV_VIEW_FORMAT_I420 ? sourceURow[blockX] : sourceURow[blockX * 2];
            uint8_t v = source->format == YUV_VIEW_FORMAT_I420 ? sourceVRow[blockX] : sourceURow[blockX * 2 + 1];
            uint32_t red = 0;
            uint32_t green = 0;
            uint32_t blue = 0;
            uint32_t count = 0;
            for (uint32_t offsetY = 0; offsetY < 2 && y + offsetY < height; offsetY++) {
                for (uint32_t offsetX = 0; offsetX < 2 && x + offsetX < width; offsetX++) {
                    uint8_t pixelRed;
                    uint8_t pixelGreen;
                    uint8_t pixelBlue;
                    yuv_negate_v1_decode(sourceY[(size_t)(y + offsetY) * width + x + offsetX], u, v,
                        &pixelRed, &pixelGreen, &pixelBlue);
                    if (yuv_negate_v1_region_contains(region, x + offsetX, y + offsetY)) {
                        pixelRed = (uint8_t)(255 - pixelRed);
                        pixelGreen = (uint8_t)(255 - pixelGreen);
                        pixelBlue = (uint8_t)(255 - pixelBlue);
                    }
                    red += pixelRed;
                    green += pixelGreen;
                    blue += pixelBlue;
                    count++;
                }
            }
            uint8_t averageRed = (uint8_t)(red / count);
            uint8_t averageGreen = (uint8_t)(green / count);
            uint8_t averageBlue = (uint8_t)(blue / count);
            if (source->format == YUV_VIEW_FORMAT_I420) {
                destinationU[(size_t)blockY * chromaWidth + blockX] = yuv_negate_v1_encode_u(averageRed, averageGreen, averageBlue);
                destinationV[(size_t)blockY * chromaWidth + blockX] = yuv_negate_v1_encode_v(averageRed, averageGreen, averageBlue);
            } else {
                uint8_t *destinationUv = destinationU + (size_t)blockY * chromaWidth * 2 + blockX * 2;
                destinationUv[0] = yuv_negate_v1_encode_u(averageRed, averageGreen, averageBlue);
                destinationUv[1] = yuv_negate_v1_encode_v(averageRed, averageGreen, averageBlue);
            }
        }
    }
}

FFI_PLUGIN_EXPORT YuvStatus yuv_negate_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvEffectOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0 || options->reserved[1] != 0) {
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
    if (yuv_negate_v1_is_tight_bgra(&sourceView, &destinationView)) {
        yuv_negate_v1_apply_tight_bgra(&sourceView, &destinationView, &region);
    } else if (yuv_negate_v1_is_tight_420(&sourceView, &destinationView)) {
        yuv_negate_v1_apply_tight_420(&sourceView, &destinationView, &region);
    } else {
        yuv_kernel_v1_apply_effect(&sourceView, &destinationView, &region, yuv_negate_v1_effect, NULL);
    }

    return YUV_STATUS_OK;
}
