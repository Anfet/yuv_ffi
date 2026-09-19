#ifndef BLACKWHITE_NV21_H
#define BLACKWHITE_NV21_H

#include "../../yuv.h"


// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_blackwhite(
        YUVDef *image
);

#endif
