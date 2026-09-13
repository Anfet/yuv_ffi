#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_grayscale(
        const YUVDef *src
) {
    const int height = src->height;
    uint8_t *uDst = src->u;

    int uv_height = height / 2;
    int uv_plane_size = uv_height * src->uvRowStride;

    // Fill U and V with 128 (neutral color)
    memset(uDst, 128, uv_plane_size);
}
