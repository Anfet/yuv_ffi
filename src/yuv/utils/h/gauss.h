#ifndef GAUSS_H
#define GAUSS_H

#include <stdint.h>

void generate_gaussian_kernel(float *kernel, int radius, float sigma);


// Applies a 1D gaussian along a line
void apply_1d_gaussian(
        const uint8_t *src, uint8_t *dst, int length,
        const float *kernel, int radius
);

// Blurs a Y/U/V plane honouring rowStride and pixelStride. Builds its own
// kernel and scratch on every call; kept for callers that blur a single
// plane in isolation. A caller blurring several planes for the same public
// operation (Y, then U, then V) should prefer
// gaussian_blur_plane_strided_with_kernel() below so the kernel is built once
// and the scratch buffers are reused instead of malloc'd per plane.
void gaussian_blur_plane_strided(
        const uint8_t *src, uint8_t *dst,
        int width, int height,
        int row_stride,
        int pixel_stride,
        int radius,
        float sigma
);

// Bounded scratch shared across every plane of one public blur call. `line`
// must hold max(width, height) samples per buffer and `tmp` width * height
// samples, sized once by the caller for the largest plane it will pass (the
// luma plane, which is always >= the chroma planes here) and reused for the
// smaller ones without re-allocating.
typedef struct {
    uint8_t *line_in;
    uint8_t *line_out;
    uint8_t *tmp;
} YuvGaussianScratch;

// Same convolution as gaussian_blur_plane_strided(), but takes an
// already-built kernel and caller-owned scratch instead of allocating its
// own. `scratch->tmp` must be at least width * height bytes and the line
// buffers at least max(width, height) bytes; the caller is responsible for
// sizing them to the largest plane it will reuse them across.
void gaussian_blur_plane_strided_with_kernel(
        const uint8_t *src, uint8_t *dst,
        int width, int height,
        int row_stride,
        int pixel_stride,
        int radius,
        const float *kernel,
        YuvGaussianScratch *scratch
);

#endif
