#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
) {
    const int rotation90 = rotationDegrees / 90.0;
    const int dstWidth = dst->width;
    const int dstHeight = dst->height;

    const int height = src->height;
    const int width = src->width;
    const int yPixelStride = src->yPixelStride;


    uint8_t *y_src = src->y;
    uint8_t *y_dst = dst->y;

    for (int y = 0; y < dstHeight; ++y) {
        for (int x = 0; x < dstWidth; ++x) {
            const int dx = x;
            const int dy = y;

            int sx = x;
            int sy = y;

            switch (rotation90) {
                case 1:
                    sx = y;
                    sy = height - 1 - x;
                    break;
                case 2:
                    sx = width - 1 - x;
                    sy = height - 1 - y;
                    break;
                case 3:
                    sx = width - 1 - y;
                    sy = x;
                    break;
            }
            const int srcYIndex =  sy * width * yPixelStride + sx * yPixelStride;
            const int dstYIndex =  dy * dstWidth * yPixelStride + dx * yPixelStride;
            memcpy(y_dst + dstYIndex, y_src + srcYIndex, yPixelStride);
        }
    }
}
