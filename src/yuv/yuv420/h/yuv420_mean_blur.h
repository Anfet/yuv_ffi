#ifndef MEAN_I420_H
#define MEAN_I420_H

#include <stdint.h>

void yuv420_mean_blur(
        const uint8_t *y_src,
        uint8_t *y_dst,
        int width,
        int height,
        int kernel_size,
        int rowStride,
        int pixelStride,
        const uint8_t *rect // rect[0]=left, rect[1]=top, rect[2]=right, rect[3]=bottom
);

#endif