#include "../yuv.h"


FFI_PLUGIN_EXPORT void yuv420_gaussblur(
        YUVDef *image,
        int radius,
        int sigma
) {
    const int width = image->width;
    const int height = image->height;
    uint8_t *y_src = image->y;
    uint8_t *y_dst = image->y;
    uint8_t *u_src = image->u;
    uint8_t *u_dst = image->u;
    uint8_t *v_src = image->v;
    uint8_t *v_dst = image->v;
    const int y_row_stride = image->yRowStride;
    const int y_pixel_stride = image->yPixelStride;
    const int uv_row_stride = image->uvRowStride;
    const int uv_pixel_stride = image->uvPixelStride;

    gaussian_blur_plane_strided(
            y_src, y_dst,
            width, height,
            y_row_stride, y_pixel_stride,
            radius, sigma
    );

    int uv_width = width / 2;
    int uv_height = height / 2;

    gaussian_blur_plane_strided(
            u_src, u_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, sigma
    );

    gaussian_blur_plane_strided(
            v_src, v_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, sigma
    );
}


