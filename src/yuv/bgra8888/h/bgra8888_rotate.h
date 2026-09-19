#ifndef ROTATE_BGRA8888_H
#define ROTATE_BGRA8888_H

#include "../../yuv.h"

// Reads `src`, writes the rotated result into `dst`.
FFI_PLUGIN_EXPORT void bgra8888_rotate(
        const YUVDef *src,
        YUVDef *dst,
        int rotationDegrees
);

#endif
