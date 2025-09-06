#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/yuv420.h"
#include "../yuv/utils/h/yuv_utils.h"

void yuv420_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        const int left,
        const int top,
        const int crop_width,
        const int crop_height
) {

    const int y_row_stride = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;
    const int uv_pixel_stride = src->uvPixelStride;

    uint8_t *y_src = src->y;
    uint8_t *u_src = src->u;
    uint8_t *v_src = src->v;


    uint8_t *y_dst = dst->y;
    uint8_t *u_dst = dst->u;
    uint8_t *v_dst = dst->v;
    // Crop Y plane
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t *src_row = y_src + (top + row) * y_row_stride + left * y_pixel_stride;
        uint8_t *dst_row = y_dst + row * crop_width * y_pixel_stride;
        memcpy(dst_row, src_row, crop_width * y_pixel_stride);
    }

    // Crop U and V planes
    int uv_crop_width = crop_width / 2;
    int uv_crop_height = crop_height / 2;
    int crop_uv_x = left / 2;
    int crop_uv_y = top / 2;

    for (int row = 0; row < uv_crop_height; ++row) {
        const uint8_t *u_src_row = u_src + (crop_uv_y + row) * uv_row_stride + crop_uv_x * uv_pixel_stride;
        const uint8_t *v_src_row = v_src + (crop_uv_y + row) * uv_row_stride + crop_uv_x * uv_pixel_stride;
        uint8_t *u_dst_row = u_dst + row * uv_crop_width * uv_pixel_stride;
        uint8_t *v_dst_row = v_dst + row * uv_crop_width * uv_pixel_stride;

        memcpy(u_dst_row, u_src_row, uv_crop_width * uv_pixel_stride);
        memcpy(v_dst_row, v_src_row, uv_crop_width * uv_pixel_stride);
    }
}

