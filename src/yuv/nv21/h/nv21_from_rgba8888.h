#ifndef NV21_FROM_RGBA8888_H
#define NV21_FROM_RGBA8888_H

#include <stdint.h>

void nv21_from_rgba8888(const uint8_t *rgba, const YUVDef *dst);

#endif