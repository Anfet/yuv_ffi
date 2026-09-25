#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/*
 * Horizontal or vertical flip at identical geometry. Horizontal maps
 * destination (x,y) from source (width-1-x, y); vertical from (x, height-1-y).
 */
/* Reversing an axis of extent n keeps every 2x2 chroma block intact exactly
 * when n is even, or when n is 1 and the reversal is therefore the identity.
 * At any other odd extent a destination block straddles two source blocks. */
static int yuv_axis_reversal_is_block_aligned(uint32_t extent) {
    return (extent % 2) == 0 || extent == 1;
}

typedef struct {
    uint32_t width;
    uint32_t height;
    int horizontal;
} YuvFlipContextV1;

static void yuv_flip_v1_map(
    void *context, uint32_t destinationX, uint32_t destinationY, uint32_t *outSourceX, uint32_t *outSourceY) {
    const YuvFlipContextV1 *flip = (const YuvFlipContextV1 *)context;
    if (flip->horizontal) {
        *outSourceX = flip->width - 1 - destinationX;
        *outSourceY = destinationY;
        return;
    }
    *outSourceX = destinationX;
    *outSourceY = flip->height - 1 - destinationY;
}

static int yuv_flip_v1_plane_is_tightly_packed(
    const YuvValidatedConstPlaneIn *source, const YuvValidatedMutablePlaneIn *destination, uint32_t width) {
    uint64_t rowBytes = (uint64_t)width * source->sampleBytes;
    return source->pixelStride == source->sampleBytes && destination->pixelStride == destination->sampleBytes
        && source->sampleBytes == destination->sampleBytes && source->rowStride == rowBytes
        && destination->rowStride == rowBytes;
}

static void yuv_flip_v1_reverse_row(
    const uint8_t *source, uint8_t *destination, uint32_t sampleCount, uint32_t sampleBytes) {
    for (uint32_t x = 0; x < sampleCount; x++) {
        const uint8_t *from = source + (size_t)(sampleCount - 1 - x) * sampleBytes;
        uint8_t *to = destination + (size_t)x * sampleBytes;
        for (uint32_t byte = 0; byte < sampleBytes; byte++) {
            to[byte] = from[byte];
        }
    }
}

static int yuv_flip_v1_tightly_packed(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    int horizontal) {
    for (uint32_t planeIndex = 0; planeIndex < source->planeCount; planeIndex++) {
        uint32_t planeWidth = source->width;
        uint32_t planeHeight = source->height;
        if (planeIndex > 0) {
            planeWidth = (planeWidth + 1) / 2;
            planeHeight = (planeHeight + 1) / 2;
        }
        if (!yuv_flip_v1_plane_is_tightly_packed(
                &source->planes[planeIndex], &destination->planes[planeIndex], planeWidth)) {
            return 0;
        }

        const uint8_t *sourceBytes = (const uint8_t *)source->planes[planeIndex].data;
        uint8_t *destinationBytes = (uint8_t *)destination->planes[planeIndex].data;
        uint32_t sampleBytes = source->planes[planeIndex].sampleBytes;
        size_t rowBytes = (size_t)planeWidth * sampleBytes;
        for (uint32_t y = 0; y < planeHeight; y++) {
            const uint8_t *from = horizontal ? sourceBytes + (size_t)y * rowBytes
                                             : sourceBytes + (size_t)(planeHeight - 1 - y) * rowBytes;
            uint8_t *to = destinationBytes + (size_t)y * rowBytes;
            if (horizontal) {
                yuv_flip_v1_reverse_row(from, to, planeWidth, sampleBytes);
            } else {
                memcpy(to, from, rowBytes);
            }
        }
    }
    return 1;
}

FFI_PLUGIN_EXPORT YuvStatus yuv_flip_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvFlipOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvFlipOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved0 != 0 || options->reserved[0] != 0 || options->reserved[1] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Exactly one axis. The two constants are not a bit field in ABI v1, so a
     * caller combining them is asking for something this version does not
     * define rather than for both flips at once. */
    if (options->direction != YUV_FLIP_HORIZONTAL && options->direction != YUV_FLIP_VERTICAL) {
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

    /* Only the flipped axis can break block alignment; the other is mapped
     * identically. When it does break, the driver rebuilds chroma from the
     * visible footprint instead of copying a phase-shifted sample. */
    int blockAligned;
    if (options->direction == YUV_FLIP_HORIZONTAL) {
        blockAligned = yuv_axis_reversal_is_block_aligned(sourceView.width);
    } else {
        blockAligned = yuv_axis_reversal_is_block_aligned(sourceView.height);
    }

    YuvFlipContextV1 context;
    context.width = sourceView.width;
    context.height = sourceView.height;
    context.horizontal = options->direction == YUV_FLIP_HORIZONTAL;

    if ((!yuv_kernel_v1_is_420(sourceView.format) || blockAligned)
        && yuv_flip_v1_tightly_packed(&sourceView, &destinationView, context.horizontal)) {
        return YUV_STATUS_OK;
    }

    /* Destination-driven, so every destination sample is written exactly once
     * and nothing needs a scratch buffer: the legacy vertical flip allocated
     * one and could leave a half-mutated frame when that allocation failed.
     * With no allocation there is no failure to be atomic about, and the
     * prologue has already proven the two frames do not overlap. */
    yuv_kernel_v1_transform(&sourceView, &destinationView, yuv_flip_v1_map, &context, blockAligned);

    return YUV_STATUS_OK;
}
