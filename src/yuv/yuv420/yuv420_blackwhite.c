#include "..//yuv.h"

FFI_PLUGIN_EXPORT void yuv420_blackwhite(const YUVDef *src) {
    const int height = src->height;
    const int yRowStride = src->yRowStride;
    const int uvRowStride = src->uvRowStride;
    uint8_t *ySrc = src->y;
    uint8_t *uDst = src->u;
    uint8_t *vDst = src->v;

    int y_plane_size = height * yRowStride;
    int uv_plane_size = height / 2 * uvRowStride;

    // Бинаризуем яркость: 0 или 255
    for (int i = 0; i < y_plane_size; ++i) {
        ySrc[i] = ySrc[i] >= 127 ? 255 : 0;
    }

    // Цвет убираем — делаем нейтральный серый
    memset(uDst, 128, uv_plane_size);
    memset(vDst, 128, uv_plane_size);
}
