#include "..//yuv.h"


FFI_PLUGIN_EXPORT void yuv420_to_bgra8888(
        const YUVDef *src,
        uint8_t *outBgra
) {
    int uvIndex, yIndex = 0;

    for (int y = 0; y < src->height; y++) {
        for (int x = 0; x < src->width; x++) {
            yIndex = yuv_index(x, y, src->yRowStride, src->yPixelStride);
            int Y = src->y[yIndex];

            uvIndex = yuv_index(x >> 1, y >> 1, src->uvRowStride, src->uvPixelStride);
            int Uc = src->u[uvIndex] - 128;
            int Vc = src->v[uvIndex] - 128;

            int C = Y - 16;
            int R = (298 * C + 409 * Vc + 128) >> 8;
            int G = (298 * C - 100 * Uc - 208 * Vc + 128) >> 8;
            int B = (298 * C + 516 * Uc + 128) >> 8;

            int outIndex = (y * src->width + x) * 4;
            outBgra[outIndex + 0] = CLAMP(B);
            outBgra[outIndex + 1] = CLAMP(G);
            outBgra[outIndex + 2] = CLAMP(R);
            outBgra[outIndex + 3] = 255;
        }
    }
}
