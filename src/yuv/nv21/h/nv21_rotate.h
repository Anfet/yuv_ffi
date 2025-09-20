#ifndef ROTATE_NV21_H
#define ROTATE_NV21_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void nv21_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
);

#endif
