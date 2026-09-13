#include "../yuv.h"

// I420 (Y, U, V) -> NV21 (Y + interleaved VU).
// dst->y  : Y plane (stride = dst->yRowStride, usually W)
// dst->u  : VU plane (stride = dst->uvRowStride, MUST be W)
// dst->v  : unused (may be NULL)
FFI_PLUGIN_EXPORT void yuv420_i420_to_nv21(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Odd sizes: chroma is rounded up, matching the ceil allocation in Dart.
    const int cw = (W + 1) >> 1;   // chroma width
    const int ch = (H + 1) >> 1;   // chroma height

    // 1) Luma: copy row by row with separate source and destination strides.
    // A single memcpy of the whole source buffer would overwrite the heap when
    // the destination stride is smaller.
    const int yCopyBytes = (src->yRowStride < dst->yRowStride ? src->yRowStride : dst->yRowStride);
    for (int y = 0; y < H; ++y) {
        const uint8_t *srow = src->y + (size_t)y * src->yRowStride;
        uint8_t *drow = dst->y + (size_t)y * dst->yRowStride;
        memcpy(drow, srow, yCopyBytes);
    }

    // 2) Chroma: planar I420 U/V -> NV21 interleaved (V,U) in a row of width W.
    // Every destination VU row must be W bytes long: a (V,U) pair per i.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *urow = src->u + (size_t)j * src->uvRowStride;
        const uint8_t *vrow = src->v + (size_t)j * src->uvRowStride;

        uint8_t *drow = dst->u + (size_t)j * dst->uvRowStride;

        // general case, with an arbitrary pixelStride on U/V
        for (int i = 0; i < cw; ++i) {
            const uint8_t V = vrow[i * src->uvPixelStride];
            const uint8_t U = urow[i * src->uvPixelStride];
            drow[(i << 1) + 0] = U; // NV12: U
            drow[(i << 1) + 1] = V; // then V
        }
    }
}
