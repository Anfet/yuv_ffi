#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"

/*
 * Horizontal or vertical flip at identical geometry. Horizontal maps
 * destination (x,y) from source (width-1-x, y); vertical from (x, height-1-y).
 */
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

    /* Validation is complete and both descriptors are sound, but the flip kernel
     * has not landed yet -- YUV-31 owns it. Returning INTERNAL_ERROR without
     * writing a single destination byte keeps the atomicity contract honest in
     * the meantime: a caller sees a clean failure, never a half-written frame.
     *
     * Replace this with the real kernel -- never with a bare YUV_STATUS_OK,
     * which would report success for an untouched frame.
     */
    return YUV_STATUS_INTERNAL_ERROR;
}
