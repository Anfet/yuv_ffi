#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_negate(
        const YUVDef *src
) {
    for (int y = 0; y < src->height; y++) {
        uint8_t *row = src->y + y * src->yRowStride;

        for (int x = 0; x < src->width; x++) {
            uint8_t *pixel = row + x * 4;

            // Формула для преобразования RGB в оттенок серого
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];


            // Устанавливаем все компоненты в одинаковое значение (серый)
            pixel[0] = CLAMP(255 - b); // B
            pixel[1] = CLAMP(255 - g); // G
            pixel[2] = CLAMP(255 - r); // R
            // Alpha оставляем без изменений
        }
    }
}
