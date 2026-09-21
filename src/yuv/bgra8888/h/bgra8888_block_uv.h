#ifndef BGRA8888_BLOCK_UV_H
#define BGRA8888_BLOCK_UV_H

#include "../../yuv.h"

// Averages the actual BGRA samples covered by the 2x2 luma block at (bx, by)
// -- 1 sample on a trailing odd row/column, 4 otherwise -- and BT.601
// limited-range encodes the result into *outU/*outV. Shared by
// bgra8888_to_i420 and bgra8888_to_nv21, whose block loops were otherwise
// byte-for-byte duplicates of each other.
void bgra8888_block_uv(const YUVDef *src, int bx, int by, uint8_t *outU, uint8_t *outV);

#endif
