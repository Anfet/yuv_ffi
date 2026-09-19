#include "../yuv.h"

// I420 -> the project's legacy `nv21` label (interleaved UV/NV12-like chroma).
// dst->y  : Y plane (stride = dst->yRowStride, usually W)
// dst->u  : UV plane (stride = dst->uvRowStride)
// dst->v  : unused (may be NULL)
FFI_PLUGIN_EXPORT void yuv420_i420_to_nv21(const YUVDef *src, YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Odd sizes: chroma is rounded up, matching the ceil allocation in Dart.
    const int cw = (W + 1) >> 1;   // chroma width
    const int ch = (H + 1) >> 1;   // chroma height

    // 1) Luma: copy sample by sample with separate source and destination
    // strides. A memcpy of min(rowStride) would carry padding bytes instead of
    // logical samples whenever the two planes use different pixel strides.
    const int srcYPixelStride = src->yPixelStride > 0 ? src->yPixelStride : 1;
    const int dstYPixelStride = dst->yPixelStride > 0 ? dst->yPixelStride : 1;
    for (int y = 0; y < H; ++y) {
        const uint8_t *srow = src->y + (size_t)y * src->yRowStride;
        uint8_t *drow = dst->y + (size_t)y * dst->yRowStride;
        if (srcYPixelStride == 1 && dstYPixelStride == 1) {
            memcpy(drow, srow, (size_t)W);
        } else {
            for (int x = 0; x < W; ++x) {
                drow[(size_t)x * dstYPixelStride] = srow[(size_t)x * srcYPixelStride];
            }
        }
    }

    // 2) Chroma: planar I420 U/V -> interleaved (U,V).
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
