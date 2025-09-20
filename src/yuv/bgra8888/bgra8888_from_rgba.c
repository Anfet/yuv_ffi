#include "..//yuv.h"

FFI_PLUGIN_EXPORT void bgra8888_from_rgba8888(const uint8_t *rgba, const YUVDef *dst) {
    int width = dst->width;
    int height = dst->height;
    uint8_t *buf = dst->y;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int p = y * (width * 4) + x * 4;
            buf[p] = rgba[p + 2]; //b
            buf[p + 1] = rgba[p + 1]; //g
            buf[p + 2] = rgba[p]; //r
            buf[p + 3] = rgba[p + 3]; //a
        }
    }
}