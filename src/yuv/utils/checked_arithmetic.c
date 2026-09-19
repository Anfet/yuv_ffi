#include "h/checked_arithmetic.h"

/*
 * Checked addition: a + b
 * Returns {a + b, 1} if result fits in size_t, {0, 0} if overflow.
 */
YuvSizeResult yuv_checked_add(size_t a, size_t b) {
    YuvSizeResult result = {0, 0};
    if (a > SIZE_MAX - b) {
        return result;  /* overflow */
    }
    result.value = a + b;
    result.success = 1;
    return result;
}

/*
 * Checked multiplication: a * b
 * Returns {a * b, 1} if result fits in size_t, {0, 0} if overflow.
 */
YuvSizeResult yuv_checked_mul(size_t a, size_t b) {
    YuvSizeResult result = {0, 0};

    /* special case: 0 * anything = 0 */
    if (a == 0 || b == 0) {
        result.value = 0;
        result.success = 1;
        return result;
    }

    /* detect overflow: if a > SIZE_MAX / b, then a * b > SIZE_MAX */
    if (a > SIZE_MAX / b) {
        return result;  /* overflow */
    }

    result.value = a * b;
    result.success = 1;
    return result;
}

/*
 * Checked ceiling division by 2: ceil(value / 2)
 * Implemented as (value / 2) + (value % 2) to avoid overflow of (value + 1) / 2.
 * Division and modulo never overflow for size_t, so this always succeeds.
 */
YuvSizeResult yuv_checked_ceil_half(size_t value) {
    YuvSizeResult result;
    result.value = (value / 2) + (value % 2);
    result.success = 1;
    return result;
}

/*
 * Plane minimum span: (planeWidth - 1) * pixelStride + sampleBytes
 * When planeWidth == 0, span is sampleBytes.
 */
YuvSizeResult yuv_checked_plane_span(uint32_t plane_width, uint32_t pixel_stride, uint32_t sample_bytes) {
    YuvSizeResult result = {0, 0};

    /* when plane_width == 0, span is just sample_bytes */
    if (plane_width == 0) {
        result.value = sample_bytes;
        result.success = 1;
        return result;
    }

    /* span = (plane_width - 1) * pixel_stride + sample_bytes */
    YuvSizeResult mul_result = yuv_checked_mul((size_t)(plane_width - 1), (size_t)pixel_stride);
    if (!mul_result.success) {
        return result;  /* (plane_width - 1) * pixel_stride overflowed */
    }

    YuvSizeResult add_result = yuv_checked_add(mul_result.value, (size_t)sample_bytes);
    if (!add_result.success) {
        return result;  /* span addition overflowed */
    }

    result.value = add_result.value;
    result.success = 1;
    return result;
}

/*
 * Plane minimum allocation size: (planeHeight - 1) * rowStride + minSpan
 * When planeHeight == 0, size is minSpan.
 */
YuvSizeResult yuv_checked_plane_size(uint32_t plane_height, uint64_t row_stride, uint64_t min_span) {
    YuvSizeResult result = {0, 0};

    /* The ABI carries strides and lengths as uint64_t, while every result
       and checked primitive in this module is size_t-based. Reject values
       that cannot be represented before narrowing them, rather than turning
       (for example on a 32-bit target) a huge stride into a small one. */
    if (row_stride > SIZE_MAX || min_span > SIZE_MAX) {
        return result;
    }

    /* when plane_height == 0, size is just min_span */
    if (plane_height == 0) {
        result.value = min_span;
        result.success = 1;
        return result;
    }

    /* size = (plane_height - 1) * row_stride + min_span */
    YuvSizeResult mul_result = yuv_checked_mul((size_t)(plane_height - 1), (size_t)row_stride);
    if (!mul_result.success) {
        return result;  /* (plane_height - 1) * row_stride overflowed */
    }

    YuvSizeResult add_result = yuv_checked_add(mul_result.value, (size_t)min_span);
    if (!add_result.success) {
        return result;  /* size addition overflowed */
    }

    result.value = add_result.value;
    result.success = 1;
    return result;
}

/*
 * Sample offset in a plane: y * rowStride + x * pixelStride
 */
YuvSizeResult yuv_checked_sample_offset(uint32_t y, uint64_t row_stride, uint32_t x, uint32_t pixel_stride) {
    YuvSizeResult result = {0, 0};

    /* See yuv_checked_plane_size(): do not silently narrow ABI-width
       row_stride before handing it to the size_t checked primitives. */
    if (row_stride > SIZE_MAX) {
        return result;
    }

    /* x * pixel_stride */
    YuvSizeResult x_mul = yuv_checked_mul((size_t)x, (size_t)pixel_stride);
    if (!x_mul.success) {
        return result;
    }

    /* y * row_stride */
    YuvSizeResult y_mul = yuv_checked_mul((size_t)y, (size_t)row_stride);
    if (!y_mul.success) {
        return result;
    }

    /* y * row_stride + x * pixel_stride */
    YuvSizeResult final_add = yuv_checked_add(y_mul.value, x_mul.value);
    if (!final_add.success) {
        return result;
    }

    result.value = final_add.value;
    result.success = 1;
    return result;
}
