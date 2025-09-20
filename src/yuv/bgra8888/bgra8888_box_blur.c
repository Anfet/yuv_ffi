#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
) {
    const int width  = src->width;
    const int height = src->height;
    const int stride = src->yRowStride;   // bytes per row
    const int bpp    = 4;                 // BGRA

    uint8_t *dst = src->y;

    uint32_t left = 0, top = 0, right = width, bottom = height;
    if (rect) {
        left   = rect[0];
        top    = rect[1];
        right  = rect[2];
        bottom = rect[3];
    }

    uint8_t *temp = (uint8_t *) malloc(height * stride);
    if (!temp) return;

    // --- Горизонтальный проход ---
    for (int y = 0; y < height; ++y) {
        const uint8_t *row = src->y + y * stride;
        uint8_t *temp_row  = temp + y * stride;

        for (int c = 0; c < bpp; ++c) {
            int sum = 0;
            for (int dx = -radius; dx <= radius; ++dx) {
                int x = dx < 0 ? 0 : (dx >= width ? width - 1 : dx);
                sum += row[x * bpp + c];
            }
            temp_row[0 * bpp + c] = (uint8_t)(sum / (2 * radius + 1));

            for (int x = 1; x < width; ++x) {
                int x_add    = (x + radius < width) ? x + radius : width - 1;
                int x_remove = (x - radius - 1 >= 0) ? x - radius - 1 : 0;
                sum += row[x_add * bpp + c];
                sum -= row[x_remove * bpp + c];
                temp_row[x * bpp + c] = (uint8_t)(sum / (2 * radius + 1));
            }
        }
    }

    // --- Вертикальный проход ---
    for (int x = 0; x < width; ++x) {
        for (int c = 0; c < bpp; ++c) {
            int sum = 0;
            for (int dy = -radius; dy <= radius; ++dy) {
                int yy = dy < 0 ? 0 : (dy >= height ? height - 1 : dy);
                sum += temp[yy * stride + x * bpp + c];
            }

            for (int y = 0; y < height; ++y) {
                int idx = y * stride + x * bpp + c;
                uint8_t original = src->y[idx];

                if (x < (int)left || x >= (int)right ||
                    y < (int)top  || y >= (int)bottom) {
                    dst[idx] = original; // оставляем как есть
                } else {
                    dst[idx] = (uint8_t)(sum / (2 * radius + 1));
                }

                if (y + 1 < height) {
                    int y_add = (y + radius + 1 < height) ? y + radius + 1 : height - 1;
                    int y_sub = (y - radius >= 0) ? y - radius : 0;
                    sum += temp[y_add * stride + x * bpp + c];
                    sum -= temp[y_sub * stride + x * bpp + c];
                }
            }
        }
    }

    free(temp);
}
