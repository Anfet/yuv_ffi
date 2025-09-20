#ifndef MEAN_I420_H
#define MEAN_I420_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void yuv420_mean_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif