#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "log.h"

void yuv420_crop_rect(
        const uint8_t* y_src, const uint8_t* u_src, const uint8_t* v_src,
        uint8_t* y_dst, uint8_t* u_dst, uint8_t* v_dst,
        int src_width, int src_height,
        int crop_x, int crop_y, int crop_width, int crop_height,
        int y_row_stride, int u_row_stride, int v_row_stride,
        int y_pixel_stride, int u_pixel_stride, int v_pixel_stride
) {
    // Crop Y plane
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t* src_row = y_src + (crop_y + row) * y_row_stride + crop_x * y_pixel_stride;
        uint8_t* dst_row = y_dst + row * crop_width * y_pixel_stride;
        memcpy(dst_row, src_row, crop_width * y_pixel_stride);
    }

    // Crop U and V planes
    int uv_crop_width = crop_width / 2;
    int uv_crop_height = crop_height / 2;
    int crop_uv_x = crop_x / 2;
    int crop_uv_y = crop_y / 2;

    for (int row = 0; row < uv_crop_height; ++row) {
        const uint8_t* u_src_row = u_src + (crop_uv_y + row) * u_row_stride + crop_uv_x * u_pixel_stride;
        const uint8_t* v_src_row = v_src + (crop_uv_y + row) * v_row_stride + crop_uv_x * v_pixel_stride;
        uint8_t* u_dst_row = u_dst + row * uv_crop_width * u_pixel_stride;
        uint8_t* v_dst_row = v_dst + row * uv_crop_width * v_pixel_stride;

        memcpy(u_dst_row, u_src_row, uv_crop_width * u_pixel_stride);
        memcpy(v_dst_row, v_src_row, uv_crop_width * v_pixel_stride);
    }
}

