#ifndef MEAN_NV21_H
#define MEAN_NV21_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void nv21_mean_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif