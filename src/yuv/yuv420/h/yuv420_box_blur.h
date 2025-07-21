#ifndef BOXBLUR_H
#define BOXBLUR_H

#include <stdint.h>
#include <stdlib.h>



void yuv420_box_blur(
        const YUV420Def *src,
        int radius,
        const uint32_t *rect
);

#endif