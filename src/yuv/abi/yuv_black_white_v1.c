#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/*
 * Black-white effect: the rounded visible BT.601 gray selects white at >= 128
 * and black below it. I420->I420, NV12->NV12, BGRA->BGRA at identical geometry.
 * The inclusive boundary is part of the ABI v1 contract.
 */
static YuvRgbaPixelV1 yuv_black_white_v1_effect(void *context, YuvRgbaPixelV1 pixel, uint32_t x, uint32_t y) {
    (void)context;
    (void)x;
    (void)y;
    uint8_t value = yuv_kernel_v1_gray(pixel.r, pixel.g, pixel.b) >= 128 ? 255 : 0;
    pixel.r = value;
    pixel.g = value;
    pixel.b = value;
    return pixel;
}

static int yuv_black_white_v1_plane_is_tightly_packed(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    uint32_t plane,
    uint32_t width,
    uint32_t sampleBytes) {
    uint64_t rowBytes = (uint64_t)width * sampleBytes;
    return source->planes[plane].pixelStride == sampleBytes &&
        destination->planes[plane].pixelStride == sampleBytes &&
        source->planes[plane].rowStride == rowBytes &&
        destination->planes[plane].rowStride == rowBytes &&
        source->planes[plane].data != destination->planes[plane].data;
}

static int yuv_black_white_v1_is_tightly_packed(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination) {
    uint32_t chromaWidth = (source->width + 1) / 2;
    if (source->format == YUV_VIEW_FORMAT_BGRA8888) {
        return yuv_black_white_v1_plane_is_tightly_packed(source, destination, 0, source->width, 4);
    }
    if (!yuv_black_white_v1_plane_is_tightly_packed(source, destination, 0, source->width, 1) ||
        !yuv_black_white_v1_plane_is_tightly_packed(source, destination, 1, chromaWidth,
            source->format == YUV_VIEW_FORMAT_NV12 ? 2 : 1)) {
        return 0;
    }
    return source->format != YUV_VIEW_FORMAT_I420 ||
        yuv_black_white_v1_plane_is_tightly_packed(source, destination, 2, chromaWidth, 1);
}

static uint8_t yuv_black_white_v1_clip(int32_t value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return (uint8_t)value;
}

static uint8_t yuv_black_white_v1_gray(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_black_white_v1_clip(
        (299 * (int32_t)r + 587 * (int32_t)g + 114 * (int32_t)b + 500) / 1000);
}

static uint8_t yuv_black_white_v1_value(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_black_white_v1_gray(r, g, b) >= 128 ? 255 : 0;
}

static uint8_t yuv_black_white_v1_rgb_to_y(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_black_white_v1_clip(((66 * (int32_t)r + 129 * (int32_t)g + 25 * (int32_t)b + 128) >> 8) + 16);
}

static uint8_t yuv_black_white_v1_rgb_to_u(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_black_white_v1_clip(((-38 * (int32_t)r - 74 * (int32_t)g + 112 * (int32_t)b + 128) >> 8) + 128);
}

static uint8_t yuv_black_white_v1_rgb_to_v(uint8_t r, uint8_t g, uint8_t b) {
    return yuv_black_white_v1_clip(((112 * (int32_t)r - 94 * (int32_t)g - 18 * (int32_t)b + 128) >> 8) + 128);
}

static uint8_t yuv_black_white_v1_yuv_gray(uint8_t y, uint8_t u, uint8_t v) {
    int32_t c = (int32_t)y - 16;
    int32_t d = (int32_t)u - 128;
    int32_t e = (int32_t)v - 128;
    uint8_t r = yuv_black_white_v1_clip((298 * c + 409 * e + 128) >> 8);
    uint8_t g = yuv_black_white_v1_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    uint8_t b = yuv_black_white_v1_clip((298 * c + 516 * d + 128) >> 8);
    return yuv_black_white_v1_value(r, g, b);
}

