#ifndef NV21_TO_BGRA8888_H
#define NV21_TO_BGRA8888_H

#include "../../yuv.h"

// Read-only in `src`: the planes are never written through, so `const` here is
// accurate rather than decorative. Output goes to `outBgra`.
FFI_PLUGIN_EXPORT void nv21_to_bgra8888(const YUVDef *src, uint8_t *outBgra);

#endif