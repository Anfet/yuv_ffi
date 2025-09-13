#ifndef FLIP_BGRA8888_H
#define FLIP_BGRA8888_H

#include <stdint.h>

void bgra8888_flip_horizontally(
        const YUVDef *src
);

void bgra8888_flip_vertically(
        const YUVDef *src
);

#endif
