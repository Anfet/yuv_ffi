#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/utils/h/yuv_utils.h"

void yuv420_rotate_interleaved(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int rotationDegrees,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride
) {


    const int rotation90 = (rotationDegrees % 360) / 90.0;
    const int dstWidth = rotation90 % 2 == 0 ? width : height;
    const int dstHeight = rotation90 % 2 == 0 ? height : width;
    const int uvDstWidth = (rotation90 % 2 == 1 ? height : width) / 2;

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
            const int srcYIndex = yuv_index(sx, sy, yRowStride, yPixelStride);
            const int dstYIndex = yuv_index(dx, dy, dstWidth, yPixelStride);
            y_dst[dstYIndex] = y_src[srcYIndex];

            if (dy % 2 == 0 & dx % 2 == 0) {
                const int srcUvIndex = yuv_index(sx / 2, sy / 2, uvRowStride, uvPixelStride);
                const int dstUvIndex = yuv_index(dx / 2, dy / 2, uvDstWidth * uvPixelStride, uvPixelStride);
                memcpy(u_dst + dstUvIndex, u_src + srcUvIndex, uvPixelStride);
                memcpy(v_dst + dstUvIndex, v_src + srcUvIndex, uvPixelStride);
            }
        }
    }
}
