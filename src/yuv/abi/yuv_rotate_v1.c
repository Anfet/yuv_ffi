#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

/*
 * Clockwise rotation by exactly 0, 90, 180, or 270 degrees.
 *
 * 0 and 180 keep the source geometry; 90 and 270 transpose it, so the
 * destination must be source height x width. Getting that backwards is the
 * likeliest caller mistake here, which is why the geometry rule is chosen from
 * the angle before the destination is checked against it.
 */
/* Reversing an axis of extent n keeps every 2x2 chroma block intact exactly
 * when n is even, or when n is 1 and the reversal is therefore the identity.
 * At any other odd extent a destination block straddles two source blocks. */
static int yuv_axis_reversal_is_block_aligned(uint32_t extent) {
    return (extent % 2) == 0 || extent == 1;
}

typedef struct {
    uint32_t sourceWidth;
    uint32_t sourceHeight;
    uint32_t degrees;
} YuvRotateContextV1;

/* Clockwise, per section 11: 90 takes destination (x,y) from source
 * (y, height-1-x), 180 from (width-1-x, height-1-y), 270 from (width-1-y, x). */
static void yuv_rotate_v1_map(
    void *context, uint32_t destinationX, uint32_t destinationY, uint32_t *outSourceX, uint32_t *outSourceY) {
    const YuvRotateContextV1 *rotate = (const YuvRotateContextV1 *)context;
    switch (rotate->degrees) {
        case 90:
            *outSourceX = destinationY;
            *outSourceY = rotate->sourceHeight - 1 - destinationX;
            return;
        case 180:
            *outSourceX = rotate->sourceWidth - 1 - destinationX;
            *outSourceY = rotate->sourceHeight - 1 - destinationY;
            return;
        case 270:
            *outSourceX = rotate->sourceWidth - 1 - destinationY;
            *outSourceY = destinationX;
            return;
        default:
            *outSourceX = destinationX;
            *outSourceY = destinationY;
            return;
    }
}

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

    /* 0 degrees is the identity. Every other angle reverses at least one
     * axis (180 reverses both; 90 and 270 reverse one and transpose), and a
     * transpose can pair any x block with any y block, so both extents have
     * to survive reversal for the copy path to stay phase-correct. */
    int blockAligned = options->rotationDegrees == 0 ||
        (yuv_axis_reversal_is_block_aligned(sourceView.width) &&
            yuv_axis_reversal_is_block_aligned(sourceView.height));

    YuvRotateContextV1 context;
    context.sourceWidth = sourceView.width;
    context.sourceHeight = sourceView.height;
    context.degrees = options->rotationDegrees;

    yuv_kernel_v1_transform(&sourceView, &destinationView, yuv_rotate_v1_map, &context, blockAligned);

    return YUV_STATUS_OK;
}
