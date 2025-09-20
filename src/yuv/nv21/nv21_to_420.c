#include "..//yuv.h"


// NV21 (Y + interleaved VU) -> I420 (Y + planar U, V)
// src->y : Y-плоскость NV21
// src->u : интерлив VU (ширина строки = W)
// src->v : не используется
// dst    : I420, где dst->u — U-план, dst->v — V-план (обе размером W/2 x H/2)
FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    const int cw = W >> 1;
    const int ch = H >> 1;

    memcpy(dst->y, src->y, src->height * src->yRowStride);

    // 2) Chroma: из интерлива VU разложим в U и V планарно.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *sVU = src->u + j * src->uvRowStride; // NV21 строка: V,U,V,U,... (длина W)
        uint8_t *dU = dst->u + j * dst->uvRowStride;        // целевая U-строка (длина = cw при pixelStride=1)
        uint8_t *dV = dst->v + j * dst->uvRowStride;        // целевая V-строка

        if (dst->uvPixelStride == 1) {
            // быстрый путь
            for (int i = 0; i < cw; ++i) {
                dU[i] = sVU[(i << 1) + 0]; // U
                dV[i] = sVU[(i << 1) + 1]; // V
            }
        } else {
            // общий случай: у назначения U/V pixelStride > 1
            for (int i = 0; i < cw; ++i) {
                dU[i * dst->uvPixelStride] = sVU[(i << 1) + 0];
                dV[i * dst->uvPixelStride] = sVU[(i << 1) + 1];
            }
        }
    }
}
