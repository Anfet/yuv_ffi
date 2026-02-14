#ifndef FLIP_BGRA8888_H
#define FLIP_BGRA8888_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_flip_horizontally(
        const YUVDef *src
);

FFI_PLUGIN_EXPORT void bgra8888_flip_vertically(
        const YUVDef *src
);

#endif
