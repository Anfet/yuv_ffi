#ifndef NV21_CROP_H
#define NV21_CROP_H

#include "../../yuv.h"


// Reads `src`, writes the cropped result into `dst`.
FFI_PLUGIN_EXPORT void nv21_crop_rect(
        const YUVDef *src,
        YUVDef *dst,
        int left, int top,
        int crop_width, int crop_height);

#endif