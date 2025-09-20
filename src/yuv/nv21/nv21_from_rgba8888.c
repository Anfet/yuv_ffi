#include "..//yuv.h"

/**
 * Конвертирует RGBA8888 -> NV21.
 * Требования:
 *  - NV21: Y-плоскость + интерлив VU (именно V затем U)
 *  - uvPixelStride == 2 (для пары VU на каждый 2x2-блок)
 *  - Формулы совпадают с yuv420_from_rgba8888 (BT.601, видео диапазон)
 *
 * ВНИМАНИЕ к stride:
 *  - Здесь, как и в твоей исходной функции, stride для RGBA берётся как (yRowStride * 4).
 *    Если у RGBA есть свой отличный stride, лучше протащить отдельный параметр.
 */
FFI_PLUGIN_EXPORT void nv21_from_rgba8888(const uint8_t *rgba, const YUVDef *dst) {
    uint8_t *yPlane = dst->y;
    uint8_t *uv     = dst->u; // interleaved VU
    const int width        = dst->width;
    const int height       = dst->height;
    const int yRowStride   = dst->yRowStride;
    const int yPixelStride = dst->yPixelStride;
    const int uvRowStride  = dst->uvRowStride;
    const int uvPixelStride= dst->uvPixelStride; // ожидаем 2

    // (необязательно) защитимся от странного описателя:
    if (uvPixelStride != 2) return;

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            // Индекс в Y-плоскости
            const int yIndex = yuv_index(x, y, yRowStride, yPixelStride);
            // ВАЖНО: как и в твоём примере, используем yRowStride как "ширину" для RGBA
            const int rgbaIndex = (y * yRowStride + x) * 4;

            const int r = rgba[rgbaIndex + 0];
            const int g = rgba[rgbaIndex + 1];
            const int b = rgba[rgbaIndex + 2];

            // Те же коэффициенты (BT.601, видео-диапазон)
            const int yValue = CLAMP(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
            yPlane[yIndex] = (uint8_t)yValue;

            // Хрому пишем раз в 2x2
            if ((x % 2 == 0) && (y % 2 == 0)) {
                int sumU = 0, sumV = 0;

                const int x0 = x;
                const int y0 = y;

                // Собираем 2x2 блок; делаем так же, как в исходнике: с границами и делением на 4
                for (int dy = 0; dy < 2; ++dy) {
                    const int yy = y0 + dy;
                    if (yy >= height) continue;

                    const uint8_t *row = rgba + yy * yRowStride * 4;

                    for (int dx = 0; dx < 2; ++dx) {
                        const int xx = x0 + dx;
                        if (xx >= width) continue;

                        const uint8_t *p = row + xx * 4;
                        const int rr = p[0];
                        const int gg = p[1];
                        const int bb = p[2];

                        // U и V из RGBA
                        sumU += ((-38 * rr - 74 * gg + 112 * bb + 128) >> 8) + 128;
                        sumV += ((112 * rr - 94 * gg - 18 * bb + 128) >> 8) + 128;
                    }
                }

                // Индекс хромы для NV21 (VU-пара на каждый блок)
                const int uvIndex = yuv_index(x / 2, y / 2, uvRowStride, uvPixelStride);
                uv[uvIndex + 0] = (uint8_t)CLAMP(sumV / 4); // V
                uv[uvIndex + 1] = (uint8_t)CLAMP(sumU / 4); // U
            }
        }
    }
}
