#ifndef YUV_H
#define YUV_H

#include <stdio.h>
#include <stdlib.h>

typedef struct {
    uint8_t *y;
    uint8_t *u;
    uint8_t *v;
    int width;
    int height;
    int yRowStride;
    int yPixelStride;
    int uvRowStride;
    int uvPixelStride;
} YUVDef;

#endif