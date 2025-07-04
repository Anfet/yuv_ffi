#ifndef ROTATE_I420_H
#define ROTATE_I420_H

#include <stdint.h>

void yuv420_rotate_interleaved(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int rotationDegrees,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride
);

#endif
