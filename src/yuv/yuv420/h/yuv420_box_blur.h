#ifndef BOXBLUR_H
#define BOXBLUR_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_box_blur(
        const YUVDef *src,
        int radius,
        const uint32_t *rect
);

#endif