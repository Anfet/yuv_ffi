#ifndef NEGATE_NV21_H
#define NEGATE_NV21_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void nv21_negate(
        YUVDef *image
);

#endif
