#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_crop_rect(
        const YUVDef *src,
        const YUVDef *dst,
        const int left,
        const int top,
        const int crop_width,
        const int crop_height
) {


    uint8_t *y_src = src->y;
    uint8_t *y_dst = dst->y;
    // Crop Y plane
    for (int row = 0; row < crop_height; ++row) {
        const uint8_t *src_row = y_src + (top + row) * src->yRowStride + left * src->yPixelStride;
        uint8_t *dst_row = y_dst + row * dst->yRowStride;
        memcpy(dst_row, src_row, crop_width * dst->yPixelStride);
    }

}

