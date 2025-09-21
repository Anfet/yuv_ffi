#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_flip_horizontally(
        const YUVDef *src
) {
    uint8_t yTemp[src->yPixelStride];
    uint8_t uTemp[src->uvPixelStride];
    uint8_t vTemp[src->uvPixelStride];
    const int flipWidth = src->width / 2;
    for (int y = 0; y < src->height; ++y) {
        for (int x = 0; x < flipWidth; ++x) {
            int sx = src->width - 1 - x;
            int sy = y;
            int dx = x;
            int dy = y;

            const int srcYIndex = yuv_index(sx, sy, src->yRowStride, src->yPixelStride);
            const int dstYIndex = yuv_index(dx, dy, src->yRowStride, src->yPixelStride);

            if (src->yPixelStride == 1) {
                uint8_t temp = src->y[dstYIndex];
                src->y[dstYIndex] = src->y[srcYIndex];
                src->y[srcYIndex] = temp;
            } else {
                memcpy(yTemp, src->y + dstYIndex, src->yPixelStride);
                memcpy(src->y + dstYIndex, src->y + srcYIndex, src->yPixelStride);
                memcpy(src->y + srcYIndex, yTemp, src->yPixelStride);
            }

            if (x % 2 == 0 && y % 2 == 0) {
                int srcUvIndex = yuv_index(sx / 2, sy / 2, src->uvRowStride, src->uvPixelStride);
                int dstUvIndex = yuv_index(dx / 2, dy / 2, src->uvRowStride, src->uvPixelStride);

                memcpy(uTemp, src->u + dstUvIndex, src->uvPixelStride);
                memcpy(src->u + dstUvIndex, src->u + srcUvIndex, src->uvPixelStride);
                memcpy(src->u + srcUvIndex, uTemp, src->uvPixelStride);
            }
        }
    }
}

FFI_PLUGIN_EXPORT void nv21_flip_vertically(
        const YUVDef *src
) {

    const int flipHeight = src->height / 2;
    for (int y = 0; y < flipHeight; ++y) {
        uint8_t *srcYIndex = src->y + yuv_index(0, y, src->yRowStride, src->yPixelStride);
        uint8_t *dstYIndex = src->y + yuv_index(0, src->height - y - 1, src->yRowStride, src->yPixelStride);
        swap_bytes(srcYIndex, dstYIndex, src->yRowStride);

        if (y % 2 == 0) {
            int srcUvIndex = yuv_index(0, y / 2, src->uvRowStride, src->uvPixelStride);
            int dstUvIndex = yuv_index(0, (src->height - y - 1) / 2, src->uvRowStride, src->uvPixelStride);
            swap_bytes(src->u + dstUvIndex, src->u + srcUvIndex, src->uvRowStride);
        }
    }
}
