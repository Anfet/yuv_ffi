#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "log.h"

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

            const int srcYIndex = (sy * yRowStride) + (sx * yPixelStride);
            const int dstYIndex = (dy * yPixelStride * width) + (dx * yPixelStride);
            y_dst[dstYIndex] = y_src[srcYIndex];
            int srcUvIndex = ((sy / 2) * uvRowStride) + ((sx / 2) * uvPixelStride);
            int dstUvIndex = ((dy / 2) * (width / 2) * uvPixelStride) + ((dx / 2) * uvPixelStride);
            for (int z = 0; z < uvPixelStride; ++z) {
                u_dst[dstUvIndex + z] = u_src[srcUvIndex + z];
                v_dst[dstUvIndex + z] = v_src[srcUvIndex + z];
            }
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
        int uvPixelStride
) {
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int sx = x;
            int sy = height - 1 - y;
            int dx = x;
            int dy = y;

            const int srcYIndex = (sy * yRowStride) + (sx * yPixelStride);
            const int dstYIndex = (dy * yPixelStride * width) + (dx * yPixelStride);
            y_dst[dstYIndex] = y_src[srcYIndex];
            int srcUvIndex = ((sy / 2) * uvRowStride) + ((sx / 2) * uvPixelStride);
            int dstUvIndex = ((dy / 2) * (width / 2) * uvPixelStride) + ((dx / 2) * uvPixelStride);
            for (int z = 0; z < uvPixelStride; ++z) {
                u_dst[dstUvIndex + z] = u_src[srcUvIndex + z];
                v_dst[dstUvIndex + z] = v_src[srcUvIndex + z];
            }
        }
    }
}
