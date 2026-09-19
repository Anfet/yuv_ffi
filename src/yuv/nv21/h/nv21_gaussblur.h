#ifndef GAUSS_NV21_H
#define GAUSS_NV21_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_gaussian_blur(
        YUVDef *image,
        int radius,
        float sigma
);

#endif
