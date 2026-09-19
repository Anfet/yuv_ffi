#include "../yuv.h"

/**
 * Converts RGBA8888 -> NV.
 * Requirements:
 *  - Y plane + interleaved chroma in (U, V) order
 *  - uvPixelStride == 2 (one chroma pair per 2x2 block)
 *  - Formulas match yuv420_from_rgba8888 (BT.601, video range)
 *
 * Chroma order: the public format name is `nv21`, but the established byte
 * order of this project is U first, then V (NV12-like). Every other converter
 * writes and reads it that way: bgra8888_to_nv21 and yuv420_i420_to_nv21 write
 * (U, V), and nv21_to_bgra8888 and nv21_to_i420 read byte 0 as U. This
 * function used to write (V, U), which inverted the colors of a direct
 * RGBA -> NV conversion.
 *
 * Stride note:
 *  - By the public contract the RGBA input is tightly packed
 *    (width * height * 4), so its row stride is width * 4 and does not depend
 *    on the destination yRowStride, which may be padded.
 */
FFI_PLUGIN_EXPORT void nv21_from_rgba8888(const uint8_t *rgba, YUVDef *dst) {
    uint8_t *yPlane = dst->y;
    uint8_t *uv     = dst->u; // interleaved chroma, (U, V) order
    const int width        = dst->width;
    const int height       = dst->height;
    const int yRowStride   = dst->yRowStride;
    const int yPixelStride = dst->yPixelStride;
    const int uvRowStride  = dst->uvRowStride;
    const int uvPixelStride= dst->uvPixelStride; // expected to be 2

    // (optional) guard against an odd descriptor:
    if (uvPixelStride != 2) return;

    // Tightly packed RGBA input: a row is width * 4 bytes.
    const int rgbaRowStride = width * 4;

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            // Index inside the Y plane
            const int yIndex = yuv_index(x, y, yRowStride, yPixelStride);
            const int rgbaIndex = y * rgbaRowStride + x * 4;

            const int r = rgba[rgbaIndex + 0];
            const int g = rgba[rgbaIndex + 1];
            const int b = rgba[rgbaIndex + 2];

            // Same coefficients (BT.601, video range)
            const int yValue = CLAMP(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
            yPlane[yIndex] = (uint8_t)yValue;

            // Chroma is written once per 2x2 block
            if ((x % 2 == 0) && (y % 2 == 0)) {
                int sumU = 0, sumV = 0;

                const int x0 = x;
                const int y0 = y;

                // Gather the 2x2 block within bounds and divide by the actual
                // pixel count, so an edge block of an odd-sized frame is not
                // averaged over four non-existent samples.
                int samples = 0;

                for (int dy = 0; dy < 2; ++dy) {
                    const int yy = y0 + dy;
                    if (yy >= height) continue;

                    const uint8_t *row = rgba + yy * rgbaRowStride;

                    for (int dx = 0; dx < 2; ++dx) {
                        const int xx = x0 + dx;
                        if (xx >= width) continue;

                        const uint8_t *p = row + xx * 4;
                        const int rr = p[0];
                        const int gg = p[1];
                        const int bb = p[2];

                        // U and V from RGBA
                        sumU += ((-38 * rr - 74 * gg + 112 * bb + 128) >> 8) + 128;
                        sumV += ((112 * rr - 94 * gg - 18 * bb + 128) >> 8) + 128;
                        ++samples;
                    }
                }

                // Chroma index for NV (one (U, V) pair per block)
                const int uvIndex = yuv_index(x / 2, y / 2, uvRowStride, uvPixelStride);
                uv[uvIndex + 0] = (uint8_t)CLAMP(sumU / samples); // U
                uv[uvIndex + 1] = (uint8_t)CLAMP(sumV / samples); // V
            }
        }
    }
}
