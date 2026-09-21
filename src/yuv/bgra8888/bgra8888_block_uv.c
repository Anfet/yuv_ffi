#include "../yuv.h"
#include "h/bgra8888_block_uv.h"

void bgra8888_block_uv(const YUVDef *src, int bx, int by, uint8_t *outU, uint8_t *outV) {
    const int W = src->width;
    const int H = src->height;

    int sumR = 0, sumG = 0, sumB = 0, samples = 0;
    for (int oy = 0; oy < 2; ++oy) {
        int py = by + oy;
        if (py >= H) continue;
        const uint8_t *row = src->y + (size_t) py * src->yRowStride;
        for (int ox = 0; ox < 2; ++ox) {
            int px = bx + ox;
            if (px >= W) continue;
            const uint8_t *pixel = row + (size_t) px * src->yPixelStride;
            sumB += pixel[0];
            sumG += pixel[1];
            sumR += pixel[2];
            samples++;
        }
    }

    int R = sumR / samples, G = sumG / samples, B = sumB / samples;
    int U = ((-38 * R - 74 * G + 112 * B + 128) >> 8) + 128;
    int V = ((112 * R - 94 * G - 18 * B + 128) >> 8) + 128;

    *outU = (uint8_t) CLAMP(U);
    *outV = (uint8_t) CLAMP(V);
}
