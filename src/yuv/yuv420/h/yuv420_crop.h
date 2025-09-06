#ifndef CROP_I420_H
#define CROP_I420_H

#include <stdint.h>

void yuv420_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        const int left,  int top, int crop_width, int crop_height
);

#endif
