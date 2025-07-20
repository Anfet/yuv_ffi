#ifndef BOXBLUR_H
#define BOXBLUR_H

#include <stdint.h>
#include <stdlib.h>



void yuv420_box_blur(
        const uint8_t *src,
        uint8_t *dst,
        int width,
        int height,
        int rowStride,
        int pixelStride,
        int radius,
        const uint32_t *rect  // NULL или [left, top, right, bottom]
);

#endif