#ifndef YUV_KERNEL_V1_H
#define YUV_KERNEL_V1_H

#include "yuv_abi_v1.h"
#include "../../utils/h/validated_view.h"

/*
 * Shared pixel-kernel support for the ABI v1 entry points.
 *
 * Division of labour: yuv_validate_v1.h owns everything that happens BEFORE
 * the first destination write; this header owns what happens after, once both
 * views are known sound. It exists because the legacy surface proved that
 * nine or forty copies of "index a sample through its own row/pixel stride"
 * and "decode BT.601" diverge -- the audit behind YUV-22/23/31/32 is a list
 * of exactly those divergences (floor vs ceil chroma, pixelStride used as a
 * sample size, one matrix here and another there).
 *
 * Two rules hold throughout and are the reason the accessors take a plane
 * view rather than a raw pointer:
 *
 *  - A sample is addressed as `y * rowStride + x * pixelStride` and is
 *    exactly `sampleBytes` wide. Row gaps, pixel gaps, and bytes past the
 *    last sample are padding: never read as pixel data, never written.
 *  - 4:2:0 chroma geometry is ceil(w/2) x ceil(h/2). A frame of odd width or
 *    height has a trailing chroma column/row that is a real sample.
 */

/* A logical RGB pixel with its alpha carried alongside. Alpha is preserved
 * byte-exact by effects and blur (it never enters a convolution) and moves
 * with its pixel through the geometric transforms; for YUV formats, which
 * have no alpha, it is 255. */
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} YuvRgbaPixelV1;

/* ===========================================================================
 * Sample addressing
 * =========================================================================== */

/*
 * Byte offset of logical sample (x, y) within `plane`, or a failed
 * YuvSizeResult on overflow. Both helpers go through
 * yuv_checked_sample_offset(); no caller multiplies strides itself.
 */
const uint8_t *yuv_kernel_v1_const_sample(const YuvValidatedConstPlaneIn *plane, uint32_t x, uint32_t y);
uint8_t *yuv_kernel_v1_mutable_sample(const YuvValidatedMutablePlaneIn *plane, uint32_t x, uint32_t y);

/* ===========================================================================
 * BT.601 limited-range codec (section 11: "the existing BT.601 limited-range
 * integer oracle")
 * =========================================================================== */

/* Decodes one YUV triple to RGB. Alpha of the result is 255. */
YuvRgbaPixelV1 yuv_kernel_v1_yuv_to_rgb(uint8_t y, uint8_t u, uint8_t v);

/* Encodes RGB to the limited-range Y sample. */
uint8_t yuv_kernel_v1_rgb_to_y(uint8_t r, uint8_t g, uint8_t b);

/* Encodes RGB to the limited-range U and V samples. */
uint8_t yuv_kernel_v1_rgb_to_u(uint8_t r, uint8_t g, uint8_t b);
uint8_t yuv_kernel_v1_rgb_to_v(uint8_t r, uint8_t g, uint8_t b);

/* Rounded luma used by grayscale and black-white:
 * floor((299*R + 587*G + 114*B + 500) / 1000). Note this is the visible-RGB
 * gray of section 11, NOT the limited-range Y above: they differ, and using
 * one where the other belongs is one of the reference failures YUV-22 lists. */
uint8_t yuv_kernel_v1_gray(uint8_t r, uint8_t g, uint8_t b);

/* ===========================================================================
 * Visible-pixel access
 *
 * These read and write a frame as if it were a plain RGB image, hiding which
 * of the three storage formats is underneath. That is what makes one kernel
 * per operation satisfy the "storage-independent visible-pixel oracle"
 * instead of three per-format kernels that drift apart.
 * =========================================================================== */

/*
 * Reads visible pixel (x, y) of a validated source frame. For 4:2:0 the
 * chroma sample at (x/2, y/2) is shared by the 2x2 luma footprint, which is
 * the decode direction of the same rule conversion uses when encoding.
 */
YuvRgbaPixelV1 yuv_kernel_v1_read_pixel(const YuvValidatedConstFrameView *frame, uint32_t x, uint32_t y);

