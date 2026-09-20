#include "../yuv.h"

// RGB-visible grayscale contract: gray = round((299R + 587G + 114B) / 1000),
// applied per pixel to the BT.601 limited-decoded sample, then re-encoded.
// A gray RGB triple (R=G=B) always encodes to U=V=128 regardless of the gray
// value, so chroma collapses to a neutral fill; only Y needs recomputation.
FFI_PLUGIN_EXPORT void yuv420_grayscale(
        YUVDef *image
) {
    const int width = image->width;
    const int height = image->height;

    for (int y = 0; y < height; ++y) {
        uint8_t *yRow = image->y + (size_t) y * image->yRowStride;
        const uint8_t *uRow = image->u + (size_t) (y >> 1) * image->uvRowStride;
        const uint8_t *vRow = image->v + (size_t) (y >> 1) * image->uvRowStride;

        for (int x = 0; x < width; ++x) {
            int Yv = yRow[(size_t) x * image->yPixelStride];
            int Uc = uRow[(size_t) (x >> 1) * image->uvPixelStride] - 128;
            int Vc = vRow[(size_t) (x >> 1) * image->uvPixelStride] - 128;

            int C = Yv - 16;
            int R = CLAMP((298 * C + 409 * Vc + 128) >> 8);
            int G = CLAMP((298 * C - 100 * Uc - 208 * Vc + 128) >> 8);
            int B = CLAMP((298 * C + 516 * Uc + 128) >> 8);

            int gray = (299 * R + 587 * G + 114 * B + 500) / 1000;
            yRow[(size_t) x * image->yPixelStride] = (uint8_t) CLAMP(((220 * gray + 128) >> 8) + 16);
        }
    }

    const int uvHeight = (height + 1) / 2;
    for (int j = 0; j < uvHeight; ++j) {
        uint8_t *uDst = image->u + (size_t) j * image->uvRowStride;
        uint8_t *vDst = image->v + (size_t) j * image->uvRowStride;
        const int uvWidth = (width + 1) / 2;
        for (int i = 0; i < uvWidth; ++i) {
            uDst[(size_t) i * image->uvPixelStride] = 128;
            vDst[(size_t) i * image->uvPixelStride] = 128;
        }
    }
}
