#ifndef NV21_BOXBLUR_H
#define NV21_BOXBLUR_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void nv21_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif