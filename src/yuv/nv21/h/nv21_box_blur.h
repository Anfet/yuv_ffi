#ifndef NV21_BOXBLUR_H
#define NV21_BOXBLUR_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_box_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif