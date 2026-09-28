#ifndef YUV_VALIDATED_VIEW_H
#define YUV_VALIDATED_VIEW_H

#include <stdint.h>
#include <stddef.h>

/*
 * Internal validated plane and frame views used by the native ABI.
 *
 * These views mirror the wire-compatible `YuvConstPlaneV1` / `YuvMutablePlaneV1`
 * / `YuvConstFrameV1` / `YuvMutableFrameV1` layouts, but this header
 * intentionally does NOT redeclare those ABI structs: yuv_abi_v1.h owns the
 * public, wire-stable descriptor/status ABI, including version negotiation,
 * layout assertions, and reserved-field checks. This header owns the
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

/* Internal format IDs matching the public ABI values. */
#define YUV_VIEW_FORMAT_I420     ((uint32_t)1)
#define YUV_VIEW_FORMAT_NV12     ((uint32_t)2)
#define YUV_VIEW_FORMAT_BGRA8888 ((uint32_t)3)
#define YUV_VIEW_FORMAT_RGBA8888 ((uint32_t)4)

/* Internal validation status, kept intentionally close to YuvStatus
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
 * checked against the format's geometry, stride, and span rules.
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
 * unused plane slots of a format with fewer than 3 planes.
 */
YuvValidatedConstPlaneIn yuv_validated_view_zero_plane_in(void);
YuvValidatedMutablePlaneIn yuv_validated_view_zero_plane_mutable_in(void);

/*
 * Returns the plane count required by `format`, or 0 if `format` is not one
 * of the supported format IDs.
 */
uint32_t yuv_validated_view_plane_count(uint32_t format);

/*
 * Returns the logical plane width/height for `planeIndex` of `format` given
 * frame `width`/`height`, using checked ceil-half (yuv_checked_ceil_half) for
 * 4:2:0 chroma. Returns YUV_VIEW_OK and fills
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
 * `planeIndex` of `format`:
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
 * geometry alone).
 *
 * `planes` must have exactly `yuv_validated_view_plane_count(format)` entries
 * populated (planes beyond that count are ignored on input and the
 * corresponding output slots are zero-filled). Validation is performed in
 * this order:
 *
 *   1. `out` non-null, `format` is supported, else
 *      UNSUPPORTED_FORMAT / INVALID_ARGUMENT (out null).
 *   2. `width` and `height` are both >= 1 and <= INT32_MAX.
 *   3. For each used plane: `data` non-null, `sampleBytes` and `pixelStride`
 *      match/exceed the format's required sample layout (`sampleBytes` must
 *      equal exactly; `pixelStride` must be >= the format minimum -- larger
 *      values are an accepted padded/gapped layout), and `rowStride`/`length`
 *      satisfy the checked minimum span/size formulas computed via the
 *      yuv_checked_* helpers
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
 * operation requires, given the
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
 * Adoption contract
 * ---------------------------------------------------------------------------
 *
 * Every native operation validates its options, then builds the source and
 * destination views and checks destination geometry before the first write.
 * It returns on any validation failure without modifying the destination.
 *
 * The public descriptors include a caller-supplied `length`; validation
 * checks geometry and strides against that declared buffer length. It cannot
 * measure the allocation behind the pointer, so the caller must report an
 * accurate length.
 */

#endif  // YUV_VALIDATED_VIEW_H
