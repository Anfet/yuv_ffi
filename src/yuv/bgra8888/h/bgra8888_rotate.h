#ifndef ROTATE_BGRA8888_H
#define ROTATE_BGRA8888_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
);

#endif
