#ifndef NV21_TO_BGRA8888_H
#define NV21_TO_BGRA8888_H

#include <stdint.h>

void nv21_to_bgra8888(const YUVDef *src, uint8_t *outBgra);

#endif