#ifndef MEAN_BGRA8888_H
#define MEAN_BGRA8888_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif