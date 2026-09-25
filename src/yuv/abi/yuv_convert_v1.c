#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/* The validated views guarantee that every active sample address fits its
 * plane. Work from row pointers here so conversion does not repeat checked
 * arithmetic and callback dispatch for every pixel. */
static const uint8_t *yuv_convert_const_at(
    const YuvValidatedConstPlaneIn *plane, uint32_t x, uint32_t y) {
    return (const uint8_t *)plane->data + (uint64_t)y * plane->rowStride + (uint64_t)x * plane->pixelStride;
}

static uint8_t *yuv_convert_mutable_at(
    const YuvValidatedMutablePlaneIn *plane, uint32_t x, uint32_t y) {
    return (uint8_t *)plane->data + (uint64_t)y * plane->rowStride + (uint64_t)x * plane->pixelStride;
}

static void yuv_convert_copy_plane(
    const YuvValidatedConstPlaneIn *source, const YuvValidatedMutablePlaneIn *destination,
    uint32_t width, uint32_t height) {
    const uint32_t bytes = source->sampleBytes;
    for (uint32_t y = 0; y < height; y++) {
        const uint8_t *from = yuv_convert_const_at(source, 0, y);
        uint8_t *to = yuv_convert_mutable_at(destination, 0, y);
        if (source->pixelStride == bytes && destination->pixelStride == bytes &&
            (uint64_t)width * bytes <= SIZE_MAX) {
            memcpy(to, from, (size_t)width * bytes);
        } else {
            for (uint32_t x = 0; x < width; x++) {
                memcpy(to + (uint64_t)x * destination->pixelStride,
                    from + (uint64_t)x * source->pixelStride, bytes);
            }
        }
    }
}

static void yuv_convert_copy(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    for (uint32_t plane = 0; plane < source->planeCount; plane++) {
        uint32_t width = plane == 0 ? source->width : (source->width + 1u) / 2u;
        uint32_t height = plane == 0 ? source->height : (source->height + 1u) / 2u;
        yuv_convert_copy_plane(&source->planes[plane], &destination->planes[plane], width, height);
    }
}

static void yuv_convert_relayout(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    yuv_convert_copy_plane(&source->planes[0], &destination->planes[0], source->width, source->height);
    const uint32_t chromaWidth = (source->width + 1u) / 2u;
    const uint32_t chromaHeight = (source->height + 1u) / 2u;
    for (uint32_t y = 0; y < chromaHeight; y++) {
        for (uint32_t x = 0; x < chromaWidth; x++) {
            if (source->format == YUV_VIEW_FORMAT_I420) {
                uint8_t *uv = yuv_convert_mutable_at(&destination->planes[1], x, y);
                uv[0] = *yuv_convert_const_at(&source->planes[1], x, y);
                uv[1] = *yuv_convert_const_at(&source->planes[2], x, y);
            } else {
                const uint8_t *uv = yuv_convert_const_at(&source->planes[1], x, y);
                *yuv_convert_mutable_at(&destination->planes[1], x, y) = uv[0];
                *yuv_convert_mutable_at(&destination->planes[2], x, y) = uv[1];
            }
        }
    }
}

static uint8_t yuv_convert_clip(int32_t value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return (uint8_t)value;
}

static void yuv_convert_to_bgra(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    const int packed = source->format == YUV_VIEW_FORMAT_RGBA8888;
    for (uint32_t y = 0; y < source->height; y++) {
        const uint8_t *sourceRow = yuv_convert_const_at(&source->planes[0], 0, y);
        uint8_t *destinationRow = yuv_convert_mutable_at(&destination->planes[0], 0, y);
        const uint8_t *chromaU = packed ? NULL : yuv_convert_const_at(&source->planes[1], 0, y / 2u);
        const uint8_t *chromaV = !packed && source->format == YUV_VIEW_FORMAT_I420
            ? yuv_convert_const_at(&source->planes[2], 0, y / 2u) : NULL;
        for (uint32_t x = 0; x < source->width; x++) {
            uint8_t *to = destinationRow + (uint64_t)x * destination->planes[0].pixelStride;
            if (packed) {
                const uint8_t *from = sourceRow + (uint64_t)x * source->planes[0].pixelStride;
                to[0] = from[2];
                to[1] = from[1];
                to[2] = from[0];
                to[3] = from[3];
            } else {
                const uint8_t yy = sourceRow[(uint64_t)x * source->planes[0].pixelStride];
                const uint32_t cx = x / 2u;
                int32_t u;
                int32_t v;
                if (source->format == YUV_VIEW_FORMAT_I420) {
                    u = chromaU[(uint64_t)cx * source->planes[1].pixelStride];
                    v = chromaV[(uint64_t)cx * source->planes[2].pixelStride];
                } else {
                    const uint8_t *uv = chromaU + (uint64_t)cx * source->planes[1].pixelStride;
                    u = uv[0];
                    v = uv[1];
                }
                const int32_t c = (int32_t)yy - 16;
                const int32_t d = u - 128;
                const int32_t e = v - 128;
                to[0] = yuv_convert_clip((298 * c + 516 * d + 128) >> 8);
                to[1] = yuv_convert_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
                to[2] = yuv_convert_clip((298 * c + 409 * e + 128) >> 8);
                to[3] = 255;
            }
        }
    }
}

