#ifndef GAUSS_BGRA8888_H
#define GAUSS_BGRA8888_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_gaussian_blur(
        YUVDef *image,
        int radius,
        float sigma
);

#endif
