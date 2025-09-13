#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/yuv420.h"

void nv21_grayscale(
        const YUVDef *src
) {
    const int height = src->height;
    uint8_t *uDst = src->u;

    int uv_height = height / 2;
    int uv_plane_size = uv_height * src->uvRowStride;

    // Заполняем U и V 128 (нейтральный цвет)
    memset(uDst, 128, uv_plane_size);
}
