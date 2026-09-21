#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

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
    yuv_kernel_v1_apply_effect(&sourceView, &destinationView, &region, yuv_negate_v1_effect, NULL);

    return YUV_STATUS_OK;
}
