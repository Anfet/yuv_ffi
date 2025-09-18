#include <stdint.h>
#include <stdlib.h>
#include "../yuv/yuv.h"
#include "../yuv/utils/h/yuv_utils.h"

void nv21_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
) {
    uint8_t *yData = src->y;
    uint8_t *uvData = src->v; // в NV21 здесь хранится интерливное VU
    const int width = src->width;
    const int height = src->height;

    int left   = rect ? rect[0] : 0;
    int top    = rect ? rect[1] : 0;
    int right  = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    // --- Y-плоскость (полное усреднение) ---
    uint8_t *yTemp = (uint8_t*) malloc(width * height);
    memcpy(yTemp, yData, width * height);

    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            int sum = 0, count = 0;

            for (int dy = -radius; dy <= radius; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= height) continue;
                for (int dx = -radius; dx <= radius; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= width) continue;
                    sum += yTemp[ny * width + nx];
                    count++;
                }
            }
            yData[y * width + x] = (uint8_t)(sum / count);
        }
    }

    free(yTemp);

    // --- UV-плоскость (half resolution) ---
    int uvWidth = width / 2;
    int uvHeight = height / 2;

    uint8_t *uvTemp = (uint8_t*) malloc(uvWidth * uvHeight * 2);
    memcpy(uvTemp, uvData, uvWidth * uvHeight * 2);

    for (int y = 0; y < uvHeight; ++y) {
        for (int x = 0; x < uvWidth; ++x) {
            int sumU = 0, sumV = 0, count = 0;

            for (int dy = -radius; dy <= radius; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= uvHeight) continue;
                for (int dx = -radius; dx <= radius; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= uvWidth) continue;
                    int idx = (ny * uvWidth + nx) * 2;
                    sumV += uvTemp[idx + 0];
                    sumU += uvTemp[idx + 1];
                    count++;
                }
            }

            int dstIdx = (y * uvWidth + x) * 2;
            uvData[dstIdx + 0] = (uint8_t)(sumV / count);
            uvData[dstIdx + 1] = (uint8_t)(sumU / count);
        }
    }

    free(uvTemp);
}