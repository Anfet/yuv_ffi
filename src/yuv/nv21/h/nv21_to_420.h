#ifndef NV21_TO_420_H
#define NV21_TO_420_H

#include "../../yuv.h"

FFI_PLUGIN_EXPORT void nv21_to_i420(const YUVDef* src, const YUVDef* dst);

#endif