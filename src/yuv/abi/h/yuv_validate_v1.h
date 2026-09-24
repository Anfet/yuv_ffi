#ifndef YUV_VALIDATE_V1_H
#define YUV_VALIDATE_V1_H

#include "yuv_abi_v1.h"
#include "../../utils/h/validated_view.h"

/*
 * Internal validation prologue shared by the eleven ABI v1 entry points.
 *
 * This header is NOT part of the exported ABI; it is the common front half of
 * every `yuv_*_v1` body. Keeping it in one place is the point: eleven
 * hand-written copies of "check abiVersion, check structSize, check reserved,
 * check color pairing, build both views, compare geometry" is exactly how the
 * legacy surface ended up with per-file divergence.
 *
 * Division of labour with src/yuv/utils/h/validated_view.h (YUV-33c): that
 * header owns everything derivable from a plane's own numbers -- plane count,
 * logical geometry, sample bytes, pixel/row strides, minimum spans, and the
 * checked arithmetic behind them. This header owns what only the public ABI
 * carries and what only a whole operation can judge:
 *
 *   - struct size / ABI version negotiation and reserved-field zeroing;
 *   - the declared colorMatrix/colorRange pairing, which the views do not see;
 *   - the frame's own planeCount agreeing with the format;
 *   - the source/destination format pair and destination geometry for the
 *     specific operation;
 *   - the ABI v1 rule that active source and destination spans must not
 *     overlap.
 *
 * Status vocabulary: the view layer reports YuvViewStatus, deliberately not
 * aliased to the public YuvStatus. yuv_validate_v1_status_from_view() performs
 * the one authorised translation, so the mapping exists once rather than in
 * each caller.
 */

/* Translates an internal YuvViewStatus into the public YuvStatus. */
YuvStatus yuv_validate_v1_status_from_view(YuvViewStatus status);

/*
 * Validates one frame descriptor and builds its validated view.
 *
 * Order matters and is fixed by section 9: "Null descriptor/options pointers,
 * ABI versions other than 1, structSize smaller than the full v1 type,
 * non-zero known reserved fields, and unknown numeric format/matrix/range
 * values return YUV_STATUS_INVALID_ARGUMENT BEFORE plane access." A larger
 * structSize is accepted and its unknown tail ignored -- that is the
 * forward-compatible extension rule, not a laxity.
 *
 * Returns YUV_STATUS_OK and fills `*outView` on success.
 */
YuvStatus yuv_validate_v1_const_frame(const YuvConstFrameV1 *frame, YuvValidatedConstFrameView *outView);
YuvStatus yuv_validate_v1_mutable_frame(YuvMutableFrameV1 *frame, YuvValidatedMutableFrameView *outView);

/*
 * Validates the common header (structSize/abiVersion) of an options struct.
 * `fullSize` is sizeof() of the caller's concrete v1 options type.
 */
YuvStatus yuv_validate_v1_options_header(const void *options, uint32_t fullSize);

/*
 * Validates a region sub-struct (section 10). When `enabled` is 0 every
 * coordinate and `reserved0` must be zero; when 1 the rectangle must be a
 * well-formed right/bottom-exclusive, non-empty rectangle inside
 * `width` x `height`. Any other `enabled` value is invalid.
 */
YuvStatus yuv_validate_v1_region(const YuvRegionOptionsV1 *region, uint32_t width, uint32_t height);

/*
 * Rejects an overlap between the active spans of source and destination
 * (section 9: "Source and destination active spans must not overlap in ABI
 * v1"). Compares the half-open byte range of each used plane.
 *
 * Note this checks the ACTIVE span, so a destination that merely sits in the
 * same allocation as the source but past its last active byte is accepted;
 * what is rejected is genuine aliasing of the bytes an operation would read
 * and write.
 */
YuvStatus yuv_validate_v1_no_overlap(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination);

/*
 * How an operation derives its required destination geometry from the
 * validated source geometry. Passed to yuv_validate_v1_frames() instead of
 * precomputed width/height, because the caller cannot legally read
 * source->width until the source descriptor has been validated -- and that
 * validation happens inside yuv_validate_v1_frames().
 */
typedef enum {
    /* Destination is exactly source width x height (effects, blur, convert,
     * flip, rotate 0/180, chroma swap). */
    YUV_GEOMETRY_V1_SAME = 0,
    /* Destination is source height x width (rotate 90/270). */
    YUV_GEOMETRY_V1_TRANSPOSED = 1,
    /* Destination geometry is supplied by the operation's options (crop);
     * the caller passes it in explicitly. */
    YUV_GEOMETRY_V1_EXPLICIT = 2
} YuvGeometryRuleV1;

/*
 * The full prologue every entry point runs before touching a pixel: validates
 * both descriptors, checks the destination geometry against what the operation
 * requires, and rejects overlapping spans.
 *
 * `rule` selects how the required destination geometry follows from the
 * source. `explicitWidth`/`explicitHeight` are read only for
 * YUV_GEOMETRY_V1_EXPLICIT and ignored otherwise.
 */
YuvStatus yuv_validate_v1_frames(
    const YuvConstFrameV1 *source,
    YuvMutableFrameV1 *destination,
    YuvGeometryRuleV1 rule,
    uint32_t explicitWidth,
    uint32_t explicitHeight,
    YuvValidatedConstFrameView *outSource,
    YuvValidatedMutableFrameView *outDestination);

/*
 * Checks a source->destination format pair against a caller-supplied table of
 * accepted pairs. Returns YUV_STATUS_UNSUPPORTED_FORMAT when the pair is
 * absent, which section 11 requires to happen before any destination write.
 */
typedef struct {
    uint32_t sourceFormat;
    uint32_t destinationFormat;
} YuvFormatPairV1;

YuvStatus yuv_validate_v1_format_pair(
    uint32_t sourceFormat, uint32_t destinationFormat, const YuvFormatPairV1 *pairs, uint32_t pairCount);

/*
 * The pair table shared by effects, blur, and the geometric transforms:
 * I420->I420, NV12->NV12, BGRA->BGRA. Conversion and chroma swap use their own
 * tables.
 */
extern const YuvFormatPairV1 YUV_SAME_FORMAT_PAIRS_V1[3];

#endif  /* YUV_VALIDATE_V1_H */
