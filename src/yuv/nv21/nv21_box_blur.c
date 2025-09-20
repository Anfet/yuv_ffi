#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
) {
    const int width  = src->width;
    const int height = src->height;
    const int rowStride   = src->yRowStride;
    const int pixelStride = src->yPixelStride;
    uint8_t *dst = src->y;

    uint32_t left = 0, top = 0, right = width, bottom = height;
    if (rect) {
        left   = rect[0];
        top    = rect[1];
        right  = rect[2];
        bottom = rect[3];
    }

    uint8_t *temp = (uint8_t *) malloc(height * rowStride);
    if (!temp) return;

    // --- Горизонтальный проход (Y) ---
    for (int y = 0; y < height; ++y) {
        const uint8_t *row    = src->y + y * rowStride;
        uint8_t *temp_row     = temp   + y * rowStride;

        int sum = 0;
        for (int dx = -radius; dx <= radius; ++dx) {
            int x = MIN(width - 1, MAX(0, dx));
            sum += row[x * pixelStride];
        }
        temp_row[0 * pixelStride] = (uint8_t)(sum / (2 * radius + 1));

        for (int x = 1; x < width; ++x) {
            int x_add    = MIN(width - 1, x + radius);
            int x_remove = MAX(0, x - radius - 1);
            sum += row[x_add * pixelStride] - row[x_remove * pixelStride];
            temp_row[x * pixelStride] = (uint8_t)(sum / (2 * radius + 1));
        }
    }

    // --- Вертикальный проход (Y) ---
    for (int x = 0; x < width; ++x) {
        int sum = 0;
        for (int dy = -radius; dy <= radius; ++dy) {
            int yy = MIN(height - 1, MAX(0, dy));
            sum += temp[yy * rowStride + x * pixelStride];
        }

        for (int y = 0; y < height; ++y) {
            int dstIndex = yuv_index(x, y, rowStride, pixelStride);
            uint8_t original = src->y[dstIndex];

            if (x < (int)left || x >= (int)right ||
                y < (int)top  || y >= (int)bottom) {
                dst[dstIndex] = original;
            } else {
                dst[dstIndex] = (uint8_t)(sum / (2 * radius + 1));
            }

            if (y + 1 < height) {
                int y_add = MIN(height - 1, y + radius + 1);
                int y_sub = MAX(0, y - radius);
                sum += temp[y_add * rowStride + x * pixelStride];
                sum -= temp[y_sub * rowStride + x * pixelStride];
            }
        }
    }

    free(temp);

    // --- UV (VU interleaved) ---
    const int uv_width  = width  / 2;
    const int uv_height = height / 2;

    uint8_t *u_plane = (uint8_t *) malloc(uv_width * uv_height);
    uint8_t *v_plane = (uint8_t *) malloc(uv_width * uv_height);

    // Распаковка
    for (int y = 0; y < uv_height; ++y) {
        const uint8_t *row = src->u + y * src->uvRowStride;
        for (int x = 0; x < uv_width; ++x) {
            v_plane[y * uv_width + x] = row[x * 2 + 0];
            u_plane[y * uv_width + x] = row[x * 2 + 1];
        }
    }

    // Размытие U и V так же, как Y (с box blur)
    // ⚠️ Упрощённо: без rect, т.к. в NV21 UV соответствует 2×2 блокам Y
    // Если нужен rect и на UV — придётся аккуратно учитывать even coords.
    for (int y = 0; y < uv_height; ++y) {
        for (int x = 0; x < uv_width; ++x) {
            int sumU = 0, sumV = 0, count = 0;
            for (int dy = -radius; dy <= radius; ++dy) {
                int yy = MIN(uv_height - 1, MAX(0, y + dy));
                for (int dx = -radius; dx <= radius; ++dx) {
                    int xx = MIN(uv_width - 1, MAX(0, x + dx));
                    sumU += u_plane[yy * uv_width + xx];
                    sumV += v_plane[yy * uv_width + xx];
                    count++;
                }
            }
            u_plane[y * uv_width + x] = (uint8_t)(sumU / count);
            v_plane[y * uv_width + x] = (uint8_t)(sumV / count);
        }
    }

    // Сборка обратно в interleaved VU
    for (int y = 0; y < uv_height; ++y) {
        uint8_t *row = src->u + y * src->uvRowStride;
        for (int x = 0; x < uv_width; ++x) {
            row[x * 2 + 0] = v_plane[y * uv_width + x];
            row[x * 2 + 1] = u_plane[y * uv_width + x];
        }
    }

    free(u_plane);
    free(v_plane);
}
