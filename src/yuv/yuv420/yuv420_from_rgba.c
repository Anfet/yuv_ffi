#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "../yuv/utils/h/yuv_utils.h"
#include "../yuv/yuv420.h"

void yuv420_from_rgba8888(const uint8_t *rgba, const YUV420Def *src) {
    uint8_t *yPlane = src->y;
    uint8_t *uPlane = src->u;
    uint8_t *vPlane = src->v;
    const int width = src->width;
    const int height = src->height;
    const int yRowStride = src->yRowStride;
    const int yPixelStride = src->yPixelStride;
    const int uvRowStride = src->uvRowStride;
    const int uvPixelStride = src->uvPixelStride;

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int yIndex = yuv_index(x, y, yRowStride, yPixelStride);
            int rgbaIndex = (y * width + x) * 4;

            uint8_t r = rgba[rgbaIndex + 0];
            uint8_t g = rgba[rgbaIndex + 1];
            uint8_t b = rgba[rgbaIndex + 2];

            int yValue = CLAMP(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);

            yPlane[yIndex] = yValue;

            if ((y % 2 == 0) && (x % 2 == 0)) {
                int uValue = CLAMP(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
                int vValue = CLAMP(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
                int uvIndex = yuv_index(x / 2, y / 2, uvRowStride, uvPixelStride);

                uPlane[uvIndex] = uValue;
                vPlane[uvIndex] = vValue;
            }
        }
    }
}
