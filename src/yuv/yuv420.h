#ifndef YUV420_H
#define YUV420_H

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
} YUV420Def;

#include <stdio.h>
#include "yuv420/h/yuv420_blackwhite.h"
#include "yuv420/h/yuv420_crop.h"
#include "yuv420/h/yuv420_flip.h"
#include "yuv420/h/yuv420_gaussblur.h"
#include "yuv420/h/yuv420_grayscale.h"
#include "yuv420/h/yuv420_mean_blur.h"
#include "yuv420/h/yuv420_rotate.h"
#include "yuv420/h/yuv420_to_bgra.h"
#include "yuv420/h/yuv420_negate.h"
#include "yuv420/h/yuv420_box_blur.h"
#include "yuv420/h/yuv420_from_rgba.h"

#endif