#include "../yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_grayscale(const YUVDef *src) {
    for (int y = 0; y < src->height; y++) {
        uint8_t* row = src->y + y * src->yRowStride;

        for (int x = 0; x < src->width; x++) {
            uint8_t* pixel = row + x * src->yPixelStride;

            // Формула для преобразования RGB в оттенок серого
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];

            // Стандартная формула: Y = 0.299*R + 0.587*G + 0.114*B
            uint8_t gray = (uint8_t)(0.299f * r + 0.587f * g + 0.114f * b);

            // Устанавливаем все компоненты в одинаковое значение (серый)
            pixel[0] = gray; // B
            pixel[1] = gray; // G
            pixel[2] = gray; // R
            // Alpha оставляем без изменений
        }
    }
}
