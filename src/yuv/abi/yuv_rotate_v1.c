#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"

/*
 * Clockwise rotation by exactly 0, 90, 180, or 270 degrees.
 *
 * 0 and 180 keep the source geometry; 90 and 270 transpose it, so the
 * destination must be source height x width. Getting that backwards is the
 * likeliest caller mistake here, which is why the geometry rule is chosen from
 * the angle before the destination is checked against it.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_rotate_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvRotateOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvRotateOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved0 != 0 || options->reserved[0] != 0 || options->reserved[1] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvGeometryRuleV1 rule;
    switch (options->rotationDegrees) {
        case 0:
        case 180:
            rule = YUV_GEOMETRY_V1_SAME;
            break;
        case 90:
        case 270:
            rule = YUV_GEOMETRY_V1_TRANSPOSED;
            break;
        default:
            return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView sourceView;
    YuvValidatedMutableFrameView destinationView;
    YuvStatus framesStatus =
        yuv_validate_v1_frames(source, destination, rule, 0, 0, &sourceView, &destinationView);
    if (framesStatus != YUV_STATUS_OK) {
        return framesStatus;
    }

    YuvStatus pairStatus = yuv_validate_v1_format_pair(
        sourceView.format, destinationView.format, YUV_SAME_FORMAT_PAIRS_V1, 3);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    /* Validation is complete and both descriptors are sound, but the rotation kernel
     * has not landed yet -- YUV-31 owns it. Returning INTERNAL_ERROR without
     * writing a single destination byte keeps the atomicity contract honest in
     * the meantime: a caller sees a clean failure, never a half-written frame.
     *
     * Replace this with the real kernel -- never with a bare YUV_STATUS_OK,
     * which would report success for an untouched frame.
     */
    return YUV_STATUS_INTERNAL_ERROR;
}
