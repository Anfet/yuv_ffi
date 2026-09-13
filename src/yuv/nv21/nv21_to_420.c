#include "../yuv.h"


// NV21 (Y + interleaved VU) -> I420 (Y + planar U, V)
// src->y : NV21 Y plane
// src->u : interleaved VU (row width = W)
// src->v : unused
// dst    : I420, where dst->u is the U plane and dst->v the V plane
//          (both sized W/2 x H/2)
FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Odd sizes: chroma is rounded up, matching the ceil allocation in Dart.
    const int cw = (W + 1) >> 1;
    const int ch = (H + 1) >> 1;

    // 1) Luma: row by row with separate source and destination strides. A
    // single memcpy of the source buffer size would overwrite the heap when
    // the destination stride is smaller.
    const int yCopyBytes = (src->yRowStride < dst->yRowStride ? src->yRowStride : dst->yRowStride);
    for (int y = 0; y < H; ++y) {
        const uint8_t *srow = src->y + (size_t)y * src->yRowStride;
        uint8_t *drow = dst->y + (size_t)y * dst->yRowStride;
        memcpy(drow, srow, yCopyBytes);
    }

    // 2) Chroma: split the interleaved VU data into planar U and V.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *sVU = src->u + (size_t)j * src->uvRowStride; // NV21 row: V,U,V,U,... (length W)
        // Destination rows are addressed with the destination's own stride.
        uint8_t *dU = dst->u + (size_t)j * dst->uvRowStride;
        uint8_t *dV = dst->v + (size_t)j * dst->uvRowStride;

        if (dst->uvPixelStride == 1) {
            // fast path
            for (int i = 0; i < cw; ++i) {
                dU[i] = sVU[(i << 1) + 0]; // U
                dV[i] = sVU[(i << 1) + 1]; // V
            }
        } else {
            // general case: the destination U/V planes have pixelStride > 1
            for (int i = 0; i < cw; ++i) {
                dU[i * dst->uvPixelStride] = sVU[(i << 1) + 0];
                dV[i * dst->uvPixelStride] = sVU[(i << 1) + 1];
            }
        }
    }
}
