#ifndef YUV420_FROM_RGBA_H
#define YUV420_FROM_RGBA_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_from_rgba8888(const uint8_t *rgba, const YUVDef *src);

#endif
