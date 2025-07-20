#ifndef FLIP_I420_H
#define FLIP_I420_H

#include <stdint.h>

void yuv420_flip_horizontally(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride
);

void yuv420_flip_vertically(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst,
        int width,
        int height,
        int yRowStride,
        int yPixelStride,
        int uvRowStride,
        int uvPixelStride,
        uint32_t *rect
);

#endif