static void yuv_convert_from_packed(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    const uint32_t width = source->width;
    const uint32_t height = source->height;
    const uint32_t redOffset = source->format == YUV_VIEW_FORMAT_BGRA8888 ? 2u : 0u;
    const uint32_t blueOffset = 2u - redOffset;
    const uint32_t sourceStride = source->planes[0].pixelStride;
    const uint32_t lumaStride = destination->planes[0].pixelStride;
    const uint32_t chromaWidth = (width + 1u) / 2u;
    const uint32_t chromaHeight = (height + 1u) / 2u;
#define YUV_CONVERT_PACKED_SAMPLE(from, to) do { \
        const uint8_t r = (from)[redOffset]; \
        const uint8_t g = (from)[1]; \
        const uint8_t b = (from)[blueOffset]; \
        *(to) = (uint8_t)(((66 * (int32_t)r + 129 * (int32_t)g + 25 * (int32_t)b + 128) >> 8) + 16); \
        red += r; green += g; blue += b; count++; \
    } while (0)
    for (uint32_t by = 0; by < chromaHeight; by++) {
        const uint32_t y0 = by * 2u;
        const uint8_t *source0 = yuv_convert_const_at(&source->planes[0], 0, y0);
        uint8_t *luma0 = yuv_convert_mutable_at(&destination->planes[0], 0, y0);
        const uint8_t *source1 = y0 + 1u < height ? yuv_convert_const_at(&source->planes[0], 0, y0 + 1u) : NULL;
        uint8_t *luma1 = y0 + 1u < height ? yuv_convert_mutable_at(&destination->planes[0], 0, y0 + 1u) : NULL;
        uint8_t *chromaU = yuv_convert_mutable_at(&destination->planes[1], 0, by);
        uint8_t *chromaV = destination->format == YUV_VIEW_FORMAT_I420
            ? yuv_convert_mutable_at(&destination->planes[2], 0, by) : NULL;
        const uint32_t chromaStride = destination->planes[1].pixelStride;
        for (uint32_t bx = 0; bx < chromaWidth; bx++) {
            uint32_t red = 0, green = 0, blue = 0, count = 0;
            const uint64_t sourceOffset = (uint64_t)bx * 2u * sourceStride;
            const uint64_t lumaOffset = (uint64_t)bx * 2u * lumaStride;
            YUV_CONVERT_PACKED_SAMPLE(source0 + sourceOffset, luma0 + lumaOffset);
            if (bx * 2u + 1u < width) {
                YUV_CONVERT_PACKED_SAMPLE(source0 + sourceOffset + sourceStride, luma0 + lumaOffset + lumaStride);
            }
            if (source1 != NULL) {
                YUV_CONVERT_PACKED_SAMPLE(source1 + sourceOffset, luma1 + lumaOffset);
                if (bx * 2u + 1u < width) {
                    YUV_CONVERT_PACKED_SAMPLE(source1 + sourceOffset + sourceStride,
                        luma1 + lumaOffset + lumaStride);
                }
            }
            const int32_t r = (int32_t)(red / count);
            const int32_t g = (int32_t)(green / count);
            const int32_t b = (int32_t)(blue / count);
            /* For 8-bit RGB these limited-range formulas stay within 16..240,
             * so the oracle's clip cannot change either result. */
            const uint8_t u = (uint8_t)(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
            const uint8_t v = (uint8_t)(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
            if (destination->format == YUV_VIEW_FORMAT_I420) {
                chromaU[(uint64_t)bx * chromaStride] = u;
                chromaV[(uint64_t)bx * destination->planes[2].pixelStride] = v;
            } else {
                uint8_t *uv = chromaU + (uint64_t)bx * chromaStride;
                uv[0] = u;
                uv[1] = v;
            }
        }
    }
#undef YUV_CONVERT_PACKED_SAMPLE
}

FFI_PLUGIN_EXPORT YuvStatus yuv_convert_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvConvertOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvConvertOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0 || options->reserved[1] != 0 || options->reserved[2] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView sourceView;
    YuvValidatedMutableFrameView destinationView;
    YuvStatus framesStatus = yuv_validate_v1_frames(
        source, destination, YUV_GEOMETRY_V1_SAME, 0, 0, &sourceView, &destinationView);
    if (framesStatus != YUV_STATUS_OK) {
        return framesStatus;
    }

    static const YuvFormatPairV1 convertPairs[12] = {
        {YUV_FORMAT_I420, YUV_FORMAT_I420},
        {YUV_FORMAT_I420, YUV_FORMAT_NV12},
        {YUV_FORMAT_I420, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_NV12, YUV_FORMAT_I420},
        {YUV_FORMAT_NV12, YUV_FORMAT_NV12},
        {YUV_FORMAT_NV12, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_NV12},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_I420},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_NV12},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_BGRA8888},
    };
    YuvStatus pairStatus =
        yuv_validate_v1_format_pair(sourceView.format, destinationView.format, convertPairs, 12);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    if (sourceView.format == destinationView.format) {
        yuv_convert_copy(&sourceView, &destinationView);
    } else if (yuv_kernel_v1_is_420(sourceView.format) && yuv_kernel_v1_is_420(destinationView.format)) {
        yuv_convert_relayout(&sourceView, &destinationView);
    } else if (destinationView.format == YUV_VIEW_FORMAT_BGRA8888) {
        yuv_convert_to_bgra(&sourceView, &destinationView);
    } else {
        yuv_convert_from_packed(&sourceView, &destinationView);
    }
    return YUV_STATUS_OK;
}
