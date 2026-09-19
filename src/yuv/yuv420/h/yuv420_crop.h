#ifndef CROP_I420_H
#define CROP_I420_H

#include "../../yuv.h"

// Reads `src`, writes the cropped result into `dst`.
FFI_PLUGIN_EXPORT void yuv420_crop_rect(
        const YUVDef *src,
        YUVDef *dst,
        const int left, const int top,
        const int crop_width, const int crop_height
);

#endif
