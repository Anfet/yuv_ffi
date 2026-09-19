#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_negate(
        YUVDef *image
) {
    for (int y = 0; y < image->height; y++) {
        uint8_t *row = image->y + y * image->yRowStride;

        for (int x = 0; x < image->width; x++) {
            uint8_t *pixel = row + x * 4;

            // Read the color components
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];


            // Invert every color component
            pixel[0] = CLAMP(255 - b); // B
            pixel[1] = CLAMP(255 - g); // G
            pixel[2] = CLAMP(255 - r); // R
            // Alpha is left unchanged
        }
    }
}
