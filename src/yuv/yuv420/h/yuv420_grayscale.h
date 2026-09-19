#ifndef GRAYSCALE_I420_H
#define GRAYSCALE_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_grayscale(
        YUVDef *image
);

#endif
