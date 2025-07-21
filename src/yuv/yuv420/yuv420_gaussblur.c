#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../yuv/yuv420.h"
#include "../yuv/utils/h/yuv_utils.h"

// Генерация 1D гауссового ядра
static void generate_gaussian_kernel(float *kernel, int radius, float sigma) {
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

// Применение 1D гаусса по линии
static void apply_1d_gaussian(
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

// Размытие Y/U/V плоскости с учетом rowStride и pixelStride
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

    // Временный буфер: нормализованные байты, без stride
    uint8_t *tmp = (uint8_t *) malloc(width * height);

    // --- Горизонтальное размытие ---
    for (int y = 0; y < height; ++y) {
        uint8_t line_in[width];
        uint8_t line_out[width];

        const uint8_t *row_ptr = src + y * row_stride;

        for (int x = 0; x < width; ++x) {
            line_in[x] = row_ptr[x * pixel_stride];
        }

        apply_1d_gaussian(line_in, line_out, width, kernel, radius);

        for (int x = 0; x < width; ++x) {
            tmp[y * width + x] = line_out[x];
        }
    }

    // --- Вертикальное размытие ---
    for (int x = 0; x < width; ++x) {
        uint8_t col_in[height];
        uint8_t col_out[height];

        for (int y = 0; y < height; ++y) {
            col_in[y] = tmp[y * width + x];
        }

        apply_1d_gaussian(col_in, col_out, height, kernel, radius);

        for (int y = 0; y < height; ++y) {
            dst[y * row_stride + x * pixel_stride] = col_out[y];
        }
    }

    free(kernel);
    free(tmp);
}

void yuv420_gaussblur(
        const YUV420Def *src,
        int radius,
        int sigma
) {
    const int width = src->width;
    const int height = src->height;
    uint8_t *y_src = src->y;
    uint8_t *y_dst = src->y;
    uint8_t *u_src = src->u;
    uint8_t *u_dst = src->u;
    uint8_t *v_src = src->v;
    uint8_t *v_dst = src->v;
    const int y_row_stride = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;
    const int uv_pixel_stride = src->uvPixelStride;

    gaussian_blur_plane_strided(
            y_src, y_dst,
            width, height,
            y_row_stride, y_pixel_stride,
            radius, sigma
    );

    int uv_width = width / 2;
    int uv_height = height / 2;

    gaussian_blur_plane_strided(
            u_src, u_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, sigma
    );

    gaussian_blur_plane_strided(
            v_src, v_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, sigma
    );
}


