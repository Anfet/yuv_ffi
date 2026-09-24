#ifndef YUV_VALIDATED_VIEW_H
#define YUV_VALIDATED_VIEW_H

#include <stdint.h>
#include <stddef.h>

/*
 * Internal validated plane/frame views for the 0.3 native ABI.
 *
 * These views mirror the wire-compatible `YuvConstPlaneV1` / `YuvMutablePlaneV1`
 * / `YuvConstFrameV1` / `YuvMutableFrameV1` layouts described in
 * doc/api-abi-0.4-design.md sections 9-11, but this header intentionally does
 * NOT redeclare those exact ABI structs: YUV-36 owns the public, wire-stable
 * descriptor/status ABI (structSize/abiVersion negotiation, sizeof/offsetof
 * layout assertions, reserved-field zero checks). This header owns the
 * validation LOGIC and the internal view shape the `yuv_*_v1` operations
 * build from those public structs.
 *
 * A caller-facing plane descriptor. Deliberately shaped like the public ABI
 * plane structs (`length`, `rowStride`, `pixelStride`, `sampleBytes`, `data`),
 * so building one from a `YuvConstPlaneV1`/`YuvMutablePlaneV1` is a field
 * copy, not a semantic conversion. `data` is `const void *` / `void *` here rather than `uint8_t *`
 * because validation never dereferences or indexes through it -- see the
 * adoption contract below.
 */
typedef struct {
    uint64_t length;
    uint64_t rowStride;
    uint32_t pixelStride;
    uint32_t sampleBytes;
    const void *data;
} YuvValidatedConstPlaneIn;

typedef struct {
    uint64_t length;
    uint64_t rowStride;
    uint32_t pixelStride;
    uint32_t sampleBytes;
    void *data;
} YuvValidatedMutablePlaneIn;

/* Format IDs, matching doc/api-abi-0.4-design.md section 9 exactly. */
#define YUV_VIEW_FORMAT_I420     ((uint32_t)1)
#define YUV_VIEW_FORMAT_NV12     ((uint32_t)2)
#define YUV_VIEW_FORMAT_BGRA8888 ((uint32_t)3)
#define YUV_VIEW_FORMAT_RGBA8888 ((uint32_t)4)

/* Validation status, kept intentionally close to YuvStatus (ABI section 9)
 * but not aliased to it: this file does not own status-value stability for
 * the public ABI, src/yuv/abi/h/yuv_abi_v1.h does. */
typedef enum {
    YUV_VIEW_OK = 0,
    YUV_VIEW_INVALID_ARGUMENT = 1,
    YUV_VIEW_UNSUPPORTED_FORMAT = 2,
    YUV_VIEW_OVERFLOW = 4
} YuvViewStatus;

/*
 * A validated source (const) frame view: up to 3 planes, each one already
 * checked against the format's geometry/stride/span rules in section 11.
 * Unused planes (e.g. I420's absent 3rd slot logically, or a format with
 * fewer than 3 planes) are zero-filled with a null `data` pointer -- see
 * yuv_validated_view_zero_plane_in().
 */
typedef struct {
    uint32_t format;
    uint32_t planeCount;
    uint32_t width;
    uint32_t height;
    YuvValidatedConstPlaneIn planes[3];
} YuvValidatedConstFrameView;

typedef struct {
    uint32_t format;
    uint32_t planeCount;
    uint32_t width;
    uint32_t height;
    YuvValidatedMutablePlaneIn planes[3];
} YuvValidatedMutableFrameView;

/*
 * Returns a zero-filled plane descriptor with a null data pointer, for the
 * unused plane slots of a format with fewer than 3 planes (section 9: "Unused
 * planes are zero-filled descriptors with null data").
 */
YuvValidatedConstPlaneIn yuv_validated_view_zero_plane_in(void);
YuvValidatedMutablePlaneIn yuv_validated_view_zero_plane_mutable_in(void);

/*
 * Returns the plane count required by `format`, or 0 if `format` is not one
 * of the section-9 format IDs.
 */
uint32_t yuv_validated_view_plane_count(uint32_t format);

/*
 * Returns the logical plane width/height for `planeIndex` of `format` given
 * frame `width`/`height`, using checked ceil-half (yuv_checked_ceil_half) for
 * 4:2:0 chroma per section 11's format matrix. Returns YUV_VIEW_OK and fills
 * `*outPlaneWidth`/`*outPlaneHeight` on success; returns
 * YUV_VIEW_UNSUPPORTED_FORMAT for an unknown format or out-of-range
 * planeIndex, or YUV_VIEW_OVERFLOW if the ceil-half computation cannot
 * proceed (defensive; ceil-half itself cannot overflow, but this keeps a
 * uniform status surface).
 */
YuvViewStatus yuv_validated_view_plane_geometry(
    uint32_t format,
    uint32_t planeIndex,
    uint32_t width,
    uint32_t height,
    uint32_t *outPlaneWidth,
    uint32_t *outPlaneHeight);

/*
 * Returns the required `sampleBytes` and minimum `pixelStride` for
 * `planeIndex` of `format`, per section 11's format matrix:
 *   I420:      every plane      sampleBytes=1, minPixelStride=1
 *   NV12:      Y                sampleBytes=1, minPixelStride=1
 *              UV               sampleBytes=2, minPixelStride=2
 *   BGRA/RGBA: single packed    sampleBytes=4, minPixelStride=4
 * Returns YUV_VIEW_UNSUPPORTED_FORMAT for an unknown format or out-of-range
 * planeIndex.
 */
