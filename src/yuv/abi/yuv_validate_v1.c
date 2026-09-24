#include "h/yuv_validate_v1.h"
#include "../utils/h/checked_arithmetic.h"

#include <stddef.h>
#include <stdint.h>

const YuvFormatPairV1 YUV_SAME_FORMAT_PAIRS_V1[3] = {
    {YUV_FORMAT_I420, YUV_FORMAT_I420},
    {YUV_FORMAT_NV12, YUV_FORMAT_NV12},
    {YUV_FORMAT_BGRA8888, YUV_FORMAT_BGRA8888},
};

YuvStatus yuv_validate_v1_status_from_view(YuvViewStatus status) {
    switch (status) {
        case YUV_VIEW_OK:
            return YUV_STATUS_OK;
        case YUV_VIEW_UNSUPPORTED_FORMAT:
            /* The view layer raises this for an unknown format ID, which the
             * public ABI classifies as a malformed descriptor
             * (INVALID_ARGUMENT), not as UNSUPPORTED_FORMAT -- that status is
             * reserved for a known format in a pairing an operation rejects.
             * Every caller here already screens unknown formats in the frame
             * prefix, so this arm is defensive; translating it to status 2
             * anyway would reintroduce the contract violation by the back
             * door if that ordering ever changed. */
            return YUV_STATUS_INVALID_ARGUMENT;
        case YUV_VIEW_OVERFLOW:
            return YUV_STATUS_OVERFLOW;
        case YUV_VIEW_INVALID_ARGUMENT:
        default:
            /* An unmapped view status is a defect in this translation, not a
             * caller error; report it as invalid argument rather than inventing
             * a success. */
            return YUV_STATUS_INVALID_ARGUMENT;
    }
}

/*
 * I420 and NV12 carry BT.601 limited-range luma/chroma; BGRA and RGBA are
 * already in the display space and declare no matrix or range. Section 9 makes
 * these the ONLY two combinations in ABI v1.
 *
 * The two failure modes are deliberately different statuses, and the order of
 * the checks below is what separates them:
 *
 *   - a value this ABI does not define at all (matrix 99) is an unknown
 *     numeric value, which section 9 groups with null pointers and bad
 *     versions as INVALID_ARGUMENT -- the descriptor is malformed;
 *   - a value this ABI does define, paired with a format it does not go with
 *     (BGRA declaring BT601), is UNSUPPORTED_COLOR -- the descriptor is
 *     well-formed and simply names a combination this version does not
 *     implement.
 *
 * Collapsing the two would tell Dart to raise ArgumentError where the contract
 * calls for UnsupportedError, and vice versa.
 */
static YuvStatus yuv_validate_v1_color(uint32_t format, uint32_t colorMatrix, uint32_t colorRange) {
    if (colorMatrix != YUV_COLOR_MATRIX_NONE && colorMatrix != YUV_COLOR_MATRIX_BT601) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (colorRange != YUV_COLOR_RANGE_NONE && colorRange != YUV_COLOR_RANGE_LIMITED) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    switch (format) {
        case YUV_FORMAT_I420:
        case YUV_FORMAT_NV12:
            if (colorMatrix != YUV_COLOR_MATRIX_BT601 || colorRange != YUV_COLOR_RANGE_LIMITED) {
                return YUV_STATUS_UNSUPPORTED_COLOR;
            }
            return YUV_STATUS_OK;

        case YUV_FORMAT_BGRA8888:
        case YUV_FORMAT_RGBA8888:
            if (colorMatrix != YUV_COLOR_MATRIX_NONE || colorRange != YUV_COLOR_RANGE_NONE) {
                return YUV_STATUS_UNSUPPORTED_COLOR;
            }
            return YUV_STATUS_OK;

        default:
            /* Unreachable: the caller checks the format before reaching here.
             * Kept as a defensive default rather than an assumption. */
            return YUV_STATUS_INVALID_ARGUMENT;
    }
}

/* All four reserved slots must be zero. A caller setting one is either using a
 * newer ABI against an older binary or corrupting the descriptor; either way
 * this build cannot honour whatever the field was meant to request, so it must
 * refuse rather than silently ignore it. */
