#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "../yuv/yuv420.h"

void yuv420_grayscale(
        const YUV420Def *src
) {
    const int height = src->height;
    uint8_t *uDst = src->u;
    uint8_t *vDst = src->v;

    int uv_height = height / 2;
    int uv_plane_size = uv_height * src->uvRowStride;

    // Заполняем U и V 128 (нейтральный цвет)
    memset(uDst, 128, uv_plane_size);
    memset(vDst, 128, uv_plane_size);
}
