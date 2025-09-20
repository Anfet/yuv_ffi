#include "../yuv.h"

// Кроп NV21 (Y + interleaved VU) в прямоугольник.
// src->y = Y plane, src->u = interleaved VU, src->v не используется
// dst->y = Y plane, dst->u = interleaved VU, dst->v не используется
FFI_PLUGIN_EXPORT void nv21_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        int left,
        int top,
        int crop_width,
        int crop_height
) {
    const int y_row_stride  = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;
    const int uv_pixel_stride = src->uvPixelStride; // обычно = 2 (VU пара)

    uint8_t *y_src = src->y;
    uint8_t *vu_src = src->u; // interleaved VU

    uint8_t *y_dst = dst->y;
    uint8_t *vu_dst = dst->u;

    // ---- Y plane ----
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t *src_row = y_src + (top + row) * y_row_stride + left * y_pixel_stride;
        uint8_t *dst_row = y_dst + row * crop_width * y_pixel_stride;
        memcpy(dst_row, src_row, crop_width * y_pixel_stride);
    }

    // ---- VU plane ----
    // NV21 = 4:2:0 → каждая строка UV соответствует 2 строкам Y
    int uv_crop_width  = crop_width  / 2; // число сэмплов VU
    int uv_crop_height = crop_height / 2; // число строк UV
    int crop_uv_x = left / 2;
    int crop_uv_y = top  / 2;

    for (int row = 0; row < uv_crop_height; ++row) {
        const uint8_t *src_row = vu_src + (crop_uv_y + row) * uv_row_stride + crop_uv_x * uv_pixel_stride;
        uint8_t *dst_row = vu_dst + row * uv_crop_width * uv_pixel_stride;

        memcpy(dst_row, src_row, uv_crop_width * uv_pixel_stride);
    }
}
