#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

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

    yuv_kernel_v1_transform(&sourceView, &destinationView, yuv_crop_v1_map, &context, blockAligned);

    return YUV_STATUS_OK;
}
