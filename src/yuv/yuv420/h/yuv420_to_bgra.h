#ifndef YUV420_TO_BGRA_H
#define YUV420_TO_BGRA_H

#include "..//..//yuv.h"

FFI_PLUGIN_EXPORT void yuv420_to_bgra8888(
        const YUVDef *src,
        uint8_t *outBgra
);

#endif
