#ifndef CROP_I420_H
#define CROP_I420_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        const int left,  int top, int crop_width, int crop_height
);

#endif
