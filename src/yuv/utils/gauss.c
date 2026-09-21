#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "h/gauss.h"

void generate_gaussian_kernel(float *kernel, int radius, float sigma) {
    float sum = 0.0f;
    for (int i = -radius; i <= radius; ++i) {
        float x = (float) i;
        kernel[i + radius] = expf(-(x * x) / (2 * sigma * sigma));
        sum += kernel[i + radius];
    }
    for (int i = 0; i < 2 * radius + 1; ++i) {
        kernel[i] /= sum;
    }
}


// Applies a 1D gaussian along a line
void apply_1d_gaussian(
        const uint8_t *src, uint8_t *dst, int length,
        const float *kernel, int radius
) {
    for (int i = 0; i < length; ++i) {
        float sum = 0.0f;
        float weight = 0.0f;
        for (int k = -radius; k <= radius; ++k) {
            // Clamp-to-edge: every kernel tap still contributes, re-reading the
            // nearest in-bounds sample instead of being dropped, matching the
            // mandated 0.3.0 border contract.
            int idx = i + k;
            if (idx < 0) idx = 0;
            if (idx >= length) idx = length - 1;
            sum += kernel[k + radius] * src[idx];
            weight += kernel[k + radius];
        }
        // Round to nearest instead of truncating. generate_gaussian_kernel
        // normalizes the kernel to sum to 1, so `weight` is always that same
        // total regardless of clamping; dividing by it explicitly guards
        // against float drift instead of assuming weight == 1.0f.
        dst[i] = (uint8_t)(sum / weight + 0.5f);
    }
}

// Blurs a Y/U/V plane honouring rowStride and pixelStride, using an
// already-built kernel and caller-owned scratch. See gauss.h for the sizing
// contract on `scratch`. Arithmetic and rounding are unchanged from the
// original single-call implementation this factors out of: only the
// allocation lifetime moved to the caller.
void gaussian_blur_plane_strided_with_kernel(
        const uint8_t *src, uint8_t *dst,
        int width, int height,
        int row_stride,
        int pixel_stride,
        int radius,
        const float *kernel,
        YuvGaussianScratch *scratch
) {
    uint8_t *line_in = scratch->line_in;
    uint8_t *line_out = scratch->line_out;
    uint8_t *tmp = scratch->tmp;

    // --- Horizontal blur ---
    for (int y = 0; y < height; ++y) {
        const uint8_t *row_ptr = src + y * row_stride;

        for (int x = 0; x < width; ++x) {
            line_in[x] = row_ptr[x * pixel_stride];
        }

        apply_1d_gaussian(line_in, line_out, width, kernel, radius);

        for (int x = 0; x < width; ++x) {
            tmp[y * width + x] = line_out[x];
        }
    }

    // --- Vertical blur ---
    for (int x = 0; x < width; ++x) {
        for (int y = 0; y < height; ++y) {
            line_in[y] = tmp[y * width + x];
        }

        apply_1d_gaussian(line_in, line_out, height, kernel, radius);

        for (int y = 0; y < height; ++y) {
            dst[y * row_stride + x * pixel_stride] = line_out[y];
        }
    }
}

// Blurs a Y/U/V plane honouring rowStride and pixelStride
void gaussian_blur_plane_strided(
        const uint8_t *src, uint8_t *dst,
        int width, int height,
        int row_stride,
        int pixel_stride,
        int radius,
        float sigma
) {
    float *kernel = (float *) malloc((2 * radius + 1) * sizeof(float));
    // One row/column buffer pair, reused across every line and column instead
    // of a fresh malloc/free per iteration: fewer allocations, and no path
    // that can `return` early mid-loop while other buffers are still held.
    uint8_t *line_in = (uint8_t *) malloc((size_t) (width > height ? width : height));
    uint8_t *line_out = (uint8_t *) malloc((size_t) (width > height ? width : height));
    uint8_t *tmp = (uint8_t *) malloc((size_t) width * height);
    if (!kernel || !line_in || !line_out || !tmp) {
        free(kernel);
        free(line_in);
        free(line_out);
        free(tmp);
        return;
    }
    generate_gaussian_kernel(kernel, radius, sigma);

    YuvGaussianScratch scratch = {line_in, line_out, tmp};
    gaussian_blur_plane_strided_with_kernel(src, dst, width, height, row_stride, pixel_stride, radius, kernel, &scratch);

    free(kernel);
    free(line_in);
    free(line_out);
    free(tmp);
}