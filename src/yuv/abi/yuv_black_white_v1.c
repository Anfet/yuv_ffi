#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

/*
 * Threshold effect: the rounded BT.601 luma of each visible pixel selects white
 * when it is >= 128 and black otherwise. I420->I420, NV12->NV12, BGRA->BGRA at
 * identical geometry.
 */
/* Section 11: the same rounded gray as grayscale, then white when
 * gray >= 128. The boundary is inclusive; the legacy kernel used > 128, which
 * is the single-step difference that put 1 536 pixels 255 apart from the
 * oracle in EFFECT-BLACKWHITE-BGRA8888. */
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
    yuv_kernel_v1_apply_effect(&sourceView, &destinationView, &region, yuv_black_white_v1_effect, NULL);

    return YUV_STATUS_OK;
}
