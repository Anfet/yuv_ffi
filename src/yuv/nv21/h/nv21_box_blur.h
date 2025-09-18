#ifndef NV21_BOXBLUR_H
#define NV21_BOXBLUR_H

#include <stdint.h>
#include <stdlib.h>


void nv21_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif