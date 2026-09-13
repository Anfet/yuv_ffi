#include "../yuv.h"


// NV21 (Y + interleaved VU) -> I420 (Y + planar U, V)
// src->y : Y-плоскость NV21
// src->u : интерлив VU (ширина строки = W)
// src->v : не используется
// dst    : I420, где dst->u — U-план, dst->v — V-план (обе размером W/2 x H/2)
FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Нечётные размеры: chroma округляется вверх, как и при аллокации в Dart.
    const int cw = (W + 1) >> 1;
    const int ch = (H + 1) >> 1;

    // 1) Luma: построчно с раздельными stride источника и назначения. Один
    // memcpy размера исходного буфера переписал бы heap при меньшем stride
    // назначения.
    const int yCopyBytes = (src->yRowStride < dst->yRowStride ? src->yRowStride : dst->yRowStride);
    for (int y = 0; y < H; ++y) {
        const uint8_t *srow = src->y + (size_t)y * src->yRowStride;
        uint8_t *drow = dst->y + (size_t)y * dst->yRowStride;
        memcpy(drow, srow, yCopyBytes);
    }

    // 2) Chroma: из интерлива VU разложим в U и V планарно.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *sVU = src->u + (size_t)j * src->uvRowStride; // NV21 строка: V,U,V,U,... (длина W)
        // Строки назначения адресуются собственным stride назначения.
        uint8_t *dU = dst->u + (size_t)j * dst->uvRowStride;
        uint8_t *dV = dst->v + (size_t)j * dst->uvRowStride;

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
