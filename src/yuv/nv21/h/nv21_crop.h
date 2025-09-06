#ifndef NV21_TO_420_H
#define NV21_TO_420_H

#include <stdint.h>


void nv21_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        int left, int top,
        int crop_width, int crop_height);

#endif