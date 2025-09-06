// nv21_to_i420.c
#include <stdint.h>
#include <string.h>
#include "yuv.h"

// Копируем Y (общая для NV21/I420)
static inline void copy_Y_from_src_to_dst(const YUVDef* src, const YUVDef* dst) {
    const int W = src->width, H = src->height;

    if (src->yPixelStride == 1 && src->yRowStride == W && dst->yRowStride == W) {
        memcpy(dst->y, src->y, (size_t)(W * H));
        return;
    }
    for (int y = 0; y < H; ++y) {
        const uint8_t* s = src->y + y * src->yRowStride;
        uint8_t* d = dst->y + y * dst->yRowStride;
        if (src->yPixelStride == 1) {
            memcpy(d, s, (size_t)W);
        } else {
            for (int x = 0; x < W; ++x) d[x] = s[x * src->yPixelStride];
        }
    }
}

// NV21 (Y + interleaved VU) -> I420 (Y + planar U, V)
// src->y : Y-плоскость NV21
// src->u : интерлив VU (ширина строки = W)
// src->v : не используется
// dst    : I420, где dst->u — U-план, dst->v — V-план (обе размером W/2 x H/2)
void nv21_to_i420(const YUVDef* src, const YUVDef* dst) {
    const int W  = src->width;
    const int H  = src->height;
    const int cw = W >> 1;
    const int ch = H >> 1;

    // 1) Luma
    copy_Y_from_src_to_dst(src, dst);

    // 2) Chroma: из интерлива VU разложим в U и V планарно.
    for (int j = 0; j < ch; ++j) {
        const uint8_t* sVU = src->u + j * src->uvRowStride; // NV21 строка: V,U,V,U,... (длина W)
        uint8_t* dU = dst->u + j * dst->uvRowStride;        // целевая U-строка (длина = cw при pixelStride=1)
        uint8_t* dV = dst->v + j * dst->uvRowStride;        // целевая V-строка

        if (dst->uvPixelStride == 1) {
            // быстрый путь
            for (int i = 0; i < cw; ++i) {
                dV[i] = sVU[(i << 1) + 0]; // V
                dU[i] = sVU[(i << 1) + 1]; // U
            }
        } else {
            // общий случай: у назначения U/V pixelStride > 1
            for (int i = 0; i < cw; ++i) {
                dV[i * dst->uvPixelStride] = sVU[(i << 1) + 0];
                dU[i * dst->uvPixelStride] = sVU[(i << 1) + 1];
            }
        }
    }
}
