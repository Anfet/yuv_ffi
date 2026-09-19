#include "../yuv.h"

// Crops the legacy `nv21` format (Y + interleaved chroma) to a rectangle.
// src->y = Y plane, src->u = interleaved (U, V) chroma, src->v unused
// dst->y = Y plane, dst->u = interleaved (U, V) chroma, dst->v unused
//
// The copy below is a plain memcpy of whole chroma pairs, so it is agnostic
// to which byte within a pair is U and which is V.
FFI_PLUGIN_EXPORT void nv21_crop_rect(
        const YUVDef *src,
        YUVDef *dst,
        int left,
        int top,
        int crop_width,
        int crop_height
) {
    const int y_row_stride  = src->yRowStride;
    const int y_pixel_stride = src->yPixelStride;
    const int uv_row_stride = src->uvRowStride;
    const int uv_pixel_stride = src->uvPixelStride; // usually 2 (a chroma pair)

    uint8_t *y_src = src->y;
    uint8_t *vu_src = src->u; // interleaved chroma; local name is historical

    uint8_t *y_dst = dst->y;
    uint8_t *vu_dst = dst->u;

    // ---- Y plane ----
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t *src_row = y_src + (top + row) * y_row_stride + left * y_pixel_stride;
        uint8_t *dst_row = y_dst + row * crop_width * y_pixel_stride;
        memcpy(dst_row, src_row, crop_width * y_pixel_stride);
    }

    // ---- Chroma plane ----
    // 4:2:0, so one chroma row corresponds to two Y rows
    int uv_crop_width  = crop_width  / 2; // number of chroma samples
    int uv_crop_height = crop_height / 2; // number of chroma rows
    int crop_uv_x = left / 2;
    int crop_uv_y = top  / 2;

    for (int row = 0; row < uv_crop_height; ++row) {
        const uint8_t *src_row = vu_src + (crop_uv_y + row) * uv_row_stride + crop_uv_x * uv_pixel_stride;
        uint8_t *dst_row = vu_dst + row * uv_crop_width * uv_pixel_stride;

        memcpy(dst_row, src_row, uv_crop_width * uv_pixel_stride);
    }
}
