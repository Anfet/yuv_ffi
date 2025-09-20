#include "..//yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_blackwhite(const YUVDef *src) {
    const int BINARY_THRESHOLD = 128;
    for (int y = 0; y < src->height; y++) {
        uint8_t* row = src->y + y * src->yRowStride;

        for (int x = 0; x < src->width; x++) {
            uint8_t* pixel = row + x * 4;

            // Преобразуем RGB в яркость
            uint8_t b = pixel[0];
            uint8_t g = pixel[1];
            uint8_t r = pixel[2];
            uint8_t brightness = (uint8_t)(0.299f * r + 0.587f * g + 0.114f * b);

            // Бинаризация
            uint8_t binary_value = (brightness > BINARY_THRESHOLD) ? 255 : 0;

            // Устанавливаем все цветовые компоненты в одинаковое бинарное значение
            pixel[0] = binary_value; // B
            pixel[1] = binary_value; // G
            pixel[2] = binary_value; // R
            // Alpha оставляем без изменений
        }
    }
}
