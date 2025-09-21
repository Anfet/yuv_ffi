#include "../yuv.h"bgra8888_gaussblur


FFI_PLUGIN_EXPORT void yuv420_gaussblur(
        const YUVDef *src,
        int radius,
        int sigma
) {
    const int width = src->width;
    const int height = src->height;
    uint8_t *y_src = src->y;
    uint8_t *y_dst = src->y;
    uint8_t *u_src = src->u;
    uint8_t *u_dst = src->u;
    uint8_t *v_src = src->v;
    uint8_t *v_dst = src->v;
    const int y_row_stride = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;
    const int uv_pixel_stride = src->uvPixelStride;

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


