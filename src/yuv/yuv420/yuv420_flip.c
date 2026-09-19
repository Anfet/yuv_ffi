#include "../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_flip_horizontally(
        YUVDef *image
) {
    uint8_t* yTemp = (uint8_t*)malloc(image->yPixelStride);
    if (!yTemp) return;
    uint8_t* uTemp = (uint8_t*)malloc(image->uvPixelStride);
    if (!uTemp) return;
    uint8_t* vTemp = (uint8_t*)malloc(image->uvPixelStride);
    if (!vTemp) return;

    const int flipWidth = image->width / 2;
    for (int y = 0; y < image->height; ++y) {
        for (int x = 0; x < flipWidth; ++x) {
            int sx = image->width - 1 - x;
            int sy = y;
            int dx = x;
            int dy = y;

            const int srcYIndex = yuv_index(sx, sy, image->yRowStride, image->yPixelStride);
            const int dstYIndex = yuv_index(dx, dy, image->yRowStride, image->yPixelStride);

            if (image->yPixelStride == 1) {
                uint8_t temp = image->y[dstYIndex];
                image->y[dstYIndex] = image->y[srcYIndex];
                image->y[srcYIndex] = temp;
            } else {
                memcpy(yTemp, image->y + dstYIndex, image->yPixelStride);
                memcpy(image->y + dstYIndex, image->y + srcYIndex, image->yPixelStride);
                memcpy(image->y + srcYIndex, yTemp, image->yPixelStride);
            }

            if (x % 2 == 0 && y % 2 == 0) {
                int srcUvIndex = yuv_index(sx / 2, sy / 2, image->uvRowStride, image->uvPixelStride);
                int dstUvIndex = yuv_index(dx / 2, dy / 2, image->uvRowStride, image->uvPixelStride);

                memcpy(uTemp, image->u + dstUvIndex, image->uvPixelStride);
                memcpy(image->u + dstUvIndex, image->u + srcUvIndex, image->uvPixelStride);
                memcpy(image->u + srcUvIndex, uTemp, image->uvPixelStride);

                memcpy(vTemp, image->v + dstUvIndex, image->uvPixelStride);
                memcpy(image->v + dstUvIndex, image->v + srcUvIndex, image->uvPixelStride);
                memcpy(image->v + srcUvIndex, vTemp, image->uvPixelStride);
            }
        }
    }

    free(yTemp);
    free(uTemp);
    free(vTemp);
}

FFI_PLUGIN_EXPORT void yuv420_flip_vertically(
        YUVDef *image
) {
//    uint8_t yTemp[image->yRowStride];
//    uint8_t uvTemp[image->uvRowStride];

    const int flipHeight = image->height / 2;
    for (int y = 0; y < flipHeight; ++y) {
        uint8_t *srcYIndex = image->y + yuv_index(0, y, image->yRowStride, image->yPixelStride);
        uint8_t *dstYIndex = image->y + yuv_index(0, image->height - y - 1, image->yRowStride, image->yPixelStride);
        swap_bytes(srcYIndex, dstYIndex, image->yRowStride);
//        memcpy(yTemp, dstYIndex, image->yRowStride);
//        memcpy(dstYIndex, srcYIndex, image->yRowStride);
//        memcpy(srcYIndex, yTemp, image->yRowStride);

        if (y % 2 == 0) {
            int srcUvIndex = yuv_index(0, y / 2, image->uvRowStride, image->uvPixelStride);
            int dstUvIndex = yuv_index(0, (image->height - y - 1) / 2, image->uvRowStride, image->uvPixelStride);
            swap_bytes(image->u + dstUvIndex, image->u + srcUvIndex, image->uvRowStride);
//            memcpy(uvTemp, image->u + dstUvIndex, image->uvRowStride);
//            memcpy(image->u + dstUvIndex, image->u + srcUvIndex, image->uvRowStride);
//            memcpy(image->u + srcUvIndex, uvTemp, image->uvRowStride);

            swap_bytes(image->v + dstUvIndex, image->v + srcUvIndex, image->uvRowStride);
//            memcpy(uvTemp, image->v + dstUvIndex, image->uvRowStride);
//            memcpy(image->v + dstUvIndex, image->v + srcUvIndex, image->uvRowStride);
//            memcpy(image->v + srcUvIndex, uvTemp, image->uvRowStride);
        }
    }
}
