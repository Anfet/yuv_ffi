#include "../yuv.h"

// --- Гауссовый блюр NV21 ---
// src->y = Y plane
// src->u = interleaved VU plane (NV21), src->v не используется
FFI_PLUGIN_EXPORT void nv21_gaussian_blur(
        const YUVDef *src,
        int radius,
        float sigma
) {
    const int width = src->width;
    const int height = src->height;

    uint8_t *y_src = src->y;
    uint8_t *y_dst = src->y;
    uint8_t *vu_src = src->u;
    uint8_t *vu_dst = src->u;

    const int y_row_stride = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;

    // --- Y plane ---
    gaussian_blur_plane_strided(
            y_src, y_dst,
            width, height,
            y_row_stride, y_pixel_stride,
            radius, sigma
    );

    // --- UV plane (VU interleaved) ---
    const int uv_width = width / 2;
    const int uv_height = height / 2;

    uint8_t *u_plane = (uint8_t *) malloc(uv_width * uv_height);
    uint8_t *v_plane = (uint8_t *) malloc(uv_width * uv_height);

    // Распаковка VU → отдельные U и V
    for (int y = 0; y < uv_height; ++y) {
        const uint8_t *row = vu_src + y * uv_row_stride;
        for (int x = 0; x < uv_width; ++x) {
            v_plane[y * uv_width + x] = row[x * 2 + 0];
            u_plane[y * uv_width + x] = row[x * 2 + 1];
        }
    }

    // Размытие U и V по отдельности
    gaussian_blur_plane_strided(
            u_plane, u_plane,
            uv_width, uv_height,
            uv_width, 1,
            radius, sigma
    );
    gaussian_blur_plane_strided(
            v_plane, v_plane,
            uv_width, uv_height,
            uv_width, 1,
            radius, sigma
    );

    // Сборка обратно в interleaved VU
    for (int y = 0; y < uv_height; ++y) {
        uint8_t *row = vu_dst + y * uv_row_stride;
        for (int x = 0; x < uv_width; ++x) {
            row[x * 2 + 0] = v_plane[y * uv_width + x];
            row[x * 2 + 1] = u_plane[y * uv_width + x];
        }
    }

    free(u_plane);
    free(v_plane);
}
