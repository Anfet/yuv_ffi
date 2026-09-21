#include "../yuv.h"
#include "h/bgra8888_block_uv.h"

// BT.601 limited-range encode, consistent with the *_to_bgra8888 decode
// matrix used elsewhere in this project. Chroma is the average of the actual
// samples in each 2x2 block (not just the top-left sample), dividing by the
// real sample count so odd trailing rows/columns are not skewed. Legacy
// `nv21` established (U, V) byte order.
FFI_PLUGIN_EXPORT void bgra8888_to_nv21(const YUVDef *src, YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;

    for (int y = 0; y < H; ++y) {
        const uint8_t *row = src->y + (size_t) y * src->yRowStride;
        for (int x = 0; x < W; ++x) {
            const uint8_t *pixel = row + (size_t) x * src->yPixelStride;
            uint8_t B = pixel[0];
            uint8_t G = pixel[1];
            uint8_t R = pixel[2];

            int Y = ((66 * R + 129 * G + 25 * B + 128) >> 8) + 16;
            int yIndex = yuv_index(x, y, dst->yRowStride, dst->yPixelStride);
            dst->y[yIndex] = (uint8_t) CLAMP(Y);
        }
    }

    for (int by = 0; by < H; by += 2) {
        int j = by / 2;
        for (int bx = 0; bx < W; bx += 2) {
            int i = bx / 2;
            uint8_t U, V;
            bgra8888_block_uv(src, bx, by, &U, &V);

            int uvIndex = yuv_index(i, j, dst->uvRowStride, dst->uvPixelStride);
            dst->u[uvIndex] = U;
            dst->u[uvIndex + 1] = V;
        }
    }
}