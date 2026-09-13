#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

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
            int idx = i + k;
            if (idx < 0) idx = 0;
            if (idx >= length) idx = length - 1;
            sum += kernel[k + radius] * src[idx];
            weight += kernel[k + radius];
        }
        dst[i] = (uint8_t)(sum / weight);
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
    generate_gaussian_kernel(kernel, radius, sigma);

    // Temporary buffer: normalized bytes, without stride
    uint8_t *tmp = (uint8_t *) malloc(width * height);

    // --- Horizontal blur ---
    for (int y = 0; y < height; ++y) {
        uint8_t* line_in = (uint8_t*)malloc(width);
        if (!line_in) return;
        uint8_t* line_out = (uint8_t*)malloc(width);
        if (!line_out) return;


        const uint8_t *row_ptr = src + y * row_stride;

        for (int x = 0; x < width; ++x) {
            line_in[x] = row_ptr[x * pixel_stride];
        }

        apply_1d_gaussian(line_in, line_out, width, kernel, radius);

        for (int x = 0; x < width; ++x) {
            tmp[y * width + x] = line_out[x];
        }
        free(line_in);
        free(line_out);
    }

    // --- Vertical blur ---
    for (int x = 0; x < width; ++x) {
        uint8_t* col_in = (uint8_t*)malloc(height);
        if (!col_in) return;
        uint8_t* col_out = (uint8_t*)malloc(height);
        if (!col_out) return;


        for (int y = 0; y < height; ++y) {
            col_in[y] = tmp[y * width + x];
        }

        apply_1d_gaussian(col_in, col_out, height, kernel, radius);

        for (int y = 0; y < height; ++y) {
            dst[y * row_stride + x * pixel_stride] = col_out[y];
        }
        free(col_in);
        free(col_out);
    }

    free(kernel);
    free(tmp);
}