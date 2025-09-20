#include "..//yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_to_i420(const YUVDef *src, const YUVDef *dst) {
    const int W = src->width;
    const int H = src->height;

    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const uint8_t *pixel = src->y + y * src->yRowStride + x * src->yPixelStride;
            uint8_t B = pixel[0];
            uint8_t G = pixel[1];
            uint8_t R = pixel[2];

            int Y = (77 * R + 150 * G + 29 * B) >> 8;
            int U = ((-43 * R - 85 * G + 128 * B) >> 8) + 128;
            int V = ((128 * R - 107 * G - 21 * B) >> 8) + 128;

            // --- Y plane ---
            int yIndex = y * dst->yRowStride + x * dst->yPixelStride;
            dst->y[yIndex] = Y;

            // --- U/V subsampling (4:2:0) ---
            if ((y % 2 == 0) && (x % 2 == 0)) {
                int j = y / 2;
                int i = x / 2;

                int uvIndex = j * dst->uvRowStride + i * dst->uvPixelStride;
                memset(dst->u + uvIndex, U, dst->uvPixelStride);
                memset(dst->v + uvIndex, V, dst->uvPixelStride);
            }
        }
    }
}