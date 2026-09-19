#ifndef YUV420_TO_BGRA_H
#define YUV420_TO_BGRA_H

#include "../../yuv.h"

// Read-only in `src`: the planes are never written through, so `const` here is
// accurate rather than decorative. Output goes to `outBgra`.
FFI_PLUGIN_EXPORT void yuv420_to_bgra8888(
        const YUVDef *src,
        uint8_t *outBgra
);

#endif
