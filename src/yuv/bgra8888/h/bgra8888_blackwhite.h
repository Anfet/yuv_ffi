#ifndef BLACKWHITE_BGRA8888_H
#define BLACKWHITE_BGRA8888_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void bgra8888_blackwhite(
        YUVDef *image
);

#endif
