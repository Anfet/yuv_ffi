#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"
#include "../utils/h/checked_arithmetic.h"

#include <math.h>
#include <stdlib.h>

/*
 * Gaussian blur with the normalized two-dimensional kernel
 * exp(-(dx^2+dy^2)/(2*sigma^2)) over [-radius, +radius]. Edge-replicate at the
 * border (Engineer decision, 2026-09-20). I420->I420, NV12->NV12, BGRA->BGRA at
 * identical geometry.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_gaussian_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
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

    /* Gaussian weighting is defined only for a finite, strictly positive sigma:
     * zero divides by zero in exp(-(dx^2+dy^2)/(2*sigma^2)), and infinity or
     * NaN poisons every weight in the kernel.
     *
     * The test is written as a positive range check rather than as a chain of
     * negations because NaN compares false against everything: `sigma <= 0.0`
     * would let NaN straight through, while `sigma > 0.0 && sigma < HUGE_VAL`
     * is false for NaN, for infinity, and for zero alike. */
    if (!(options->sigma > 0.0 && options->sigma < HUGE_VAL)) {
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

    /* radius 0 leaves a single-cell kernel of weight 1, which the shared blur
     * path already handles as an exact copy; no weight table is needed. */
    if (options->radius == 0) {
        return yuv_kernel_v1_blur(&sourceView, &destinationView, &region, 0, NULL);
    }

    /* The separable form is not used here: the oracle in section 11 is the
     * two-dimensional kernel exp(-(dx^2+dy^2)/(2*sigma^2)), and matching it
     * exactly matters more than the saved multiplications at the radii this
     * ABI accepts. Weights are left unnormalized because the blur driver
     * divides by their actual sum, which is also what makes edge-replicate
     * come out right. */
    uint32_t side = options->radius * 2 + 1;
    YuvSizeResult cells = yuv_checked_mul((size_t)side, (size_t)side);
    if (!cells.success) {
        return YUV_STATUS_OVERFLOW;
    }
    YuvSizeResult weightBytes = yuv_checked_mul(cells.value, sizeof(double));
    if (!weightBytes.success) {
        return YUV_STATUS_OVERFLOW;
    }

    double *weights = (double *)malloc(weightBytes.value);
    if (weights == NULL) {
        return YUV_STATUS_ALLOCATION_FAILED;
    }

    double denominator = 2.0 * options->sigma * options->sigma;
    for (int32_t offsetY = -(int32_t)options->radius; offsetY <= (int32_t)options->radius; offsetY++) {
        for (int32_t offsetX = -(int32_t)options->radius; offsetX <= (int32_t)options->radius; offsetX++) {
            double squared = (double)(offsetX * offsetX + offsetY * offsetY);
            size_t index = (size_t)(offsetY + (int32_t)options->radius) * side +
                (size_t)(offsetX + (int32_t)options->radius);
            weights[index] = exp(-squared / denominator);
        }
    }

    YuvStatus status = yuv_kernel_v1_blur(&sourceView, &destinationView, &region, options->radius, weights);
    free(weights);
    return status;
}
