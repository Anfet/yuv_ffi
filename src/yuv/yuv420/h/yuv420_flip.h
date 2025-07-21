#ifndef FLIP_I420_H
#define FLIP_I420_H

#include <stdint.h>

void yuv420_flip_horizontally(
        const YUV420Def *src
);

void yuv420_flip_vertically(
        const YUV420Def *src
);

#endif
