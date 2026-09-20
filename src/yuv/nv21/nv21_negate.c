#include "../yuv.h"

// RGB-visible negate contract: 255 - channel for R/G/B. The BT.601 limited
// encode matrix is affine-linear in R/G/B, so negating the decoded RGB and
// re-encoding is algebraically equivalent (within 1-2 LSB, verified against
// every input in the RGB cube) to negating Y/U/V directly around their own
// limited-range midpoints: Y' = 251 - Y (since Y spans [16, 235], sum=251),
// U' = V' = 255 - channel (U/V span the full [0, 255] range). This avoids a
// second decode/re-encode round trip stacked on top of the original capture.
// Legacy `nv21` established (U, V) byte order.
FFI_PLUGIN_EXPORT void nv21_negate(
        YUVDef *image
) {
    const int width = image->width;
    const int height = image->height;

    for (int y = 0; y < height; ++y) {
        uint8_t *row = image->y + (size_t) y * image->yRowStride;
        for (int x = 0; x < width; ++x) {
            uint8_t *sample = row + (size_t) x * image->yPixelStride;
            *sample = (uint8_t) CLAMP(251 - *sample);
        }
    }

    const int uvWidth = (width + 1) / 2;
    const int uvHeight = (height + 1) / 2;
    for (int j = 0; j < uvHeight; ++j) {
        uint8_t *uvRow = image->u + (size_t) j * image->uvRowStride;
        for (int i = 0; i < uvWidth; ++i) {
            uint8_t *pair = uvRow + (size_t) i * image->uvPixelStride;
            pair[0] = (uint8_t) (255 - pair[0]); // U
            pair[1] = (uint8_t) (255 - pair[1]); // V
        }
    }
}
