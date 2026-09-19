#ifndef MEAN_I420_H
#define MEAN_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
);

#endif