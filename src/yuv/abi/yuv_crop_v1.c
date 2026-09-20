#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"

/*
 * Crop to the destination geometry named by the options rectangle.
 *
 * Unlike every other operation the destination is NOT source-sized: it is
 * exactly options->width x options->height, and the rectangle must lie inside
 * the source frame.
 */
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

    /* Validation is complete and both descriptors are sound, but the crop kernel
     * has not landed yet -- YUV-31 owns it. Returning INTERNAL_ERROR without
     * writing a single destination byte keeps the atomicity contract honest in
     * the meantime: a caller sees a clean failure, never a half-written frame.
     *
     * Replace this with the real kernel -- never with a bare YUV_STATUS_OK,
     * which would report success for an untouched frame.
     */
    return YUV_STATUS_INTERNAL_ERROR;
}
