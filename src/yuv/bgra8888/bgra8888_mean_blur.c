#include <stdint.h>
#include <stdlib.h>
#include "../yuv/utils/h/yuv_utils.h"
#include "../yuv/yuv.h"

void bgra8888_mean_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
) {
    uint8_t *data = src->y;
    const int width = src->width;
    const int height = src->height;
    const int rowStride = src->yRowStride;   // width * 4
    const int bytesPerPixel = 4;

    int left   = rect ? rect[0] : 0;
    int top    = rect ? rect[1] : 0;
    int right  = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    // Интегральные изображения (int для переполнения)
    int32_t *satB = (int32_t*) calloc(width * height, sizeof(int32_t));
    int32_t *satG = (int32_t*) calloc(width * height, sizeof(int32_t));
    int32_t *satR = (int32_t*) calloc(width * height, sizeof(int32_t));
    int32_t *satA = (int32_t*) calloc(width * height, sizeof(int32_t));

    if (!satB || !satG || !satR || !satA) {
        free(satB); free(satG); free(satR); free(satA);
        return;
    }

    // Построение summed area table
    for (int y = 0; y < height; ++y) {
        int32_t rowB = 0, rowG = 0, rowR = 0, rowA = 0;
        for (int x = 0; x < width; ++x) {
            int idx = y * rowStride + x * bytesPerPixel;
            rowB += data[idx + 0];
            rowG += data[idx + 1];
            rowR += data[idx + 2];
            rowA += data[idx + 3];

            int prevIdx = (y - 1) * width + x;
            int curIdx = y * width + x;

            satB[curIdx] = rowB + (y > 0 ? satB[prevIdx] : 0);
            satG[curIdx] = rowG + (y > 0 ? satG[prevIdx] : 0);
            satR[curIdx] = rowR + (y > 0 ? satR[prevIdx] : 0);
            satA[curIdx] = rowA + (y > 0 ? satA[prevIdx] : 0);
        }
    }

    // Размытие
    uint8_t *temp = (uint8_t*) malloc(width * height * bytesPerPixel);
    if (!temp) {
        free(satB); free(satG); free(satR); free(satA);
        return;
    }

    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            int x1 = (x - radius < 0) ? 0 : x - radius;
            int y1 = (y - radius < 0) ? 0 : y - radius;
            int x2 = (x + radius >= width) ? width - 1 : x + radius;
            int y2 = (y + radius >= height) ? height - 1 : y + radius;

            int A = y1 * width + x1;
            int B = y1 * width + x2;
            int C = y2 * width + x1;
            int D = y2 * width + x2;

            int area = (x2 - x1 + 1) * (y2 - y1 + 1);

            int sumB = satB[D] - (y1 > 0 ? satB[B] : 0) - (x1 > 0 ? satB[C] : 0) + (x1 > 0 && y1 > 0 ? satB[A] : 0);
            int sumG = satG[D] - (y1 > 0 ? satG[B] : 0) - (x1 > 0 ? satG[C] : 0) + (x1 > 0 && y1 > 0 ? satG[A] : 0);
            int sumR = satR[D] - (y1 > 0 ? satR[B] : 0) - (x1 > 0 ? satR[C] : 0) + (x1 > 0 && y1 > 0 ? satR[A] : 0);
            int sumA = satA[D] - (y1 > 0 ? satA[B] : 0) - (x1 > 0 ? satA[C] : 0) + (x1 > 0 && y1 > 0 ? satA[A] : 0);

            int dstIdx = y * rowStride + x * bytesPerPixel;
            temp[dstIdx + 0] = (uint8_t)(sumB / area);
            temp[dstIdx + 1] = (uint8_t)(sumG / area);
            temp[dstIdx + 2] = (uint8_t)(sumR / area);
            temp[dstIdx + 3] = (uint8_t)(sumA / area);
        }
    }

    memcpy(data, temp, width * height * bytesPerPixel);

    free(temp);
    free(satB); free(satG); free(satR); free(satA);
}