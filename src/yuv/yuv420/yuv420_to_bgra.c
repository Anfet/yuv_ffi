#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "../yuv/utils/h/yuv_utils.h"
#include "../yuv/yuv420.h"


void yuv420_to_bgra8888(
        const YUV420Def *src,
        uint8_t *outBgra
) {
    int uvIndex, yIndex = 0;
    int yp, up, vp = 0;
    int r, g, b = 0;

    for (int y = 0; y < src->height; y++) {
        for (int x = 0; x < src->width; x++) {
            yIndex = yuv_index(x, y, src->yRowStride, src->yPixelStride);
            yp = src->y[yIndex];

            if ((x % 2 == 0) && (y % 2 == 0)) {
                uvIndex = yuv_index(x / 2, y / 2, src->uvRowStride, src->uvPixelStride);
                up = src->u[uvIndex] - 128;
                vp = src->v[uvIndex] - 128;
            }

            r = (int) (yp + 1.370705 * vp);
            g = (int) (yp - 0.337633 * up - 0.698001 * vp);
            b = (int) (yp + 1.732446 * up);

            int outIndex = (y * src->width + x) * 4;
            outBgra[outIndex + 0] = CLAMP(b);
            outBgra[outIndex + 1] = CLAMP(g);
            outBgra[outIndex + 2] = CLAMP(r);
            outBgra[outIndex + 3] = 255;
        }
    }
}
