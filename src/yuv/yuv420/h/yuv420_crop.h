#ifndef CROP_I420_H
#define CROP_I420_H

#include <stdint.h>

void yuv420_crop_rect(
        const uint8_t* y_src, const uint8_t* u_src, const uint8_t* v_src,
        uint8_t* y_dst, uint8_t* u_dst, uint8_t* v_dst,
        int src_width, int src_height,
        int crop_x, int crop_y, int crop_width, int crop_height,
        int y_row_stride, int u_row_stride, int v_row_stride,
        int y_pixel_stride, int u_pixel_stride, int v_pixel_stride
);

#endif
