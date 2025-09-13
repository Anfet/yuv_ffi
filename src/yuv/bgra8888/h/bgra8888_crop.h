#ifndef CROP_BGRA8888_H
#define CROP_BGRA8888_H

#include <stdint.h>

void bgra8888_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        const int left,  int top, int crop_width, int crop_height
);

#endif
