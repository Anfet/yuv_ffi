#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_negate(
        YUVDef *image
) {
    int y_plane_size = image->height * image->yRowStride;
    int uv_plane_size = (image->height / 2) * image->uvRowStride;

    // Invert the luma
    for (int i = 0; i < y_plane_size; ++i) {
        image->y[i] = 255 - image->y[i];
    }

    // Invert the color (symmetrically around 128)
    for (int i = 0; i < uv_plane_size; ++i) {
        image->u[i] = 256 - image->u[i]; // or (255 - (u_src[i] - 128)) + 128
    }
}
