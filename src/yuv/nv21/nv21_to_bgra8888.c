#include "../yuv.h"

// Expects src->y to point at Y and src->u at the interleaved chroma buffer,
// with uvPixelStride == 2. src->v is unused.
//
// The legacy public format name is `nv21`, but the established byte order of
// this project is (U, V): U at byte 0, V at byte 1 of each chroma pair. The
// code below reads it that way; the name is kept for compatibility.
FFI_PLUGIN_EXPORT void nv21_to_bgra8888(const YUVDef *src, uint8_t *outBgra) {
    int uvIndex, yIndex;

    for (int y = 0; y < src->height; ++y) {
        for (int x = 0; x < src->width; ++x) {
            yIndex = yuv_index(x, y, src->yRowStride, src->yPixelStride);
            int Y = src->y[yIndex];

            // Legacy `nv21`: interleaved (U, V) for a 2x2 block
            uvIndex = yuv_index(x >> 1, y >> 1, src->uvRowStride, src->uvPixelStride);
            int Uc = src->u[uvIndex + 0] - 128;
            int Vc = src->u[uvIndex + 1] - 128;

            int C = Y - 16;
            int R = (298 * C + 409 * Vc + 128) >> 8;
            int G = (298 * C - 100 * Uc - 208 * Vc + 128) >> 8;
            int B = (298 * C + 516 * Uc + 128) >> 8;

            const int outIndex = (y * src->width + x) * 4;
            outBgra[outIndex + 0] = CLAMP(B);
            outBgra[outIndex + 1] = CLAMP(G);
            outBgra[outIndex + 2] = CLAMP(R);
            outBgra[outIndex + 3] = 255;
        }
    }
}
