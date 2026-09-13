#include "../yuv.h"


// Меняет местами порядок интерлива chroma: (V,U) <-> (U,V).
//
// srcVU / dstUV : интерливные chroma-плоскости
// width, height : размеры кадра в пикселях (не chroma)
// stride        : общий row stride обеих плоскостей
//
// ВНИМАНИЕ к ABI: один stride описывает сразу source и destination, поэтому
// вызывающая сторона обязана передавать две плоскости с одинаковым layout.
// Обёртки в Dart выделяют назначение с stride источника именно поэтому.
// Сигнатура сохранена намеренно: её изменение потребовало бы синхронной
// пересборки WASM-экспортов, а тулчейн emscripten доступен не везде.
FFI_PLUGIN_EXPORT void nvXX_to_nvYY(uint8_t *srcVU, uint8_t *dstUV, int width, int height, int stride) {
    // Нечётные размеры: chroma округляется вверх, как и при аллокации в Dart,
    // иначе крайние строка и колонка остались бы неинициализированными.
    const int uvWidth = (width + 1) / 2;
    const int uvHeight = (height + 1) / 2;

    // Последняя пара занимает два байта, поэтому строка должна вмещать
    // uvWidth * 2 байт; при более коротком stride обрабатываем столько пар,
    // сколько реально помещается.
    int pairsPerRow = uvWidth;
    if (stride > 0 && stride / 2 < pairsPerRow) {
        pairsPerRow = stride / 2;
    }

    for (int y = 0; y < uvHeight; ++y) {
        const uint8_t *rowIn = srcVU + (size_t)y * stride;
        uint8_t *rowOut = dstUV + (size_t)y * stride;
        for (int x = 0; x < pairsPerRow; ++x) {
            const uint8_t first = rowIn[x * 2 + 0];
            const uint8_t second = rowIn[x * 2 + 1];
            rowOut[x * 2 + 0] = second;
            rowOut[x * 2 + 1] = first;
        }
    }
}
