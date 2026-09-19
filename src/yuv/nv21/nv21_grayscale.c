#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_grayscale(
        YUVDef *image
) {
    const int height = image->height;
    uint8_t *uDst = image->u;

    int uv_height = height / 2;
    int uv_plane_size = uv_height * image->uvRowStride;

    // Fill U and V with 128 (neutral color)
    memset(uDst, 128, uv_plane_size);
}
