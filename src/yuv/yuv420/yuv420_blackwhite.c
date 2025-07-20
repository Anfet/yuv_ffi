#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/utils/h/log.h"

void yuv420_blackwhite(
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
    int y_plane_size = width * height * y_pixel_stride;
    int uv_plane_size = (width / 2) * (height / 2) * uv_pixel_stride;

    // Бинаризуем яркость: 0 или 255
    for (int i = 0; i < y_plane_size; ++i) {
        y_dst[i] = y_src[i] >= 127 ? 255 : 0;
    }

    // Цвет убираем — делаем нейтральный серый
    memset(u_dst, 128, uv_plane_size);
    memset(v_dst, 128, uv_plane_size);
}
