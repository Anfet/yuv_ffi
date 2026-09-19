#ifndef BOXBLUR_H
#define BOXBLUR_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_box_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif