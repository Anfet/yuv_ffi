#ifndef FLIP_NV21_H
#define FLIP_NV21_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_flip_horizontally(
        YUVDef *image
);

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_flip_vertically(
        YUVDef *image
);

#endif
