#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../yuv/yuv.h"
#include "../yuv/utils/h/yuv_utils.h"

static void generate_gaussian_kernel(float *kernel, int radius, float sigma) {
    float sum = 0.0f;
    for (int i = -radius; i <= radius; ++i) {
        kernel[i + radius] = expf(-(i * i) / (2 * sigma * sigma));
        sum += kernel[i + radius];
    }
    for (int i = 0; i < 2 * radius + 1; ++i) kernel[i] /= sum;
}

void nv21_gaussian_blur(
        const YUVDef *src,
        int radius,
        float sigma
) {
    const int width = src->width;
    const int height = src->height;
    uint8_t *yData = src->y;
    uint8_t *uvData = src->v;

    int uvWidth = width / 2;
    int uvHeight = height / 2;

    float *kernel = (float*) malloc((2 * radius + 1) * sizeof(float));

    generate_gaussian_kernel(kernel, radius, sigma);

    // --- Y-плоскость ---
    uint8_t *tempY = (uint8_t*) malloc(width * height);
    memcpy(tempY, yData, width * height);

    // Горизонталь
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            float sum = 0.0f, weight = 0.0f;
            for (int k = -radius; k <= radius; ++k) {
                int xx = x + k;
                if (xx < 0) xx = 0;
                if (xx >= width) xx = width - 1;
                sum += kernel[k + radius] * tempY[y * width + xx];
                weight += kernel[k + radius];
            }
            yData[y * width + x] = (uint8_t)(sum / weight);
        }
    }

    // --- UV-плоскость ---
    uint8_t *tempUV = (uint8_t*) malloc(uvWidth * uvHeight * 2);
    memcpy(tempUV, uvData, uvWidth * uvHeight * 2);

    for (int y = 0; y < uvHeight; ++y) {
        for (int x = 0; x < uvWidth; ++x) {
            float sumV = 0, sumU = 0, weight = 0;
            for (int k = -radius; k <= radius; ++k) {
                int xx = x + k;
                if (xx < 0) xx = 0;
                if (xx >= uvWidth) xx = uvWidth - 1;
                int idx = y * uvWidth * 2 + xx * 2;
                sumV += kernel[k + radius] * tempUV[idx + 0];
                sumU += kernel[k + radius] * tempUV[idx + 1];
                weight += kernel[k + radius];
            }
            int dstIdx = y * uvWidth * 2 + x * 2;
            uvData[dstIdx + 0] = (uint8_t)(sumV / weight);
            uvData[dstIdx + 1] = (uint8_t)(sumU / weight);
        }
    }

    free(kernel);
    free(tempY);
    free(tempUV);
}