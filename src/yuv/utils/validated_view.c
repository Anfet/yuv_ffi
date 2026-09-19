#include "h/validated_view.h"
#include "h/checked_arithmetic.h"

#include <stdint.h>
#include <limits.h>

YuvValidatedConstPlaneIn yuv_validated_view_zero_plane_in(void) {
    YuvValidatedConstPlaneIn zero = {0, 0, 0, 0, NULL};
    return zero;
}

YuvValidatedMutablePlaneIn yuv_validated_view_zero_plane_mutable_in(void) {
    YuvValidatedMutablePlaneIn zero = {0, 0, 0, 0, NULL};
    return zero;
}

uint32_t yuv_validated_view_plane_count(uint32_t format) {
    switch (format) {
        case YUV_VIEW_FORMAT_I420:
            return 3;
        case YUV_VIEW_FORMAT_NV12:
            return 2;
        case YUV_VIEW_FORMAT_BGRA8888:
        case YUV_VIEW_FORMAT_RGBA8888:
            return 1;
        default:
            return 0;
    }
}

YuvViewStatus yuv_validated_view_plane_geometry(
    uint32_t format,
    uint32_t planeIndex,
    uint32_t width,
    uint32_t height,
    uint32_t *outPlaneWidth,
    uint32_t *outPlaneHeight) {
    if (outPlaneWidth == NULL || outPlaneHeight == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    uint32_t planeCount = yuv_validated_view_plane_count(format);
    if (planeCount == 0 || planeIndex >= planeCount) {
        return YUV_VIEW_UNSUPPORTED_FORMAT;
    }

    /* Plane 0 (Y, or the single packed RGBA/BGRA plane) is always full
     * frame geometry. Chroma planes (I420 U/V, NV12 UV) use ceil(w/2) x
     * ceil(h/2) per section 11's format matrix. */
    if (planeIndex == 0) {
        *outPlaneWidth = width;
        *outPlaneHeight = height;
        return YUV_VIEW_OK;
    }

    YuvSizeResult chromaWidth = yuv_checked_ceil_half((size_t)width);
    YuvSizeResult chromaHeight = yuv_checked_ceil_half((size_t)height);
    if (!chromaWidth.success || !chromaHeight.success) {
        return YUV_VIEW_OVERFLOW;
    }

    *outPlaneWidth = (uint32_t)chromaWidth.value;
    *outPlaneHeight = (uint32_t)chromaHeight.value;
    return YUV_VIEW_OK;
}

YuvViewStatus yuv_validated_view_plane_sample_layout(
    uint32_t format,
    uint32_t planeIndex,
    uint32_t *outSampleBytes,
    uint32_t *outMinPixelStride) {
    if (outSampleBytes == NULL || outMinPixelStride == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    uint32_t planeCount = yuv_validated_view_plane_count(format);
    if (planeCount == 0 || planeIndex >= planeCount) {
        return YUV_VIEW_UNSUPPORTED_FORMAT;
    }

    switch (format) {
        case YUV_VIEW_FORMAT_I420:
            /* Y, U, V: sampleBytes=1, minPixelStride=1 for every plane. */
            *outSampleBytes = 1;
            *outMinPixelStride = 1;
            return YUV_VIEW_OK;

        case YUV_VIEW_FORMAT_NV12:
            if (planeIndex == 0) {
                /* Y: sampleBytes=1, minPixelStride=1. */
                *outSampleBytes = 1;
                *outMinPixelStride = 1;
            } else {
                /* UV interleaved: sampleBytes=2, minPixelStride=2. */
                *outSampleBytes = 2;
                *outMinPixelStride = 2;
            }
            return YUV_VIEW_OK;

        case YUV_VIEW_FORMAT_BGRA8888:
        case YUV_VIEW_FORMAT_RGBA8888:
            /* Single packed plane: sampleBytes=4, minPixelStride=4. */
            *outSampleBytes = 4;
            *outMinPixelStride = 4;
            return YUV_VIEW_OK;

        default:
            return YUV_VIEW_UNSUPPORTED_FORMAT;
    }
}

/*
 * Shared validation body for one plane's stride/span rules (section 11):
 *   rowStride >= (planeWidth - 1) * pixelStride + sampleBytes
 *   length    >= (planeHeight - 1) * rowStride +
 *                (planeWidth - 1) * pixelStride + sampleBytes
 * Implemented entirely through yuv_checked_plane_span()/yuv_checked_plane_size()
 * (never raw `*`/`+`), per Architect Decision #1/#2.
 */
static YuvViewStatus yuv_validated_view_check_plane_geometry(
    uint32_t planeWidth,
    uint32_t planeHeight,
    uint32_t pixelStride,
    uint32_t sampleBytes,
    uint32_t minPixelStride,
    uint64_t rowStride,
    uint64_t length,
    const void *data) {
    if (data == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }
    if (sampleBytes == 0 || pixelStride < minPixelStride) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    YuvSizeResult minSpan = yuv_checked_plane_span(planeWidth, pixelStride, sampleBytes);
    if (!minSpan.success) {
        return YUV_VIEW_OVERFLOW;
    }
    if (rowStride > SIZE_MAX || (uint64_t)(size_t)rowStride != rowStride) {
        return YUV_VIEW_OVERFLOW;
    }
    if ((size_t)rowStride < minSpan.value) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    YuvSizeResult minSize = yuv_checked_plane_size(planeHeight, (size_t)rowStride, minSpan.value);
    if (!minSize.success) {
        return YUV_VIEW_OVERFLOW;
    }
    if (length > SIZE_MAX || (uint64_t)(size_t)length != length) {
        return YUV_VIEW_OVERFLOW;
    }
    if ((size_t)length < minSize.value) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    return YUV_VIEW_OK;
}

static int yuv_validated_view_geometry_in_range(uint32_t width, uint32_t height) {
    return width >= 1 && height >= 1 && width <= (uint32_t)INT32_MAX && height <= (uint32_t)INT32_MAX;
}

YuvViewStatus yuv_validated_view_build_const_frame(
    uint32_t format,
    uint32_t width,
    uint32_t height,
    const YuvValidatedConstPlaneIn *planes,
    uint32_t planesLength,
    YuvValidatedConstFrameView *out) {
    if (out == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView zeroed = {0, 0, 0, 0,
        {yuv_validated_view_zero_plane_in(), yuv_validated_view_zero_plane_in(), yuv_validated_view_zero_plane_in()}};
    *out = zeroed;

    uint32_t planeCount = yuv_validated_view_plane_count(format);
    if (planeCount == 0) {
        return YUV_VIEW_UNSUPPORTED_FORMAT;
    }
    if (!yuv_validated_view_geometry_in_range(width, height)) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }
    if (planes == NULL || planesLength < planeCount) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    for (uint32_t i = 0; i < planeCount; i++) {
        uint32_t planeWidth = 0;
        uint32_t planeHeight = 0;
        YuvViewStatus geometryStatus =
            yuv_validated_view_plane_geometry(format, i, width, height, &planeWidth, &planeHeight);
        if (geometryStatus != YUV_VIEW_OK) {
            return geometryStatus;
        }

        uint32_t sampleBytes = 0;
        uint32_t minPixelStride = 0;
        YuvViewStatus layoutStatus =
            yuv_validated_view_plane_sample_layout(format, i, &sampleBytes, &minPixelStride);
        if (layoutStatus != YUV_VIEW_OK) {
            return layoutStatus;
        }

        const YuvValidatedConstPlaneIn *plane = &planes[i];
        if (plane->sampleBytes != sampleBytes) {
            return YUV_VIEW_INVALID_ARGUMENT;
        }

        YuvViewStatus planeStatus = yuv_validated_view_check_plane_geometry(
            planeWidth, planeHeight, plane->pixelStride, sampleBytes, minPixelStride, plane->rowStride,
            plane->length, plane->data);
        if (planeStatus != YUV_VIEW_OK) {
            return planeStatus;
        }

        out->planes[i] = *plane;
    }

    out->format = format;
    out->planeCount = planeCount;
    out->width = width;
    out->height = height;
    return YUV_VIEW_OK;
}

YuvViewStatus yuv_validated_view_build_mutable_frame(
    uint32_t format,
    uint32_t width,
    uint32_t height,
    const YuvValidatedMutablePlaneIn *planes,
    uint32_t planesLength,
    YuvValidatedMutableFrameView *out) {
    if (out == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    YuvValidatedMutableFrameView zeroed = {0, 0, 0, 0,
        {yuv_validated_view_zero_plane_mutable_in(), yuv_validated_view_zero_plane_mutable_in(),
            yuv_validated_view_zero_plane_mutable_in()}};
    *out = zeroed;

    uint32_t planeCount = yuv_validated_view_plane_count(format);
    if (planeCount == 0) {
        return YUV_VIEW_UNSUPPORTED_FORMAT;
    }
    if (!yuv_validated_view_geometry_in_range(width, height)) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }
    if (planes == NULL || planesLength < planeCount) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }

    for (uint32_t i = 0; i < planeCount; i++) {
        uint32_t planeWidth = 0;
        uint32_t planeHeight = 0;
        YuvViewStatus geometryStatus =
            yuv_validated_view_plane_geometry(format, i, width, height, &planeWidth, &planeHeight);
        if (geometryStatus != YUV_VIEW_OK) {
            return geometryStatus;
        }

        uint32_t sampleBytes = 0;
        uint32_t minPixelStride = 0;
        YuvViewStatus layoutStatus =
            yuv_validated_view_plane_sample_layout(format, i, &sampleBytes, &minPixelStride);
        if (layoutStatus != YUV_VIEW_OK) {
            return layoutStatus;
        }

        const YuvValidatedMutablePlaneIn *plane = &planes[i];
        if (plane->sampleBytes != sampleBytes) {
            return YUV_VIEW_INVALID_ARGUMENT;
        }

        YuvViewStatus planeStatus = yuv_validated_view_check_plane_geometry(
            planeWidth, planeHeight, plane->pixelStride, sampleBytes, minPixelStride, plane->rowStride,
            plane->length, plane->data);
        if (planeStatus != YUV_VIEW_OK) {
            return planeStatus;
        }

        out->planes[i] = *plane;
    }

    out->format = format;
    out->planeCount = planeCount;
    out->width = width;
    out->height = height;
    return YUV_VIEW_OK;
}

YuvViewStatus yuv_validated_view_check_destination_geometry(
    const YuvValidatedMutableFrameView *destination,
    uint32_t expectedWidth,
    uint32_t expectedHeight) {
    if (destination == NULL) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }
    if (destination->width != expectedWidth || destination->height != expectedHeight) {
        return YUV_VIEW_INVALID_ARGUMENT;
    }
    return YUV_VIEW_OK;
}