YuvViewStatus yuv_validated_view_plane_sample_layout(
    uint32_t format,
    uint32_t planeIndex,
    uint32_t *outSampleBytes,
    uint32_t *outMinPixelStride);

/*
 * Validates and builds a const frame view from caller-supplied geometry and
 * per-plane descriptors carrying ACTUAL lengths (never guessed from format/
 * geometry alone -- the point of this task per YUV-33 Architect Decision #2).
 *
 * `planes` must have exactly `yuv_validated_view_plane_count(format)` entries
 * populated (planes beyond that count are ignored on input and the
 * corresponding output slots are zero-filled). Validation performed, in
 * order, per doc/api-abi-0.4-design.md sections 9-11:
 *
 *   1. `out` non-null, `format` is one of the section-9 IDs, else
 *      UNSUPPORTED_FORMAT / INVALID_ARGUMENT (out null).
 *   2. `width` and `height` are both >= 1 and <= INT32_MAX (section 9).
 *   3. For each used plane: `data` non-null, `sampleBytes` and `pixelStride`
 *      match/exceed the format's required sample layout (`sampleBytes` must
 *      equal exactly; `pixelStride` must be >= the format minimum -- larger
 *      values are an accepted padded/gapped layout per Architect Decision
 *      #3), and `rowStride`/`length` satisfy the checked minimum span/size
 *      formulas from section 11, computed via the yuv_checked_* helpers
 *      (never raw `*`/`+`).
 *   4. Any checked-arithmetic overflow anywhere in step 3 is reported as
 *      YUV_VIEW_OVERFLOW, distinct from an ordinary undersized-value
 *      INVALID_ARGUMENT.
 *
 * On any failure, `*out` is left in a zero-filled state and the specific
 * YuvViewStatus is returned. Does not dereference `data`; only compares it
 * to NULL.
 */
YuvViewStatus yuv_validated_view_build_const_frame(
    uint32_t format,
    uint32_t width,
    uint32_t height,
    const YuvValidatedConstPlaneIn *planes,
    uint32_t planesLength,
    YuvValidatedConstFrameView *out);

/* Mutable-destination counterpart of yuv_validated_view_build_const_frame(). */
YuvViewStatus yuv_validated_view_build_mutable_frame(
    uint32_t format,
    uint32_t width,
    uint32_t height,
    const YuvValidatedMutablePlaneIn *planes,
    uint32_t planesLength,
    YuvValidatedMutableFrameView *out);

/*
 * Validates that a destination frame view's geometry matches the geometry an
 * operation requires (section 11's "Destination geometry" column), given the
 * already-built destination `YuvValidatedMutableFrameView`. `expectedWidth`/
 * `expectedHeight` are computed by the caller (identity for most operations,
 * transposed for 90/270 rotation, ROI-derived for crop). Returns
 * YUV_VIEW_INVALID_ARGUMENT when they differ, YUV_VIEW_OK otherwise.
 */
YuvViewStatus yuv_validated_view_check_destination_geometry(
    const YuvValidatedMutableFrameView *destination,
    uint32_t expectedWidth,
    uint32_t expectedHeight);

/*
 * ---------------------------------------------------------------------------
 * Adoption contract (YUV-33 Architect Decision #6)
 * ---------------------------------------------------------------------------
 *
 * Every native operation MUST complete validation via
 * yuv_validated_view_build_const_frame() / yuv_validated_view_build_mutable_frame()
 * (and yuv_validated_view_check_destination_geometry() for its expected
 * output size) BEFORE its first destination mutation, and use a single
 * cleanup/return path on any non-OK status.
 *
 * This is now the state of the tree rather than a plan for it. The eleven
 * `yuv_*_v1` entry points in `src/yuv/abi/` are the whole processing surface:
 * each validates its options struct first (header, reserved fields and the
 * operation's own parameters), then builds its source and destination views
 * from the public `YuvConstFrameV1`/`YuvMutableFrameV1` structs, and checks
 * destination geometry before writing. Both halves of that sequence precede
 * the first destination mutation, which is what the contract above requires;
 * the order between them is not itself part of the contract. There are no
 * length-less pointer triples left to migrate -- YUV-52 removed the per-format
 * `src/yuv/bgra8888/`, `src/yuv/nv21/` and `src/yuv/yuv420/` implementations
 * and the `YUVDef` descriptor along with them, so every call site reaching
 * these views arrives through the section-9 ABI.
 *
 * That also closes the "weaker guarantee" recorded in YUV-33 Architect
 * Decision #5. A `YUVDef` carried no buffer length, so an adapter built on it
 * could only ever check internal consistency (non-null pointers, positive
 * geometry and strides) against a length it computed itself via
 * yuv_checked_plane_span()/yuv_checked_plane_size(). The section-9 descriptors
 * carry an explicit caller-supplied `length`, so a view built from them
 * validates the geometry and strides against the buffer length the caller
 * declares, rather than against a length derived from that same geometry.
 * Note the limit: `length` is the caller's claim about its buffer, not a
 * measurement of the allocation behind the pointer. A caller that declares a
 * length larger than it allocated still defeats these checks -- the ABI
 * cannot observe the real allocation size, and no in-process validation can.
 * What the descriptors buy is that an honest caller's under-sized buffer is
 * now rejected instead of silently over-read, which a computed length could
 * never catch.
 */

#endif  // YUV_VALIDATED_VIEW_H
