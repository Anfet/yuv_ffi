#ifndef ROTATE_I420_H
#define ROTATE_I420_H

#include <stdint.h>

void yuv420_rotate(
        const YUVDef *src,
        const YUVDef *dst,
        int rotationDegrees
);

#endif
