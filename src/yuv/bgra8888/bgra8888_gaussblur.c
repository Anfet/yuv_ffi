#include "../yuv.h"


FFI_PLUGIN_EXPORT void bgra8888_gaussian_blur(
        YUVDef *image,
        int radius,
        float sigma
) {
    const int width = image->width;
    const int height = image->height;
    const int bytesPerPixel = 4;
    const int rowStride = image->yRowStride;

    uint8_t *data = image->y;
    uint8_t *temp = (uint8_t *) malloc(width * height * bytesPerPixel);
    if (!temp) return;

    float *kernel = (float *) malloc((2 * radius + 1) * sizeof(float));
    generate_gaussian_kernel(kernel, radius, sigma);

    // --- Horizontal blur ---
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            for (int c = 0; c < 4; ++c) {
                float sum = 0.0f, weight = 0.0f;
                for (int k = -radius; k <= radius; ++k) {
                    int xx = x + k;
                    if (xx < 0) xx = 0;
                    if (xx >= width) xx = width - 1;
                    sum += kernel[k + radius] * data[y * rowStride + xx * bytesPerPixel + c];
                    weight += kernel[k + radius];
                }
                temp[y * rowStride + x * bytesPerPixel + c] = (uint8_t)(sum / weight);
            }
        }
    }

    // --- Vertical blur ---
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            for (int c = 0; c < 4; ++c) {
                float sum = 0.0f, weight = 0.0f;
                for (int k = -radius; k <= radius; ++k) {
                    int yy = y + k;
                    if (yy < 0) yy = 0;
                    if (yy >= height) yy = height - 1;
                    sum += kernel[k + radius] * temp[yy * rowStride + x * bytesPerPixel + c];
                    weight += kernel[k + radius];
                }
                data[y * rowStride + x * bytesPerPixel + c] = (uint8_t)(sum / weight);
            }
        }
    }

    free(temp);
    free(kernel);
}
