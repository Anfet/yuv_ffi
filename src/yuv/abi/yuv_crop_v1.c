#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/*
 * Crop to the destination geometry named by the options rectangle.
 *
 * Unlike every other operation the destination is NOT source-sized: it is
 * exactly options->width x options->height, and the rectangle must lie inside
 * the source frame.
 */
typedef struct {
    uint32_t left;
    uint32_t top;
} YuvCropContextV1;

static void yuv_crop_v1_map(
    void *context, uint32_t destinationX, uint32_t destinationY, uint32_t *outSourceX, uint32_t *outSourceY) {
    const YuvCropContextV1 *crop = (const YuvCropContextV1 *)context;
    *outSourceX = crop->left + destinationX;
    *outSourceY = crop->top + destinationY;
}

static int yuv_crop_v1_plane_is_tightly_packed(
    const YuvValidatedConstPlaneIn *source,
    const YuvValidatedMutablePlaneIn *destination,
    uint32_t sourceWidth,
    uint32_t destinationWidth) {
    uint64_t sourceRowBytes = (uint64_t)sourceWidth * source->sampleBytes;
    uint64_t destinationRowBytes = (uint64_t)destinationWidth * destination->sampleBytes;
    return source->pixelStride == source->sampleBytes && destination->pixelStride == destination->sampleBytes
        && source->sampleBytes == destination->sampleBytes && source->rowStride == sourceRowBytes
        && destination->rowStride == destinationRowBytes;
}

static uint8_t yuv_crop_v1_clip(int32_t value) {
    if (value < 0) return 0;
    if (value > 255) return 255;
    return (uint8_t)value;
}

static void yuv_crop_v1_reencode_chroma(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    uint32_t left,
    uint32_t top) {
    uint32_t chromaWidth = (destination->width + 1) / 2;
    uint32_t chromaHeight = (destination->height + 1) / 2;
    const uint8_t *sourceY = (const uint8_t *)source->planes[0].data;
    const uint8_t *sourceU = (const uint8_t *)source->planes[1].data;
    const uint8_t *sourceV = source->format == YUV_VIEW_FORMAT_I420 ? (const uint8_t *)source->planes[2].data : NULL;
    uint8_t *destinationU = (uint8_t *)destination->planes[1].data;
    uint8_t *destinationV = destination->format == YUV_VIEW_FORMAT_I420 ? (uint8_t *)destination->planes[2].data : NULL;
    uint32_t sourceChromaWidth = (source->width + 1) / 2;

    for (uint32_t blockY = 0; blockY < chromaHeight; blockY++) {
        for (uint32_t blockX = 0; blockX < chromaWidth; blockX++) {
            uint32_t red = 0;
            uint32_t green = 0;
            uint32_t blue = 0;
            uint32_t count = 0;
            for (uint32_t offsetY = 0; offsetY < 2; offsetY++) {
                uint32_t destinationY = blockY * 2 + offsetY;
                if (destinationY >= destination->height) continue;
                for (uint32_t offsetX = 0; offsetX < 2; offsetX++) {
                    uint32_t destinationX = blockX * 2 + offsetX;
                    if (destinationX >= destination->width) continue;
                    uint32_t sourceX = left + destinationX;
                    uint32_t sourceYIndex = top + destinationY;
                    uint32_t sourceChromaIndex = (sourceYIndex / 2) * sourceChromaWidth + sourceX / 2;
                    uint8_t y = sourceY[(size_t)sourceYIndex * source->width + sourceX];
                    uint8_t u = sourceU[sourceChromaIndex * source->planes[1].sampleBytes];
                    uint8_t v = sourceV == NULL ? sourceU[sourceChromaIndex * 2 + 1] : sourceV[sourceChromaIndex];
                    int32_t c = (int32_t)y - 16;
                    int32_t d = (int32_t)u - 128;
                    int32_t e = (int32_t)v - 128;
                    red += yuv_crop_v1_clip((298 * c + 409 * e + 128) >> 8);
                    green += yuv_crop_v1_clip((298 * c - 100 * d - 208 * e + 128) >> 8);
                    blue += yuv_crop_v1_clip((298 * c + 516 * d + 128) >> 8);
                    count++;
                }
            }
            uint8_t averageRed = (uint8_t)(red / count);
            uint8_t averageGreen = (uint8_t)(green / count);
            uint8_t averageBlue = (uint8_t)(blue / count);
            uint8_t u = yuv_crop_v1_clip(((-38 * (int32_t)averageRed - 74 * (int32_t)averageGreen
                + 112 * (int32_t)averageBlue + 128) >> 8) + 128);
            uint8_t v = yuv_crop_v1_clip(((112 * (int32_t)averageRed - 94 * (int32_t)averageGreen
                - 18 * (int32_t)averageBlue + 128) >> 8) + 128);
            size_t destinationChromaIndex = (size_t)blockY * chromaWidth + blockX;
            if (destinationV == NULL) {
                destinationU[destinationChromaIndex * 2] = u;
                destinationU[destinationChromaIndex * 2 + 1] = v;
            } else {
                destinationU[destinationChromaIndex] = u;
                destinationV[destinationChromaIndex] = v;
            }
        }
    }
}

