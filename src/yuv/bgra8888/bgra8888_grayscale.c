#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_grayscale(YUVDef *image) {
    for (int y = 0; y < image->height; y++) {
        uint8_t* row = image->y + y * image->yRowStride;

        for (int x = 0; x < image->width; x++) {
            uint8_t* pixel = row + x * image->yPixelStride;

            // Formula converting RGB to a shade of gray
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];

            // Contract: round((299R + 587G + 114B) / 1000), half-up.
            uint8_t gray = (uint8_t)((299 * r + 587 * g + 114 * b + 500) / 1000);

            // Set every component to the same value (gray)
            pixel[0] = gray; // B
            pixel[1] = gray; // G
            pixel[2] = gray; // R
            // Alpha is left unchanged
        }
    }
}
