#ifndef BGRA8888_BOXBLUR_H
#define BGRA8888_BOXBLUR_H

#include <stdint.h>
#include <stdlib.h>


void bgra8888_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif