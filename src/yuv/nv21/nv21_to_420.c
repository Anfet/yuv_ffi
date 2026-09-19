#include "../yuv.h"


// Legacy `nv21` label (Y + interleaved UV/NV12-like chroma) -> I420.
// src->y : luma plane
// src->u : interleaved UV (row width = 2 * ceil(W / 2))
// src->v : unused
// dst    : I420, where dst->u is the U plane and dst->v the V plane
//          (both sized W/2 x H/2)
FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef *src, YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;
    // Odd sizes: chroma is rounded up, matching the ceil allocation in Dart.
    const int cw = (W + 1) >> 1;
    const int ch = (H + 1) >> 1;

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

    // 2) Chroma: split the interleaved UV data into planar U and V.
    for (int j = 0; j < ch; ++j) {
        const uint8_t *sUV = src->u + (size_t)j * src->uvRowStride;
        // Destination rows are addressed with the destination's own stride.
        uint8_t *dU = dst->u + (size_t)j * dst->uvRowStride;
        uint8_t *dV = dst->v + (size_t)j * dst->uvRowStride;

        if (dst->uvPixelStride == 1) {
            // fast path
            for (int i = 0; i < cw; ++i) {
                dU[i] = sUV[(i << 1) + 0]; // U
                dV[i] = sUV[(i << 1) + 1]; // V
            }
        } else {
            // general case: the destination U/V planes have pixelStride > 1
            for (int i = 0; i < cw; ++i) {
                dU[i * dst->uvPixelStride] = sUV[(i << 1) + 0];
                dV[i * dst->uvPixelStride] = sUV[(i << 1) + 1];
            }
        }
    }
}
