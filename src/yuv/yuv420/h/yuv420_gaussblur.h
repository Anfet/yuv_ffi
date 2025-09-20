#ifndef GAUSS_I420_H
#define GAUSS_I420_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void yuv420_gaussblur(
        const YUVDef *src,
        int radius,
        int sigma
);

#endif
