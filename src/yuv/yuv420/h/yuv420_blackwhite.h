#ifndef BLACKWHITE_I420_H
#define BLACKWHITE_I420_H

#include "../../yuv.h"

// In-place: mutates the planes of `image`.
FFI_PLUGIN_EXPORT void yuv420_blackwhite(
        YUVDef *image
);

#endif
