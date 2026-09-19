#ifndef ROTATE_NV21_H
#define ROTATE_NV21_H

#include "../../yuv.h"

// Reads `src`, writes the rotated result into `dst`.
FFI_PLUGIN_EXPORT void nv21_rotate(
        const YUVDef *src,
        YUVDef *dst,
        int rotationDegrees
);

#endif
