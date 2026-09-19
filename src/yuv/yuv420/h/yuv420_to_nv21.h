#ifndef YUV420_TO_NV21_H
#define YUV420_TO_NV21_H

#include "../../yuv.h"

// Reads `src`, writes the interleaved-chroma result into `dst`.
FFI_PLUGIN_EXPORT void yuv420_i420_to_nv21(const YUVDef *src, YUVDef *dst);

#endif
