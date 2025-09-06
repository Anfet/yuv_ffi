#ifndef BOXBLUR_H
#define BOXBLUR_H

#include <stdint.h>
#include <stdlib.h>



void yuv420_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif