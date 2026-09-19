#ifndef YUV420_FROM_RGBA_H
#define YUV420_FROM_RGBA_H

#include "../../yuv.h"

// Reads `rgba`, writes the converted result into `dst`.
//
// The destination parameter used to be named `src`, which inverted the roles
// this signature actually implements: the YUVDef here is written, not read.
FFI_PLUGIN_EXPORT void yuv420_from_rgba8888(const uint8_t *rgba, YUVDef *dst);

#endif
