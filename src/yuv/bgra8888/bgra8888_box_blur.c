#include <stdint.h>
#include <stdlib.h>
#include "../yuv/utils/h/yuv_utils.h"
#include "../yuv/yuv.h"

void bgra8888_box_blur(
        const YUVDef *src,
        int radius
) {
    const int width = src->width;
    const int height = src->height;
    const int bytesPerPixel = 4;
    const int rowStride = src->yRowStride;

    uint8_t *data = src->y; // трактуем как BGRA
    uint8_t *temp = (uint8_t *) malloc(width * height * bytesPerPixel);
    if (!temp) return;

    // --- Горизонтальный проход ---
    for (int y = 0; y < height; ++y) {
        for (int c = 0; c < 4; ++c) {
            int sum = 0;
            for (int dx = -radius; dx <= radius; ++dx) {
                int x = dx < 0 ? 0 : (dx >= width ? width - 1 : dx);
                sum += data[y * rowStride + x * bytesPerPixel + c];
            }
            temp[y * rowStride + 0 * bytesPerPixel + c] =
                    (uint8_t)(sum / (2 * radius + 1));

            for (int x = 1; x < width; ++x) {
                int x_add = (x + radius < width) ? x + radius : width - 1;
                int x_remove = (x - radius - 1 >= 0) ? x - radius - 1 : 0;

                sum += data[y * rowStride + x_add * bytesPerPixel + c];
                sum -= data[y * rowStride + x_remove * bytesPerPixel + c];

                temp[y * rowStride + x * bytesPerPixel + c] =
                        (uint8_t)(sum / (2 * radius + 1));
            }
        }
    }

    // --- Вертикальный проход ---
    for (int x = 0; x < width; ++x) {
        for (int c = 0; c < 4; ++c) {
            int sum = 0;
            for (int dy = -radius; dy <= radius; ++dy) {
                int y = dy < 0 ? 0 : (dy >= height ? height - 1 : dy);
                sum += temp[y * rowStride + x * bytesPerPixel + c];
            }
            data[0 * rowStride + x * bytesPerPixel + c] =
                    (uint8_t)(sum / (2 * radius + 1));

            for (int y = 1; y < height; ++y) {
                int y_add = (y + radius < height) ? y + radius : height - 1;
                int y_sub = (y - radius - 1 >= 0) ? y - radius - 1 : 0;

                sum += temp[y_add * rowStride + x * bytesPerPixel + c];
                sum -= temp[y_sub * rowStride + x * bytesPerPixel + c];

                data[y * rowStride + x * bytesPerPixel + c] =
                        (uint8_t)(sum / (2 * radius + 1));
            }
        }
    }

    free(temp);
}