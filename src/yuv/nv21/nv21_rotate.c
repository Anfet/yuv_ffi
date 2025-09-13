#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/utils/h/yuv_utils.h"
#include "../yuv/nv21.h"

void nv21_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
) {
    const int rotation90 = rotationDegrees / 90.0;
    const int dstWidth = dst->width;
    const int dstHeight = dst->height;
    const int uvDstWidth = dst->width / 2;

    const int height = src->height;
    const int width = src->width;
    const int yRowStride = src->yRowStride;
    const int yPixelStride = src->yPixelStride;
    const int uvRowStride = src->uvRowStride;
    const int uvPixelStride = src->uvPixelStride;

    if (uvPixelStride != 2) return;

    uint8_t *y_src = src->y;
    uint8_t *u_src = src->u;

    uint8_t *y_dst = dst->y;
    uint8_t *u_dst = dst->u;

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
                int u = u_src[srcUvIndex];
                int v = u_src[srcUvIndex + 1];
                u_dst[dstUvIndex] = u;
                u_dst[dstUvIndex] = v;
            }
        }
    }
}