/*
 * Copies one visible pixel from source (sourceX, sourceY) to destination
 * (destinationX, destinationY) in its stored representation, without a decode
 * or re-encode round trip.
 *
 * Geometric transforms use this rather than read_pixel/write: a rotation or
 * flip must move bytes, not re-derive them, or a 180-degree rotation of a
 * 4:2:0 frame would quantize chroma a second time. For 4:2:0 the chroma
 * sample is copied when the destination pixel is the top-left of its own 2x2
 * block, so each destination chroma sample is written exactly once.
 */
void yuv_kernel_v1_copy_pixel(
    const YuvValidatedConstFrameView *source,
    uint32_t sourceX,
    uint32_t sourceY,
    const YuvValidatedMutableFrameView *destination,
    uint32_t destinationX,
    uint32_t destinationY);

/*
 * Writes the luma/packed part of visible pixel (x, y). For BGRA this writes
 * the whole pixel including alpha; for I420/NV12 it writes Y only, and chroma
 * is supplied separately by yuv_kernel_v1_encode_chroma_block(), because one
 * chroma sample belongs to four luma samples and must be written once from
 * their average rather than four times from the last one seen.
 */
void yuv_kernel_v1_write_luma(
    const YuvValidatedMutableFrameView *frame, uint32_t x, uint32_t y, YuvRgbaPixelV1 pixel);

/*
 * Writes the chroma sample covering the 2x2 luma footprint whose top-left is
 * (blockX * 2, blockY * 2), averaging U and V over the pixels of that
 * footprint that actually exist -- the clipped 2x2 rule of section 11, which
 * is what makes an odd right/bottom edge divide by 2 or 1 instead of 4.
 *
 * `pixels` holds the footprint in raster order and `count` how many of the
 * four are real. A no-op for BGRA, which has no chroma plane.
 */
void yuv_kernel_v1_encode_chroma_block(
    const YuvValidatedMutableFrameView *frame,
    uint32_t blockX,
    uint32_t blockY,
    const YuvRgbaPixelV1 *pixels,
    uint32_t count);

/*
 * True when `format` stores chroma at 4:2:0, i.e. has a chroma plane whose
 * geometry is ceil(w/2) x ceil(h/2).
 */
int yuv_kernel_v1_is_420(uint32_t format);

/* ===========================================================================
 * Geometric transform driver
 * =========================================================================== */

/*
 * Maps a destination visible coordinate to its source visible coordinate.
 * `context` carries whatever the specific transform needs (source geometry,
 * crop origin, rotation angle).
 */
typedef void (*YuvPixelMapV1)(void *context, uint32_t destinationX, uint32_t destinationY,
    uint32_t *outSourceX, uint32_t *outSourceY);

/*
 * Runs a geometric transform (crop, flip, rotate) over the whole destination.
 *
 * Chooses between two paths that must agree, and the choice is a correctness
 * matter rather than an optimization:
 *
 *  - Byte copy, which moves stored samples untouched. Exact only when every
 *    destination 2x2 chroma block draws from exactly one whole source 2x2
 *    block. Under a flip, a 180 rotation, or a crop that is what "both the
 *    relevant source and destination extents are even, and a crop origin is
 *    even" buys: otherwise a destination block straddles two source blocks
 *    and copying one of them shifts chroma phase.
 *  - Visible re-encode, which decodes the source footprint to RGB and
 *    re-encodes chroma by the clipped 2x2 rule. Phase-correct for any
 *    geometry, at the cost of one extra quantization.
 *
 * This is the "recompute destination chroma from the source visible RGB
 * footprint (or an exactly equivalent phase-aware implementation)" of section
 * 14 Q2: the fast path is taken only where it is provably that equivalent.
 *
 * `blockAligned` is the caller's assertion that the mapping preserves 2x2
 * block alignment. Ignored for BGRA, which has no chroma to phase-shift.
 */
void yuv_kernel_v1_transform(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    YuvPixelMapV1 map,
    void *context,
    int blockAligned);

/* ===========================================================================
 * Visible-pixel encode driver
 * =========================================================================== */

/*
 * Produces the visible RGB pixel that belongs at destination (x, y).
 * `context` carries whatever the operation needs.
 */
typedef YuvRgbaPixelV1 (*YuvPixelSourceV1)(void *context, uint32_t x, uint32_t y);

