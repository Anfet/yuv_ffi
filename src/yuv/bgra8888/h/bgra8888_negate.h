#ifndef NEGATE_BGRA8888_H
#define NEGATE_BGRA8888_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_negate(
        YUVDef *image
);

#endif
