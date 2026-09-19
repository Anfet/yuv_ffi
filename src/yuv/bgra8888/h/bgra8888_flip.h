#ifndef FLIP_BGRA8888_H
#define FLIP_BGRA8888_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_flip_horizontally(
        YUVDef *image
);

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_flip_vertically(
        YUVDef *image
);

#endif
