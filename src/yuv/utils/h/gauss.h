#ifndef GAUSS_H
#define GAUSS_H

void generate_gaussian_kernel(float *kernel, int radius, float sigma);


// Применение 1D гаусса по линии
void apply_1d_gaussian(
        const uint8_t *src, uint8_t *dst, int length,
        const float *kernel, int radius
);

// Размытие Y/U/V плоскости с учетом rowStride и pixelStride
void gaussian_blur_plane_strided(
        const uint8_t *src, uint8_t *dst,
        int width, int height,
        int row_stride,
        int pixel_stride,
        int radius,
        float sigma
);

#endif