/*
 * Writes a whole destination frame from a visible-pixel producer, applying the
 * storage rules of the destination format: luma/packed per pixel, and one
 * chroma sample per 2x2 block averaged over the pixels of that block which
 * actually exist.
 *
 * This is the single encode path behind conversion, the effects, and blur.
 * Having one means the clipped-2x2 odd-edge rule, and the "average RGB then
 * encode once" order that the reference oracle uses, cannot drift between
 * them -- which is exactly how BGRA->I420 ended up taking chroma from the
 * top-left pixel while RGBA->I420 averaged the block (YUV-32).
 *
 * `produce` is called once per visible pixel for luma, and again for the
 * members of each chroma footprint, so it must be a pure function of its
 * coordinates.
 */
void yuv_kernel_v1_encode_frame(
    const YuvValidatedMutableFrameView *destination, YuvPixelSourceV1 produce, void *context);

/* ===========================================================================
 * Effect driver
 * =========================================================================== */

/* Transforms one visible RGB pixel. Alpha of the returned pixel is ignored:
 * the driver carries the source alpha across untouched, per section 11
 * ("Effects and blur preserve the BGRA alpha byte"). */
typedef YuvRgbaPixelV1 (*YuvRgbEffectV1)(void *context, YuvRgbaPixelV1 pixel, uint32_t x, uint32_t y);

/* A normalized, already-validated region of interest. `enabled == 0` means
 * the whole frame. Coordinates are right/bottom exclusive. */
typedef struct {
    int enabled;
    uint32_t left;
    uint32_t top;
    uint32_t right;
    uint32_t bottom;
} YuvRegionV1;

/*
 * Applies `effect` to every visible pixel inside the region and copies the
 * rest of the frame across unchanged, then re-encodes chroma.
 *
 * The chroma rule is section 14 Q2's: a chroma sample is recomputed when its
 * 2x2 luma footprint intersects the region, and is otherwise copied from the
 * source. Because one chroma sample can serve pixels on both sides of the
 * region boundary, a boundary block is re-encoded from the post-effect RGB of
 * its whole footprint -- the documented shared-chroma influence, not a bug.
 *
 * Source and destination must be the same format and geometry.
 */
void yuv_kernel_v1_apply_effect(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    YuvRgbEffectV1 effect,
    void *context);

/* Builds a normalized region from a validated ABI region sub-struct. */
YuvRegionV1 yuv_kernel_v1_region(const YuvRegionOptionsV1 *options);

/* ===========================================================================
 * Blur driver
 * =========================================================================== */

/*
 * Convolves the visible RGB image and writes the result to the destination.
 *
 * Semantics are fixed by the Engineer decision of 2026-09-20 (edge-replicate)
 * and section 11:
 *
 *  - The kernel is always the full (2*radius+1)^2 for every output pixel,
 *    including at the border. A cell falling outside the image clamps its
 *    coordinate to the nearest edge, so an edge pixel enters the sum once per
 *    cell that landed on it.
 *  - The divisor is therefore always the full kernel weight, never the number
 *    of cells that happened to fall inside. The rejected alternative
 *    (shrinking the window) diverged from the oracle by more than the
 *    tolerance as radius grew.
 *  - Rounding is half-up, floor(value + 0.5), matching the oracle's round().
 *    Truncating biases every channel down by one step.
 *  - Alpha never enters the convolution: it is copied from the source pixel.
 *
 * `weights` is NULL for the uniform mean/box blur, or a (2*radius+1)^2 array
 * of Gaussian weights in raster order. Accumulation is in a type wide enough
 * that a full DCI 4K frame cannot overflow it, which the legacy int32_t
 * integral image could.
 *
 * The whole scratch snapshot is allocated once, before the first destination
 * write. On failure nothing has been written and YUV_STATUS_ALLOCATION_FAILED
 * is returned, so the destination is left exactly as the caller passed it.
 */
YuvStatus yuv_kernel_v1_blur(
    const YuvValidatedConstFrameView *source,
    const YuvValidatedMutableFrameView *destination,
    const YuvRegionV1 *region,
    uint32_t radius,
    const double *weights);

#endif  /* YUV_KERNEL_V1_H */