static YuvStatus yuv_validate_v1_reserved(const uint64_t *reserved, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        if (reserved[i] != 0) {
            return YUV_STATUS_INVALID_ARGUMENT;
        }
    }
    return YUV_STATUS_OK;
}

/*
 * The scalar prefix shared by both frame descriptors. Both frame types have an
 * identical prefix layout (asserted in yuv_abi_v1.h), so validating it once
 * against copied-out values avoids a second near-identical function whose only
 * difference would be the plane pointer type.
 */
static YuvStatus yuv_validate_v1_frame_prefix(
    uint32_t structSize,
    uint32_t fullSize,
    uint32_t abiVersion,
    uint32_t format,
    uint32_t planeCount,
    uint32_t colorMatrix,
    uint32_t colorRange,
    const uint64_t *reserved) {
    if (abiVersion != YUV_ABI_VERSION_1) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    /* Smaller than the full v1 type means the caller cannot actually own the
     * fields this build is about to read. A LARGER size is accepted and its
     * unknown tail ignored: that is the forward-compatible extension rule. */
    if (structSize < fullSize) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvStatus reservedStatus = yuv_validate_v1_reserved(reserved, 4);
    if (reservedStatus != YUV_STATUS_OK) {
        return reservedStatus;
    }

    /* An unknown numeric format is INVALID_ARGUMENT, not UNSUPPORTED_FORMAT:
     * section 9 lists it alongside null pointers and bad ABI versions as a
     * malformed descriptor. UNSUPPORTED_FORMAT is reserved for a KNOWN format
     * in a pairing an operation does not accept, which each entry point
     * decides for itself through yuv_validate_v1_format_pair(). */
    uint32_t expectedPlaneCount = yuv_validated_view_plane_count(format);
    if (expectedPlaneCount == 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    /* The descriptor states its own plane count; disagreeing with the format
     * means the caller and this build read the same buffer differently. */
    if (planeCount != expectedPlaneCount) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    return yuv_validate_v1_color(format, colorMatrix, colorRange);
}

YuvStatus yuv_validate_v1_const_frame(const YuvConstFrameV1 *frame, YuvValidatedConstFrameView *outView) {
    if (frame == NULL || outView == NULL) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvStatus prefixStatus = yuv_validate_v1_frame_prefix(frame->structSize, (uint32_t)sizeof(YuvConstFrameV1),
        frame->abiVersion, frame->format, frame->planeCount, frame->colorMatrix, frame->colorRange,
        frame->reserved);
    if (prefixStatus != YUV_STATUS_OK) {
        return prefixStatus;
    }

    YuvValidatedConstPlaneIn planes[3];
    for (uint32_t i = 0; i < 3; i++) {
        planes[i].length = frame->planes[i].length;
        planes[i].rowStride = frame->planes[i].rowStride;
        planes[i].pixelStride = frame->planes[i].pixelStride;
        planes[i].sampleBytes = frame->planes[i].sampleBytes;
        planes[i].data = (const void *)frame->planes[i].data;
    }

    YuvViewStatus viewStatus = yuv_validated_view_build_const_frame(
        frame->format, frame->width, frame->height, planes, 3, outView);
    return yuv_validate_v1_status_from_view(viewStatus);
}

YuvStatus yuv_validate_v1_mutable_frame(YuvMutableFrameV1 *frame, YuvValidatedMutableFrameView *outView) {
    if (frame == NULL || outView == NULL) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvStatus prefixStatus = yuv_validate_v1_frame_prefix(frame->structSize, (uint32_t)sizeof(YuvMutableFrameV1),
        frame->abiVersion, frame->format, frame->planeCount, frame->colorMatrix, frame->colorRange,
        frame->reserved);
    if (prefixStatus != YUV_STATUS_OK) {
        return prefixStatus;
    }

    YuvValidatedMutablePlaneIn planes[3];
    for (uint32_t i = 0; i < 3; i++) {
        planes[i].length = frame->planes[i].length;
        planes[i].rowStride = frame->planes[i].rowStride;
        planes[i].pixelStride = frame->planes[i].pixelStride;
        planes[i].sampleBytes = frame->planes[i].sampleBytes;
        planes[i].data = (void *)frame->planes[i].data;
    }

    YuvViewStatus viewStatus = yuv_validated_view_build_mutable_frame(
        frame->format, frame->width, frame->height, planes, 3, outView);
    return yuv_validate_v1_status_from_view(viewStatus);
}

YuvStatus yuv_validate_v1_options_header(const void *options, uint32_t fullSize) {
    if (options == NULL) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Every v1 options struct starts with the same two uint32_t fields
     * (asserted in yuv_abi_v1.h), so the header can be read through any of
     * them. YuvConvertOptionsV1 is used as the representative type because it
     * is the minimal one: it carries the common prefix and nothing else. */
    const YuvConvertOptionsV1 *header = (const YuvConvertOptionsV1 *)options;
    if (header->abiVersion != YUV_ABI_VERSION_1) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (header->structSize < fullSize) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    return YUV_STATUS_OK;
}

YuvStatus yuv_validate_v1_region(const YuvRegionOptionsV1 *region, uint32_t width, uint32_t height) {
    if (region == NULL) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvStatus headerStatus = yuv_validate_v1_options_header(region, (uint32_t)sizeof(YuvRegionOptionsV1));
    if (headerStatus != YUV_STATUS_OK) {
        return headerStatus;
    }

    if (region->enabled == 0) {
        /* A disabled region must be fully zeroed. Accepting leftover
         * coordinates would make two descriptors that mean the same thing
         * compare differently, and would hide a caller that set a rectangle
         * and forgot to enable it. */
        if (region->left != 0 || region->top != 0 || region->right != 0 || region->bottom != 0 ||
            region->reserved0 != 0) {
            return YUV_STATUS_INVALID_ARGUMENT;
        }
        return YUV_STATUS_OK;
    }
    if (region->enabled != 1) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (region->reserved0 != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    /* Right/bottom-exclusive, non-empty, and inside the visible frame. Dart
     * normalizes and clamps before dispatch, but C validates defensively
     * because native validation is authoritative for hostile descriptors. */
    if (region->left < 0 || region->top < 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if (region->right <= region->left || region->bottom <= region->top) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    if ((int64_t)region->right > (int64_t)width || (int64_t)region->bottom > (int64_t)height) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }
    return YUV_STATUS_OK;
}

/*
 * Computes the half-open byte range [start, end) actually touched by a plane:
 * from its data pointer through its last active sample. Bytes past that point
 * belong to the caller's padding and are not part of the overlap question.
 */
static YuvStatus yuv_validate_v1_active_span(
    const void *data,
    uint32_t planeWidth,
    uint32_t planeHeight,
    uint64_t rowStride,
    uint32_t pixelStride,
    uint32_t sampleBytes,
    const unsigned char **outStart,
    const unsigned char **outEnd) {
    YuvSizeResult span = yuv_checked_plane_span(planeWidth, pixelStride, sampleBytes);
    if (!span.success) {
        return YUV_STATUS_OVERFLOW;
    }
    if (rowStride > SIZE_MAX) {
        return YUV_STATUS_OVERFLOW;
    }
    YuvSizeResult size = yuv_checked_plane_size(planeHeight, (size_t)rowStride, span.value);
    if (!size.success) {
        return YUV_STATUS_OVERFLOW;
    }

    const unsigned char *start = (const unsigned char *)data;
    *outStart = start;
    *outEnd = start + size.value;
    return YUV_STATUS_OK;
}

YuvStatus yuv_validate_v1_no_overlap(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    if (source == NULL || destination == NULL) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    for (uint32_t s = 0; s < source->planeCount; s++) {
        uint32_t sourceWidth = 0;
        uint32_t sourceHeight = 0;
        YuvViewStatus sourceGeometry = yuv_validated_view_plane_geometry(
            source->format, s, source->width, source->height, &sourceWidth, &sourceHeight);
        if (sourceGeometry != YUV_VIEW_OK) {
            return yuv_validate_v1_status_from_view(sourceGeometry);
        }

        const unsigned char *sourceStart = NULL;
        const unsigned char *sourceEnd = NULL;
        YuvStatus sourceSpan = yuv_validate_v1_active_span(source->planes[s].data, sourceWidth, sourceHeight,
            source->planes[s].rowStride, source->planes[s].pixelStride, source->planes[s].sampleBytes,
            &sourceStart, &sourceEnd);
        if (sourceSpan != YUV_STATUS_OK) {
            return sourceSpan;
        }

        for (uint32_t d = 0; d < destination->planeCount; d++) {
            uint32_t destinationWidth = 0;
            uint32_t destinationHeight = 0;
            YuvViewStatus destinationGeometry = yuv_validated_view_plane_geometry(destination->format, d,
                destination->width, destination->height, &destinationWidth, &destinationHeight);
            if (destinationGeometry != YUV_VIEW_OK) {
                return yuv_validate_v1_status_from_view(destinationGeometry);
            }

            const unsigned char *destinationStart = NULL;
            const unsigned char *destinationEnd = NULL;
            YuvStatus destinationSpan = yuv_validate_v1_active_span(destination->planes[d].data,
                destinationWidth, destinationHeight, destination->planes[d].rowStride,
                destination->planes[d].pixelStride, destination->planes[d].sampleBytes, &destinationStart,
                &destinationEnd);
            if (destinationSpan != YUV_STATUS_OK) {
                return destinationSpan;
            }

            /* Half-open ranges overlap when each starts before the other ends.
             * Comparing pointers from unrelated allocations is not strictly
             * defined by C, but every supported target has a flat address
             * space, and the alternative -- not checking at all -- would let an
             * aliased call silently corrupt its own source mid-operation. */
            if (sourceStart < destinationEnd && destinationStart < sourceEnd) {
                return YUV_STATUS_INVALID_ARGUMENT;
            }
        }
    }

    return YUV_STATUS_OK;
}

YuvStatus yuv_validate_v1_frames(
    const YuvConstFrameV1 *source,
    YuvMutableFrameV1 *destination,
    YuvGeometryRuleV1 rule,
    uint32_t explicitWidth,
    uint32_t explicitHeight,
    YuvValidatedConstFrameView *outSource,
    YuvValidatedMutableFrameView *outDestination) {
    YuvStatus sourceStatus = yuv_validate_v1_const_frame(source, outSource);
    if (sourceStatus != YUV_STATUS_OK) {
        return sourceStatus;
    }

    YuvStatus destinationStatus = yuv_validate_v1_mutable_frame(destination, outDestination);
    if (destinationStatus != YUV_STATUS_OK) {
        return destinationStatus;
    }

    /* Only now is it legal to read the source geometry: the descriptor has
     * been validated, so width/height are known to be in range. */
    uint32_t expectedWidth = 0;
    uint32_t expectedHeight = 0;
    switch (rule) {
        case YUV_GEOMETRY_V1_SAME:
            expectedWidth = outSource->width;
            expectedHeight = outSource->height;
            break;
        case YUV_GEOMETRY_V1_TRANSPOSED:
            expectedWidth = outSource->height;
            expectedHeight = outSource->width;
            break;
        case YUV_GEOMETRY_V1_EXPLICIT:
            expectedWidth = explicitWidth;
            expectedHeight = explicitHeight;
            break;
        default:
            return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvViewStatus geometryStatus =
        yuv_validated_view_check_destination_geometry(outDestination, expectedWidth, expectedHeight);
    if (geometryStatus != YUV_VIEW_OK) {
        return yuv_validate_v1_status_from_view(geometryStatus);
    }

    return yuv_validate_v1_no_overlap(outSource, outDestination);
}

YuvStatus yuv_validate_v1_format_pair(
    uint32_t sourceFormat, uint32_t destinationFormat, const YuvFormatPairV1 *pairs, uint32_t pairCount) {
    for (uint32_t i = 0; i < pairCount; i++) {
        if (pairs[i].sourceFormat == sourceFormat && pairs[i].destinationFormat == destinationFormat) {
            return YUV_STATUS_OK;
        }
    }
    return YUV_STATUS_UNSUPPORTED_FORMAT;
}
