#ifndef GAUSS_I420_H
#define GAUSS_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_gaussblur(
        YUVDef *image,
        int radius,
        int sigma
);

#endif
