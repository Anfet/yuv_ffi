#ifndef BGRA8888_BOXBLUR_H
#define BGRA8888_BOXBLUR_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_box_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif