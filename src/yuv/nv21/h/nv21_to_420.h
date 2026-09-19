#ifndef NV21_TO_420_H
#define NV21_TO_420_H

#include "../../yuv.h"

// Reads `src`, writes the I420 result into `dst`.
FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef *src, YUVDef *dst);

#endif