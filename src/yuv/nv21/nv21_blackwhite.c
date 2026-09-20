#include "../yuv.h"

// RGB-visible blackwhite contract: gray = round((299R + 587G + 114B) / 1000),
// thresholded at >= 128 to pure black/white RGB, then re-encoded. Both black
// (0,0,0) and white (255,255,255) encode to U=V=128, so chroma collapses to a
// neutral fill.
//
// Y is thresholded directly instead of decoding to RGB and recomputing gray:
// the BT.601 limited luma weights (66/129/25) are proportional to the gray
// weights (299/587/114), so Y is already a monotonic affine function of the
// same gray value the source pixel was encoded from. Recovering RGB via the
// decode matrix and recomputing gray stacks decode error on top of the
// unavoidable encode quantization, which is enough to flip pixels whose true
// gray sits within a couple of LSBs of the 128 boundary. Thresholding Y
// directly at its equivalent cutoff (128 in gray space maps to Y in [125,
// 126], verified against the full RGB cube) avoids that extra error source.
// Legacy `nv21` established (U, V) byte order.
FFI_PLUGIN_EXPORT void nv21_blackwhite(YUVDef *image) {
    const int width = image->width;
    const int height = image->height;

    for (int y = 0; y < height; ++y) {
        uint8_t *yRow = image->y + (size_t) y * image->yRowStride;
        for (int x = 0; x < width; ++x) {
            uint8_t *sample = yRow + (size_t) x * image->yPixelStride;
            *sample = (*sample >= 126) ? 235 : 16;
        }
    }

    const int uvHeight = (height + 1) / 2;
    for (int j = 0; j < uvHeight; ++j) {
        uint8_t *uvDst = image->u + (size_t) j * image->uvRowStride;
        const int uvWidth = (width + 1) / 2;
        for (int i = 0; i < uvWidth; ++i) {
            int uvIndex = (size_t) i * image->uvPixelStride;
            uvDst[uvIndex + 0] = 128; // U
            uvDst[uvIndex + 1] = 128; // V
        }
    }
}
