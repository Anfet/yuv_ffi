// nv21_crop_rect.c
#include <stdint.h>
#include <string.h>
#include "yuv.h"

// Кроп NV21 (Y + interleaved VU) в прямоугольник [left, top, crop_width, crop_height].
// src:  NV21 (src->y = Y, src->u = VU, src->v не используется)
// dst:  NV21 (dst->y = Y, dst->u = VU, dst->v не используется)
// Требование: прямоугольник целиком в пределах кадра.
// Важно: для хромы NV21 координаты должны быть чётными; мы приводим к чётным.
void nv21_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        int left, int top,
        int crop_width, int crop_height) {
    const int W = src->width;
    const int H = src->height;

// --------- 1) Кроп Y-плоскости ----------
// Поддерживаем произвольные yPixelStride/rowStride.
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t *srow = src->y + (top + row) * src->yRowStride + left * src->yPixelStride;
        uint8_t *drow = dst->y + row * dst->yRowStride;

        if (src->yPixelStride == 1) {
            memcpy(drow, srow, (size_t) crop_width);
        } else {
            for (int x = 0; x < crop_width; ++x)
                drow[x] = srow[x * src->yPixelStride];
        }
    }

// --------- 2) Кроп VU-плоскости (интерлив, ширина строки = W байт) ----------
// Приводим к чётным — NV21 субсемплирование 4:2:0.
    const int uv_left = left & ~1;
    const int uv_top = top & ~1;
    const int uv_width = crop_width & ~1;  // число Y-пикселей по ширине (чётное)
    const int uv_height = crop_height & ~1;  // число Y-пикселей по высоте (чётное)

    const int cw = uv_width >> 1;           // ширина U/V в сэмплах
    const int ch = uv_height >> 1;           // высота U/V в сэмплах

// Смещение по исходной VU-плоскости: каждые 2 пикселя Y -> 2 байта (V,U)
    const int srcVU_xBytes = (uv_left >> 1) * 2;
    const int srcVU_yStart = uv_top >> 1;

    for (int j = 0; j < ch; ++j) {
        const uint8_t *sVU = src->u + (srcVU_yStart + j) * src->uvRowStride + srcVU_xBytes;
        uint8_t *dVU = dst->u + j * dst->uvRowStride;

// В каждой строке нужно скопировать cw пар (V,U) → 2*cw байт
        memcpy(dVU, sVU, (size_t)(cw * 2));
    }
}
