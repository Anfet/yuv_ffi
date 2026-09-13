#include "../yuv.h"

// I420 (Y, U, V) -> NV21 (Y + interleaved VU).
// dst->y  : плоскость Y (stride = dst->yRowStride, обычно W)
// dst->u  : плоскость VU (stride = dst->uvRowStride, ДОЛЖНА быть W)
// dst->v  : не используется (может быть NULL)
FFI_PLUGIN_EXPORT void yuv420_i420_to_nv21(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Нечётные размеры: chroma округляется вверх, как и при аллокации в Dart.
    const int cw = (W + 1) >> 1;   // chroma width
    const int ch = (H + 1) >> 1;   // chroma height

    // 1) Luma: копируем построчно с раздельными stride источника и назначения.
    // Один memcpy на весь буфер источника переписал бы heap, если у
    // назначения stride меньше.
    const int yCopyBytes = (src->yRowStride < dst->yRowStride ? src->yRowStride : dst->yRowStride);
    for (int y = 0; y < H; ++y) {
        const uint8_t *srow = src->y + (size_t)y * src->yRowStride;
        uint8_t *drow = dst->y + (size_t)y * dst->yRowStride;
        memcpy(drow, srow, yCopyBytes);
    }

    // 2) Chroma: I420 планарные U/V -> NV21 интерлив (V,U) в строке шириной W.
    // Каждая строка dst VU должна иметь длину W байт: (V,U) пары на каждый i.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *urow = src->u + (size_t)j * src->uvRowStride;
        const uint8_t *vrow = src->v + (size_t)j * src->uvRowStride;

        uint8_t *drow = dst->u + (size_t)j * dst->uvRowStride;

        // общий случай с произвольным pixelStride у U/V
        for (int i = 0; i < cw; ++i) {
            const uint8_t V = vrow[i * src->uvPixelStride];
            const uint8_t U = urow[i * src->uvPixelStride];
            drow[(i << 1) + 0] = U; // NV12: U
            drow[(i << 1) + 1] = V; // затем V
        }
    }
}
