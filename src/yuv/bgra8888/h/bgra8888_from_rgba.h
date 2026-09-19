#ifndef BGRA8888_FROM_RGBA_H
#define BGRA8888_FROM_RGBA_H

#include "../../yuv.h"

// Reads `rgba`, writes the converted result into `dst`.
FFI_PLUGIN_EXPORT void bgra8888_from_rgba8888(const uint8_t *rgba, YUVDef *dst);

#endif
