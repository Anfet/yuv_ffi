#include "../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_from_rgba8888(const uint8_t *rgba, YUVDef *dst) {
    uint8_t *yPlane = dst->y;
    uint8_t *uPlane = dst->u;
    uint8_t *vPlane = dst->v;
    const int width = dst->width;
    const int height = dst->height;
    const int yRowStride = dst->yRowStride;
    const int yPixelStride = dst->yPixelStride;
    const int uvRowStride = dst->uvRowStride;
    const int uvPixelStride = dst->uvPixelStride;

    // The public contract requires a tightly packed RGBA input of
    // width * height * 4 bytes, so its row stride is width * 4 and must not be
    // derived from the destination Y stride, which may be padded.
    const int rgbaRowStride = width * 4;

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int yIndex = yuv_index(x, y, yRowStride, yPixelStride);
            int rgbaIndex = y * rgbaRowStride + x * 4;

            int r = rgba[rgbaIndex + 0];
            int g = rgba[rgbaIndex + 1];
            int b = rgba[rgbaIndex + 2];

            int yValue = CLAMP(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);

            yPlane[yIndex] = yValue;

            if ((x % 2 == 0) && (y % 2 == 0)) {
                int sumU = 0, sumV = 0;

                const int x0 = x;
                const int y0 = y;

                // Count the pixels that actually exist, so an edge block of an
                // odd-sized image is averaged over its real sample count
                // instead of always dividing by four.
                int samples = 0;

                for (int dy = 0; dy < 2; ++dy) {
                    const int yy = y0 + dy;
                    if (yy >= height) continue;

                    const uint8_t *row = rgba + yy * rgbaRowStride;

                    for (int dx = 0; dx < 2; ++dx) {
                        const int xx = x0 + dx;
                        if (xx >= width) continue;

                        const uint8_t *p = row + xx * 4;
                        const uint8_t r = p[0];
                        const uint8_t g = p[1];
                        const uint8_t b = p[2];

                        sumU += ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                        sumV += ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                        ++samples;
                    }
                }

                const int uvIndex = yuv_index(x / 2, y / 2, uvRowStride, uvPixelStride);
                uPlane[uvIndex] = CLAMP(sumU / samples);
                vPlane[uvIndex] = CLAMP(sumV / samples);
            }
        }
    }
}
