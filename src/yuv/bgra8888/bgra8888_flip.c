#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_flip_horizontally(
        YUVDef *image
) {
    const int bytesPerPixel = image->yPixelStride;
    uint8_t* temp = (uint8_t*)malloc(bytesPerPixel);
    if (!temp) return;
    const int height = image->height;
    const int width = image->width;
    uint8_t *data = image->y;

    for (int y = 0; y < height; y++) {
        uint8_t *row = data + y * width * bytesPerPixel;
        for (int x = 0; x < width / 2; x++) {
            uint8_t *left = row + x * bytesPerPixel;
            uint8_t *right = row + (width - 1 - x) * bytesPerPixel;

            memcpy(temp, left, bytesPerPixel);
            memcpy(left, right, bytesPerPixel);
            memcpy(right, temp, bytesPerPixel);
        }
    }
    free(temp);
}

FFI_PLUGIN_EXPORT void bgra8888_flip_vertically(
        YUVDef *image
) {
    uint8_t *data = image->y;
    const int height = image->height;
    const int width = image->width;

    const int bytesPerPixel = image->yPixelStride;
    uint8_t *tempRow = (uint8_t *) malloc(width * bytesPerPixel);


    for (int y = 0; y < height / 2; y++) {
        uint8_t *topRow = data + y * width * bytesPerPixel;
        uint8_t *botRow = data + (height - 1 - y) * width * bytesPerPixel;

        memcpy(tempRow, topRow, width * bytesPerPixel);
        memcpy(topRow, botRow, width * bytesPerPixel);
        memcpy(botRow, tempRow, width * bytesPerPixel);
    }

    free(tempRow);
}
