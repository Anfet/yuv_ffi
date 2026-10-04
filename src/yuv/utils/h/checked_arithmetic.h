#ifndef YUV_CHECKED_ARITHMETIC_H
#define YUV_CHECKED_ARITHMETIC_H

#include <stdint.h>
#include <stddef.h>
#include <limits.h>

/*
 * Checked arithmetic helpers for YUV geometry and allocation calculations.
 * All operations detect overflow before pointer arithmetic or memory access.
 * Helpers do not dereference data pointers.
 */

/*
 * Result of a checked arithmetic operation.
 * If `success` is true, `value` holds the result.
 * If `success` is false, the operation overflowed and `value` is undefined.
 */
typedef struct {
    size_t value;
    int success;
} YuvSizeResult;

/*
 * Checked addition of two size_t values.
 * Returns {a + b, 1} if no overflow, {0, 0} if overflow detected.
 */
YuvSizeResult yuv_checked_add(size_t a, size_t b);

/*
 * Checked multiplication of two size_t values.
 * Returns {a * b, 1} if no overflow, {0, 0} if overflow detected.
 */
YuvSizeResult yuv_checked_mul(size_t a, size_t b);

/*
 * Checked ceiling of division: ceil(value / 2).
 * Implemented as (value / 2) + (value % 2) to avoid overflow of (value + 1) / 2.
 * Returns {ceil(value / 2), 1} on success, {0, 0} if unreachable.
 */
YuvSizeResult yuv_checked_ceil_half(size_t value);

/*
 * Plane minimum span for given geometry and sample layout.
 *
 * Span = (planeWidth - 1) * pixelStride + sampleBytes
 * when planeWidth > 0, or sampleBytes when planeWidth == 0.
 *
 * Returns {span, 1} on success, {0, 0} on overflow.
 */
YuvSizeResult yuv_checked_plane_span(uint32_t plane_width, uint32_t pixel_stride, uint32_t sample_bytes);

/*
 * Plane minimum allocation size for given geometry and stride.
 *
 * Size = (planeHeight - 1) * rowStride + minSpan
 * when planeHeight > 0, or minSpan when planeHeight == 0.
 *
 * Use yuv_checked_plane_span() to compute minSpan.
 * Returns {size, 1} on success, {0, 0} on overflow.
 */
YuvSizeResult yuv_checked_plane_size(uint32_t plane_height, uint64_t row_stride, uint64_t min_span);

/*
 * Sample offset in a plane: index = y * rowStride + x * pixelStride
 *
 * Performs checked arithmetic to detect overflow before indexing.
 * Returns {offset, 1} on success, {0, 0} on overflow.
 */
YuvSizeResult yuv_checked_sample_offset(uint32_t y, uint64_t row_stride, uint32_t x, uint32_t pixel_stride);

#endif  // YUV_CHECKED_ARITHMETIC_H
