#ifndef NEGATE_I420_H
#define NEGATE_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_negate(
        YUVDef *image
);

#endif
