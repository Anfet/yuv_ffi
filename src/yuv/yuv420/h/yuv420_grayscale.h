#ifndef GRAYSCALE_I420_H
#define GRAYSCALE_I420_H

#include <stdint.h>

void yuv420_grayscale(
        const uint8_t *y_src,
        int y_row_stride,
        int y_pixel_stride,
        int uv_row_stride,
        int uv_pixel_stride,
        int width,
        int height,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst
);

#endif
