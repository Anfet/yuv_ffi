#ifndef MEAN_NV21_H
#define MEAN_NV21_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif