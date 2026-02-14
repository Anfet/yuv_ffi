#ifndef MEAN_BGRA8888_H
#define MEAN_BGRA8888_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_mean_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif