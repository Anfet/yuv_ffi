#ifndef ROTATE_I420_H
#define ROTATE_I420_H

#include <stdint.h>

void yuv420_rotate(
        const YUV420Def *src,
        const YUV420Def *dst,
        int rotationDegrees
);

#endif
