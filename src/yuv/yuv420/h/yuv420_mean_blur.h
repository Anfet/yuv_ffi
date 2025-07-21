#ifndef MEAN_I420_H
#define MEAN_I420_H

#include <stdint.h>

void yuv420_mean_blur(
        const YUV420Def *src,
        int radius,
        const uint32_t *rect
);

#endif