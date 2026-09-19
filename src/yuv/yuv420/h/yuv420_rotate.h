#ifndef ROTATE_I420_H
#define ROTATE_I420_H

#include "../../yuv.h"

// Reads `src`, writes the rotated result into `dst`.
FFI_PLUGIN_EXPORT void yuv420_rotate(
        const YUVDef *src,
        YUVDef *dst,
        int rotationDegrees
);

#endif
