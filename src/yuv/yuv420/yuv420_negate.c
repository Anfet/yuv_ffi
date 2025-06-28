#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "log.h"

void yuv420_negate(
        const uint8_t *y_src,
        const uint8_t *u_src,
        const uint8_t *v_src,
        int y_row_stride,
        int y_pixel_stride,
        int uv_row_stride,
        int uv_pixel_stride,
        int width,
        int height,
        uint8_t *y_dst,
        uint8_t *u_dst,
        uint8_t *v_dst
) {
    int y_plane_size = width * height * y_pixel_stride;
    int uv_plane_size = (width / 2) * (height / 2) * uv_pixel_stride;

    // Инвертируем яркость
    for (int i = 0; i < y_plane_size; ++i) {
        y_dst[i] = 255 - y_src[i];
    }

    // Инвертируем цвет (симметрично вокруг 128)
    for (int i = 0; i < uv_plane_size; ++i) {
        u_dst[i] = 256 - u_src[i]; // или (255 - (u_src[i] - 128)) + 128
        v_dst[i] = 256 - v_src[i];
    }
}
