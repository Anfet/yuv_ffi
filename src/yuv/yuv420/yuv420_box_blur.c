#include <stdint.h>
#include <stdlib.h>
#include "../yuv/yuv420.h"
#include "../yuv/utils/h/yuv_utils.h"

void yuv420_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
) {
    const int width = src->width;
    const int height = src->height;
    const int rowStride = src->yRowStride;
    const int pixelStride = src->yPixelStride;
    uint8_t *dst = src->y;

    uint32_t left = 0, top = 0, right = width, bottom = height;
    if (rect) {
        left = rect[0];
        top = rect[1];
        right = rect[2];
        bottom = rect[3];
    }

    uint8_t *temp = (uint8_t *) malloc(height * rowStride);
    if (!temp) return;

    for (int y = 0; y < height; ++y) {
        const uint8_t *row = src->y + y * rowStride;
        uint8_t *temp_row = temp + y * rowStride;

        int sum = 0;
        for (int dx = -radius; dx <= radius; ++dx) {
            int x = MIN(width - 1, MAX(0, dx));
            sum += row[x * pixelStride];
        }

        temp_row[0 * pixelStride] = (uint8_t)(sum / (2 * radius + 1));

        for (int x = 1; x < width; ++x) {
            int x_add = MIN(width - 1, x + radius);
            int x_remove = MAX(0, x - radius - 1);
            sum += row[x_add * pixelStride] - row[x_remove * pixelStride];
            temp_row[x * pixelStride] = (uint8_t)(sum / (2 * radius + 1));
        }
    }

    // Вертикальный проход (ускоренный)
    for (int x = 0; x < width; ++x) {
        int sum = 0;

        // начальная сумма на первом пикселе
        for (int dy = -radius; dy <= radius; ++dy) {
            int yy = MIN(height - 1, MAX(0, dy));
            sum += temp[yy * rowStride + x * pixelStride];
        }

        for (int y = 0; y < height; ++y) {
            int dstIndex = yuv_index(x, y, rowStride, pixelStride);
            uint8_t original = src->y[dstIndex];

            if (x < left || x >= right || y < top || y >= bottom) {
                dst[dstIndex] = original;
            } else {
                dst[dstIndex] = (uint8_t)(sum / (2 * radius + 1));
            }

            // подготавливаем сумму для следующего y
            if (y + 1 < height) {
                int y_add = MIN(height - 1, y + radius + 1);
                int y_sub = MAX(0, y - radius);
                sum += temp[y_add * rowStride + x * pixelStride];
                sum -= temp[y_sub * rowStride + x * pixelStride];
            }
        }
    }

    free(temp);
}