#ifndef NV21_FROM_RGBA8888_H
#define NV21_FROM_RGBA8888_H

#include "../../yuv.h"

// Reads `rgba`, writes the converted result into `dst`.
FFI_PLUGIN_EXPORT void nv21_from_rgba8888(const uint8_t *rgba, YUVDef *dst);

#endif