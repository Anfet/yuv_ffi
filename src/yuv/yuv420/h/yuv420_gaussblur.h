#ifndef GAUSS_I420_H
#define GAUSS_I420_H

#include <stdint.h>

void yuv420_gaussblur(
        const YUV420Def *src,
        int radius,
        int sigma
);

#endif
