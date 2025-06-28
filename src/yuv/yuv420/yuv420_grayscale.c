#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "log.h"

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
) {
    int y_plane_size = height  *  width * y_pixel_stride;
    int uv_width = width / 2;
    int uv_height = height / 2;
    int uv_plane_size = uv_width * uv_height  * uv_pixel_stride;

    // Копируем Y как есть
    memcpy(y_dst, y_src, y_plane_size);

    // Заполняем U и V 128 (нейтральный цвет)
    memset(u_dst, 128, uv_plane_size);
    memset(v_dst, 128, uv_plane_size);
}
