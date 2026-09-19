#include "../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_blackwhite(YUVDef *image) {
    const int height = image->height;
    const int yRowStride = image->yRowStride;
    const int uvRowStride = image->uvRowStride;
    uint8_t *ySrc = image->y;
    uint8_t *uDst = image->u;
    uint8_t *vDst = image->v;

    int y_plane_size = height * yRowStride;
    int uv_plane_size = height / 2 * uvRowStride;

    // Threshold the luma: 0 or 255
    for (int i = 0; i < y_plane_size; ++i) {
        ySrc[i] = ySrc[i] >= 127 ? 255 : 0;
    }

    // Drop the color: make it neutral gray
    memset(uDst, 128, uv_plane_size);
    memset(vDst, 128, uv_plane_size);
}
