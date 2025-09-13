#ifndef FLIP_NV21_H
#define FLIP_NV21_H

#include <stdint.h>

void nv21_flip_horizontally(
        const YUVDef *src
);

void nv21_flip_vertically(
        const YUVDef *src
);

#endif
