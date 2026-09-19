#ifndef BGRA8888_TO_NV21_H
#define BGRA8888_TO_NV21_H

#include "../../yuv.h"


// Reads `src`, writes the interleaved-chroma result into `dst`.
FFI_PLUGIN_EXPORT void bgra8888_to_nv21(const YUVDef *src, YUVDef *dst);

#endif
