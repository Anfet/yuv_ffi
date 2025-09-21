#ifndef FLIP_NV21_H
#define FLIP_NV21_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void nv21_flip_horizontally(
        const YUVDef *src
);

FFI_PLUGIN_EXPORT void nv21_flip_vertically(
        const YUVDef *src
);

#endif
