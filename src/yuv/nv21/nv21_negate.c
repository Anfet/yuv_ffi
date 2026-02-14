#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_negate(
        const YUVDef *src
) {
    int y_plane_size = src->height * src->yRowStride;
    int uv_plane_size = (src->height / 2) * src->uvRowStride;

    // Инвертируем яркость
    for (int i = 0; i < y_plane_size; ++i) {
        src->y[i] = 255 - src->y[i];
    }

    // Инвертируем цвет (симметрично вокруг 128)
    for (int i = 0; i < uv_plane_size; ++i) {
        src->u[i] = 256 - src->u[i]; // или (255 - (u_src[i] - 128)) + 128
    }
}
