#ifndef FLIP_I420_H
#define FLIP_I420_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void yuv420_flip_horizontally(
        const YUVDef *src
);

FFI_PLUGIN_EXPORT void yuv420_flip_vertically(
        const YUVDef *src
);

#endif
