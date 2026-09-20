#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_blackwhite(YUVDef *image) {
    const int BINARY_THRESHOLD = 128;
    for (int y = 0; y < image->height; y++) {
        uint8_t* row = image->y + y * image->yRowStride;

        for (int x = 0; x < image->width; x++) {
            uint8_t* pixel = row + x * 4;

            // Convert RGB to brightness using the shared grayscale contract:
            // round((299R + 587G + 114B) / 1000), half-up.
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];
            uint8_t brightness = (uint8_t)((299 * r + 587 * g + 114 * b + 500) / 1000);

            // Thresholding
            uint8_t binary_value = (brightness >= BINARY_THRESHOLD) ? 255 : 0;

            // Set every color component to the same binary value
            pixel[0] = binary_value; // B
            pixel[1] = binary_value; // G
            pixel[2] = binary_value; // R
            // Alpha is left unchanged
        }
    }
}
