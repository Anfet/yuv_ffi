#ifndef GAUSS_BGRA8888_H
#define GAUSS_BGRA8888_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_gaussian_blur(
        const YUVDef *src,
        int radius,
        float sigma
);

#endif