static YuvRgbaPixelV1 yuv_black_white_v1_read_420_pixel(
    const YuvValidatedConstFrameView *source, uint32_t x, uint32_t y) {
    const uint8_t *luma = (const uint8_t *)source->planes[0].data;
    uint32_t chromaWidth = (source->width + 1) / 2;
    uint32_t chromaIndex = (y / 2) * chromaWidth + x / 2;
    uint8_t u;
    uint8_t v;
    if (source->format == YUV_VIEW_FORMAT_I420) {
        u = ((const uint8_t *)source->planes[1].data)[chromaIndex];
        v = ((const uint8_t *)source->planes[2].data)[chromaIndex];
    } else {
        const uint8_t *uv = (const uint8_t *)source->planes[1].data + chromaIndex * 2;
        u = uv[0];
        v = uv[1];
    }
    int32_t c = (int32_t)luma[(size_t)y * source->width + x] - 16;
    int32_t d = (int32_t)u - 128;
    int32_t e = (int32_t)v - 128;
    YuvRgbaPixelV1 pixel;
    pixel.r = yuv_black_white_v1_clip((298 * c + 409 * e + 128) >> 8);
    pixel.g = yuv_black_white_v1_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
    pixel.b = yuv_black_white_v1_clip((298 * c + 516 * d + 128) >> 8);
    pixel.a = 255;
    return pixel;
}

static int yuv_black_white_v1_region_contains(const YuvRegionV1 *region, uint32_t x, uint32_t y) {
    return !region->enabled ||
        (x >= region->left && x < region->right && y >= region->top && y < region->bottom);
}

static void yuv_black_white_v1_apply_bgra(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
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
            uint8_t gray = yuv_black_white_v1_value(from[2], from[1], from[0]);
            to[0] = gray;
            to[1] = gray;
            to[2] = gray;
            to[3] = from[3];
        }
    }
}

static void yuv_black_white_v1_apply_420(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region) {
    const uint8_t *inputLuma = (const uint8_t *)source->planes[0].data;
    uint8_t *outputLuma = (uint8_t *)destination->planes[0].data;
    uint32_t width = source->width;
    uint32_t height = source->height;
    uint32_t chromaWidth = (width + 1) / 2;
    uint32_t chromaHeight = (height + 1) / 2;
    if (!region->enabled) {
        for (uint32_t blockY = 0; blockY < chromaHeight; blockY++) {
            for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
                uint32_t red = 0;
                uint32_t green = 0;
                uint32_t blue = 0;
                uint32_t count = 0;
                uint32_t startX = blockX * 2;
                uint32_t startY = blockY * 2;
                size_t chromaIndex = (size_t)blockY * chromaWidth + blockX;
                uint8_t u;
                uint8_t v;
                if (source->format == YUV_VIEW_FORMAT_I420) {
                    u = ((const uint8_t *)source->planes[1].data)[chromaIndex];
                    v = ((const uint8_t *)source->planes[2].data)[chromaIndex];
                } else {
                    const uint8_t *uv = (const uint8_t *)source->planes[1].data + chromaIndex * 2;
                    u = uv[0];
                    v = uv[1];
                }
                for (uint32_t y = startY; y < startY + 2 && y < height; y++) {
                    for (uint32_t x = startX; x < startX + 2 && x < width; x++) {
                        uint8_t gray = yuv_black_white_v1_yuv_gray(inputLuma[(size_t)y * width + x], u, v);
                        outputLuma[(size_t)y * width + x] = yuv_black_white_v1_rgb_to_y(gray, gray, gray);
                        red += gray;
                        green += gray;
                        blue += gray;
                        count++;
                    }
                }
                uint8_t outputU = yuv_black_white_v1_rgb_to_u((uint8_t)(red / count), (uint8_t)(green / count),
                    (uint8_t)(blue / count));
                uint8_t outputV = yuv_black_white_v1_rgb_to_v((uint8_t)(red / count), (uint8_t)(green / count),
                    (uint8_t)(blue / count));
                if (source->format == YUV_VIEW_FORMAT_I420) {
                    ((uint8_t *)destination->planes[1].data)[chromaIndex] = outputU;
                    ((uint8_t *)destination->planes[2].data)[chromaIndex] = outputV;
                } else {
                    uint8_t *uv = (uint8_t *)destination->planes[1].data + chromaIndex * 2;
                    uv[0] = outputU;
                    uv[1] = outputV;
                }
            }
        }
        return;
    }
    if (region->enabled) {
        memcpy(outputLuma, inputLuma, (size_t)width * height);
        if (source->format == YUV_VIEW_FORMAT_I420) {
            memcpy(destination->planes[1].data, source->planes[1].data, (size_t)chromaWidth * chromaHeight);
            memcpy(destination->planes[2].data, source->planes[2].data, (size_t)chromaWidth * chromaHeight);
        } else {
            memcpy(destination->planes[1].data, source->planes[1].data, (size_t)chromaWidth * chromaHeight * 2);
        }
    }
    uint32_t left = region->enabled ? region->left : 0;
    uint32_t top = region->enabled ? region->top : 0;
    uint32_t right = region->enabled ? region->right : width;
    uint32_t bottom = region->enabled ? region->bottom : height;
    for (uint32_t y = top; y < bottom; y++) {
        for (uint32_t x = left; x < right; x++) {
            uint32_t blockX = (x / 2) * 2;
            uint32_t blockY = (y / 2) * 2;
            if (blockX >= left && blockX + 2 <= right && blockY >= top && blockY + 2 <= bottom) {
                continue;
            }
            YuvRgbaPixelV1 pixel = yuv_black_white_v1_read_420_pixel(source, x, y);
            uint8_t gray = yuv_black_white_v1_value(pixel.r, pixel.g, pixel.b);
            outputLuma[(size_t)y * width + x] = yuv_black_white_v1_rgb_to_y(gray, gray, gray);
        }
    }
    for (uint32_t blockY = 0; blockY < chromaHeight; blockY++) {
        for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
            uint32_t startX = blockX * 2;
            uint32_t startY = blockY * 2;
            int intersects = !region->enabled;
            if (region->enabled) {
                intersects = startX < region->right && startX + 2 > region->left &&
                    startY < region->bottom && startY + 2 > region->top;
            }
            if (!intersects) {
                continue;
            }
            int fullySelected = startX >= left && startX + 2 <= right &&
                startY >= top && startY + 2 <= bottom;
            uint32_t red = 0;
            uint32_t green = 0;
            uint32_t blue = 0;
            uint32_t count = 0;
            for (uint32_t y = startY; y < startY + 2 && y < height; y++) {
                for (uint32_t x = startX; x < startX + 2 && x < width; x++) {
                    YuvRgbaPixelV1 pixel = yuv_black_white_v1_read_420_pixel(source, x, y);
                    if (yuv_black_white_v1_region_contains(region, x, y)) {
                        uint8_t gray = yuv_black_white_v1_value(pixel.r, pixel.g, pixel.b);
                        pixel.r = gray;
                        pixel.g = gray;
                        pixel.b = gray;
                        if (fullySelected) {
                            outputLuma[(size_t)y * width + x] = yuv_black_white_v1_rgb_to_y(gray, gray, gray);
                        }
                    }
                    red += pixel.r;
                    green += pixel.g;
                    blue += pixel.b;
                    count++;
                }
            }
            uint8_t u = yuv_black_white_v1_rgb_to_u((uint8_t)(red / count), (uint8_t)(green / count),
                (uint8_t)(blue / count));
            uint8_t v = yuv_black_white_v1_rgb_to_v((uint8_t)(red / count), (uint8_t)(green / count),
                (uint8_t)(blue / count));
            size_t chromaIndex = (size_t)blockY * chromaWidth + blockX;
            if (source->format == YUV_VIEW_FORMAT_I420) {
                ((uint8_t *)destination->planes[1].data)[chromaIndex] = u;
                ((uint8_t *)destination->planes[2].data)[chromaIndex] = v;
            } else {
                uint8_t *uv = (uint8_t *)destination->planes[1].data + chromaIndex * 2;
                uv[0] = u;
                uv[1] = v;
            }
        }
    }
}

static void yuv_black_white_v1_apply_tightly_packed(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region) {
    if (source->format == YUV_VIEW_FORMAT_BGRA8888) {
        yuv_black_white_v1_apply_bgra(source, destination, region);
        return;
    }
    yuv_black_white_v1_apply_420(source, destination, region);
}

FFI_PLUGIN_EXPORT YuvStatus yuv_black_white_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
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
    if (yuv_black_white_v1_is_tightly_packed(&sourceView, &destinationView)) {
        yuv_black_white_v1_apply_tightly_packed(&sourceView, &destinationView, &region);
    } else {
        yuv_kernel_v1_apply_effect(&sourceView, &destinationView, &region, yuv_black_white_v1_effect, NULL);
    }

    return YUV_STATUS_OK;
}
