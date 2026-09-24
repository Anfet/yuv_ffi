#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <math.h>

/*
 * Normalized box blur: every kernel cell has weight 1/(2*radius+1)^2. Shares its
 * oracle with mean blur, so both must produce the same logical result for the
 * same radius and ROI. Edge-replicate at the border.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_box_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvBlurOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvBlurOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0 || options->reserved[1] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* radius 0 is a defined no-op rather than an error, but a radius past
     * 256 would make the kernel area exceed what the accumulators and the
     * reference oracle are defined for. */
    if (options->radius > 256) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (options->borderMode != YUV_BORDER_CLAMP) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Uniform-weight blur ignores sigma entirely, so a caller that set one
     * has misunderstood which operation they are calling; saying so beats
     * silently producing a differently-blurred frame than they expect. */
    if (options->sigma != 0.0) {
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

    return yuv_kernel_v1_blur(&sourceView, &destinationView, &region, options->radius, NULL);
}
