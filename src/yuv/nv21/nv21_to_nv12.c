#include "../yuv.h"


// Swaps the interleaved chroma order: (V,U) <-> (U,V).
//
// srcVU / dstUV : interleaved chroma planes
// width, height : frame size in pixels (not chroma size)
// stride        : shared row stride of both planes
//
// ABI note: a single stride describes both the source and the destination, so
// the caller must pass two planes with an identical layout. This is why the
// Dart wrappers allocate the destination with the stride of the source. The
// signature is kept deliberately: changing it would require rebuilding the
// WASM exports in lockstep, and the emscripten toolchain is not available
// everywhere.
FFI_PLUGIN_EXPORT void nvXX_to_nvYY(uint8_t *srcVU, uint8_t *dstUV, int width, int height, int stride) {
    // Odd sizes: chroma is rounded up, matching the ceil allocation on the Dart
    // side. Otherwise the trailing row and column would stay uninitialized.
    const int uvWidth = (width + 1) / 2;
    const int uvHeight = (height + 1) / 2;

    // The last pair occupies two bytes, so a row must hold uvWidth * 2 bytes.
    // With a shorter stride, process only as many pairs as actually fit.
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
