#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

#include <string.h>

/*
 * Swaps the U and V sample values of an NV12 frame without changing its format.
 * NV12 -> NV12 only, at identical geometry, and only over the whole frame.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_chroma_swap_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
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

    /* NV12 -> NV12 only: swapping U and V is meaningless for a packed RGB
     * format and is not defined for I420 in ABI v1. */
    static const YuvFormatPairV1 nv12Only[1] = {{YUV_FORMAT_NV12, YUV_FORMAT_NV12}};
    YuvStatus pairStatus =
        yuv_validate_v1_format_pair(sourceView.format, destinationView.format, nv12Only, 1);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    /* Regional chroma swap is not a public 0.4.0 operation, so the region
     * must be disabled rather than merely ignored: silently dropping a
     * region the caller set would swap the whole frame they meant to
     * protect. */
    if (options->region.enabled != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    YuvStatus regionStatus = yuv_validate_v1_region(&options->region, sourceView.width, sourceView.height);
    if (regionStatus != YUV_STATUS_OK) {
        return regionStatus;
    }

    const uint32_t chromaWidth = (destinationView.width + 1) / 2;
    const uint32_t chromaHeight = (destinationView.height + 1) / 2;
    const YuvValidatedConstPlaneIn *sourceY = &sourceView.planes[0];
    const YuvValidatedMutablePlaneIn *destinationY = &destinationView.planes[0];
    const YuvValidatedConstPlaneIn *sourceUv = &sourceView.planes[1];
    const YuvValidatedMutablePlaneIn *destinationUv = &destinationView.planes[1];

    if ((uint64_t)sourceView.width * sourceView.height <= SIZE_MAX &&
        (uint64_t)chromaWidth * chromaHeight * 2 <= SIZE_MAX &&
        sourceY->pixelStride == 1 && destinationY->pixelStride == 1 &&
        sourceY->rowStride == sourceView.width && destinationY->rowStride == destinationView.width &&
        sourceUv->pixelStride == 2 && destinationUv->pixelStride == 2 &&
        sourceUv->rowStride == (uint64_t)chromaWidth * 2 &&
        destinationUv->rowStride == (uint64_t)chromaWidth * 2) {
        const size_t lumaBytes = (size_t)sourceView.width * sourceView.height;
        const size_t chromaBytes = (size_t)chromaWidth * chromaHeight * 2;
        const uint8_t *from = (const uint8_t *)sourceY->data;
        uint8_t *to = (uint8_t *)destinationY->data;
        memcpy(to, from, lumaBytes);

        from = (const uint8_t *)sourceUv->data;
        to = (uint8_t *)destinationUv->data;
        for (size_t i = 0; i < chromaBytes; i += 2) {
            const uint8_t u = from[i];
            to[i] = from[i + 1];
            to[i + 1] = u;
        }
        return YUV_STATUS_OK;
    }

    /* Section 14 Q1: a channel-value effect on stored samples, not a format
     * conversion and not a visible-pixel operation. Y is copied byte for byte
     * and each UV pair is written back as (V,U); nothing is decoded to RGB,
     * because a round trip would quantize a frame whose samples the caller
     * only asked to reorder. */
    for (uint32_t y = 0; y < destinationView.height; y++) {
        for (uint32_t x = 0; x < destinationView.width; x++) {
            const uint8_t *from = yuv_kernel_v1_const_sample(&sourceView.planes[0], x, y);
            uint8_t *to = yuv_kernel_v1_mutable_sample(&destinationView.planes[0], x, y);
            if (from == NULL || to == NULL) {
                return YUV_STATUS_OVERFLOW;
            }
            to[0] = from[0];
        }
    }

    for (uint32_t y = 0; y < chromaHeight; y++) {
        for (uint32_t x = 0; x < chromaWidth; x++) {
            const uint8_t *from = yuv_kernel_v1_const_sample(&sourceView.planes[1], x, y);
            uint8_t *to = yuv_kernel_v1_mutable_sample(&destinationView.planes[1], x, y);
            if (from == NULL || to == NULL) {
                return YUV_STATUS_OVERFLOW;
            }
            uint8_t u = from[0];
            uint8_t v = from[1];
            to[0] = v;
            to[1] = u;
        }
    }

    return YUV_STATUS_OK;
}
