#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/utils/h/log.h"
#include "../yuv/utils/h/yuv_utils.h"

void yuv420_flip_horizontally(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride
) {
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int sx = width - 1 - x;
            int sy = y;
            int dx = x;
            int dy = y;

            const int srcYIndex = yuv_index(sx, sy, yRowStride, yPixelStride);
            const int dstYIndex = yuv_index(dx, dy, yRowStride, yPixelStride);
            y_dst[dstYIndex] = y_src[srcYIndex];
            int srcUvIndex = yuv_index(sx / 2, sy / 2, uvRowStride, uvPixelStride);
            int dstUvIndex = yuv_index(dx / 2, dy / 2, uvRowStride, uvPixelStride);
            memcpy(u_dst + dstUvIndex, u_src + srcUvIndex, uvPixelStride);
            memcpy(v_dst + dstUvIndex, v_src + srcUvIndex, uvPixelStride);
        }
    }
}

void yuv420_flip_vertically(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride,
        uint32_t *rect
) {
    int left = rect == NULL ? 0 : rect[0];
    int top = rect == NULL ? 0 : rect[1];
    int right = rect == NULL ? width : rect[2];
    int bottom = rect == NULL ? height : rect[3];
    for (int y = 0; y < height; ++y) {
        memcpy(y_dst, y_src, yRowStride);
        memcpy(u_dst, u_src, uvRowStride);
        memcpy(v_dst, v_src, uvRowStride);

//        if (y >= top && y <= bottom) {
//            int sx = left;
//            int sy = height - 1 - y;
//            int dx = left;
//            int dy = y;
//
//            int yLen = (right - left) * yPixelStride;
//            int uvLen = (right - left) * uvPixelStride;
//
//            memcpy(y_dst + dy * yRowStride + dx * yPixelStride, y_src + sy * yRowStride + sx * yPixelStride, yLen);
//            memcpy(u_dst + dy * uvRowStride + dx * uvPixelStride, u_src + sy * uvRowStride + sx * uvPixelStride, uvLen);
//            memcpy(v_dst + dy * uvRowStride + dx * uvPixelStride, v_src + sy * uvRowStride + sx * uvPixelStride, uvLen);
//        }
    }
}


//        for (int x = 0; x < width; ++x) {
//            int sx = x;
//            int sy = height - 1 - y;
//            int dx = x;
//            int dy = y;
//
//            const int srcYIndex = (sy * yRowStride) + (sx * yPixelStride);
//            const int dstYIndex = (dy * yPixelStride * width) + (dx * yPixelStride);
//            y_dst[dstYIndex] = y_src[srcYIndex];
//            int srcUvIndex = ((sy / 2) * uvRowStride) + ((sx / 2) * uvPixelStride);
//            int dstUvIndex = ((dy / 2) * (width / 2) * uvPixelStride) + ((dx / 2) * uvPixelStride);
//            for (int z = 0; z < uvPixelStride; ++z) {
//                u_dst[dstUvIndex + z] = u_src[srcUvIndex + z];
//                v_dst[dstUvIndex + z] = v_src[srcUvIndex + z];
//            }
//        }