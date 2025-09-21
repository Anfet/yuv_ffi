#ifndef NV21_CROP_H
#define NV21_CROP_H

#include "../../yuv.h"


FFI_PLUGIN_EXPORT void nv21_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        int left, int top,
        int crop_width, int crop_height);

#endif