#ifndef BGRA8888_TO_I420_H
#define BGRA8888_TO_I420_H

#include "../../yuv.h"

// Reads `src`, writes the I420 result into `dst`.
FFI_PLUGIN_EXPORT void bgra8888_to_i420(const YUVDef *src, YUVDef *dst);

#endif