static int yuv_crop_v1_tightly_packed(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    uint32_t left,
    uint32_t top,
    int blockAligned) {
    for (uint32_t planeIndex = 0; planeIndex < source->planeCount; planeIndex++) {
        uint32_t sourceWidth = source->width;
        uint32_t destinationWidth = destination->width;
        if (planeIndex > 0) {
            sourceWidth = (sourceWidth + 1) / 2;
            destinationWidth = (destinationWidth + 1) / 2;
        }
        if (!yuv_crop_v1_plane_is_tightly_packed(
                &source->planes[planeIndex], &destination->planes[planeIndex], sourceWidth, destinationWidth)) {
            return 0;
        }
    }

    for (uint32_t y = 0; y < destination->height; y++) {
        const uint8_t *from = (const uint8_t *)source->planes[0].data + (size_t)(top + y) * source->planes[0].rowStride
            + (size_t)left * source->planes[0].sampleBytes;
        uint8_t *to = (uint8_t *)destination->planes[0].data + (size_t)y * destination->planes[0].rowStride;
        memcpy(to, from, (size_t)destination->width * destination->planes[0].sampleBytes);
    }

    if (!yuv_kernel_v1_is_420(source->format)) return 1;
    if (!blockAligned) {
        yuv_crop_v1_reencode_chroma(source, destination, left, top);
        return 1;
    }

    uint32_t destinationChromaWidth = (destination->width + 1) / 2;
    uint32_t destinationChromaHeight = (destination->height + 1) / 2;
    uint32_t sourceChromaLeft = left / 2;
    uint32_t sourceChromaTop = top / 2;
    for (uint32_t planeIndex = 1; planeIndex < source->planeCount; planeIndex++) {
        uint32_t sampleBytes = source->planes[planeIndex].sampleBytes;
        size_t rowBytes = (size_t)destinationChromaWidth * sampleBytes;
        for (uint32_t y = 0; y < destinationChromaHeight; y++) {
            const uint8_t *from = (const uint8_t *)source->planes[planeIndex].data
                + (size_t)(sourceChromaTop + y) * source->planes[planeIndex].rowStride
                + (size_t)sourceChromaLeft * sampleBytes;
            uint8_t *to = (uint8_t *)destination->planes[planeIndex].data
                + (size_t)y * destination->planes[planeIndex].rowStride;
            memcpy(to, from, rowBytes);
        }
    }
    return 1;
}

FFI_PLUGIN_EXPORT YuvStatus yuv_crop_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvCropOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvCropOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* An empty crop is handled as a Dart no-op before dispatch, so reaching C
     * with a zero extent means the caller bypassed that path with a rectangle
     * that has no pixels to produce. */
    if (options->width == 0 || options->height == 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (options->left < 0 || options->top < 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView sourceView;
    YuvValidatedMutableFrameView destinationView;
    YuvStatus framesStatus = yuv_validate_v1_frames(source, destination, YUV_GEOMETRY_V1_EXPLICIT,
        options->width, options->height, &sourceView, &destinationView);
    if (framesStatus != YUV_STATUS_OK) {
        return framesStatus;
    }

    YuvStatus pairStatus = yuv_validate_v1_format_pair(
        sourceView.format, destinationView.format, YUV_SAME_FORMAT_PAIRS_V1, 3);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    /* The rectangle must fit inside the source. Computed in int64_t so the sum
     * cannot wrap before it is compared: each operand is bounded by INT32_MAX
     * on its own, but their sum is not. */
    if ((int64_t)options->left + (int64_t)options->width > (int64_t)sourceView.width) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if ((int64_t)options->top + (int64_t)options->height > (int64_t)sourceView.height) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Section 14 Q2: an odd crop origin puts the destination luma grid out of
     * phase with the source 2x2 chroma blocks, so destination chroma has to be
     * recomputed from the visible footprint.
     *
     * An even origin is necessary but not sufficient. A destination chroma
     * sample is the average of the pixels that actually exist in its 2x2
     * footprint, so a copy is only correct when the destination block is
     * clipped exactly as the source block it copies from. With an odd
     * destination extent the trailing block holds 1 or 2 pixels while the
     * source block it maps to holds 4, and copying it carries the wrong
     * average -- on differing colours that is several LSB, not a rounding
     * artefact. The exception is a crop running to the source edge, where the
     * source block is clipped identically.
     *
     * This condition was checked exhaustively against the footprint rule for
     * every crop of every frame up to 9x9. */
    uint32_t right = (uint32_t)options->left + options->width;
    uint32_t bottom = (uint32_t)options->top + options->height;
    int blockAligned = (options->left % 2) == 0 && (options->top % 2) == 0 &&
        ((options->width % 2) == 0 || right == sourceView.width) &&
        ((options->height % 2) == 0 || bottom == sourceView.height);

    YuvCropContextV1 context;
    context.left = (uint32_t)options->left;
    context.top = (uint32_t)options->top;

    if (yuv_crop_v1_tightly_packed(&sourceView, &destinationView, context.left, context.top, blockAligned)) {
        return YUV_STATUS_OK;
    }

    yuv_kernel_v1_transform(&sourceView, &destinationView, yuv_crop_v1_map, &context, blockAligned);

    return YUV_STATUS_OK;
}
