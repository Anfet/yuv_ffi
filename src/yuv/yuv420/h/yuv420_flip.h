#ifndef FLIP_I420_H
#define FLIP_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_flip_horizontally(
        YUVDef *image
);

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_flip_vertically(
        YUVDef *image
);

#endif
