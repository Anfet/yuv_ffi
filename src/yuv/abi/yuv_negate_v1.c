#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"

/*
 * Visible RGB negate: each channel becomes 255 - channel, with alpha preserved.
 * I420->I420, NV12->NV12, BGRA->BGRA at identical geometry.
 */
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

    /* Validation is complete and both descriptors are sound, but the pixel
     * kernel for this operation has not landed yet -- YUV-22 owns it.
     * Returning INTERNAL_ERROR without writing a single destination byte is
     * what keeps the atomicity contract honest in the meantime: a caller sees
     * a clean failure, never a half-written frame.
     *
     * YUV-36b deliberately ships the ABI surface and its validation ahead of
     * the kernels, so that the status contract, the Dart exception mapping,
     * and the WASM symbol table can be built and tested against a signature
     * that will not move. Replace this with the real kernel -- never with a
     * bare YUV_STATUS_OK, which would report success for an untouched frame.
     */
    return YUV_STATUS_INTERNAL_ERROR;
}
