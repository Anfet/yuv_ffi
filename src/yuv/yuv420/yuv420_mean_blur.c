#ifndef INVERT_I420_H
#define INVERT_I420_H

#include <stdint.h>
#include "yuv_utils.h"

void yuv420_mean_blur(
        const uint8_t *y_src,
        uint8_t *y_dst,
        int width,
        int height,
        int kernel_size,
        int rowStride,
        int pixelStride,
        const uint8_t *rect // rect[0]=left, rect[1]=top, rect[2]=right, rect[3]=bottom
) {
    int k = kernel_size / 2;

    int left = rect ? rect[0] : 0;
    int top = rect ? rect[1] : 0;
    int right = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            int sum = 0;
            int count = 0;

            for (int dy = -k; dy <= k; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= height) continue;

                for (int dx = -k; dx <= k; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= width) continue;

                    int src_index = yuv_index(nx, ny, rowStride, pixelStride);
                    sum += y_src[src_index];
                    count++;
                }
            }

            int dst_index = yuv_index(x, y, rowStride, pixelStride);
            y_dst[dst_index] = sum / count;
        }
    }
}

#endif