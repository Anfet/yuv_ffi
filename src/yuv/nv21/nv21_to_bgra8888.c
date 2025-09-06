#include <stdint.h>
#include "./yuv/utils/h/yuv_utils.h"
#include "./yuv/yuv.h" // здесь объявлен YUVDef

// Ожидаем, что src->y указывает на Y, а src->v/src->u указывают на один и тот же VU-буфер,
// при этом src->v = vu + 0, src->u = vu + 1, uvPixelStride == 2.
void nv21_to_bgra8888(const YUVDef *src, uint8_t *outBgra) {
    int uvIndex, yIndex;
    int yp, up, vp;
    int r, g, b;

    for (int y = 0; y < src->height; ++y) {
        for (int x = 0; x < src->width; ++x) {
            yIndex = yuv_index(x, y, src->yRowStride, src->yPixelStride);
            yp = src->y[yIndex];

            // NV21: interleaved VU для 2x2 блока
            uvIndex = yuv_index(x >> 1, y >> 1, src->uvRowStride, src->uvPixelStride);
            up = (int)src->v[uvIndex] - 128; // первый байт — V
            vp = (int)src->u[uvIndex + 1] - 128; // второй байт — U

            r = (int)(yp + 1.370705f * vp);
            g = (int)(yp - 0.337633f * up - 0.698001f * vp);
            b = (int)(yp + 1.732446f * up);

            const int outIndex = (y * src->width + x) * 4;
            outBgra[outIndex + 0] = CLAMP(b);
            outBgra[outIndex + 1] = CLAMP(g);
            outBgra[outIndex + 2] = CLAMP(r);
            outBgra[outIndex + 3] = 255;
        }
    }
}
