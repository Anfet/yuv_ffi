#ifndef YUV_H
#define YUV_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "utils/h/yuv_utils.h"
#include "utils/h/log.h"
#include "utils/h/gauss.h"

#define FFI_PLUGIN_EXPORT

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