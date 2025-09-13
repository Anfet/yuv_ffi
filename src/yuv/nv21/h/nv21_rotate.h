#ifndef ROTATE_NV21_H
#define ROTATE_NV21_H

#include <stdint.h>

void nv21_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
);

#endif
