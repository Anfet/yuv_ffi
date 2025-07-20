#include <stdint.h>

void nv21_to_rgb(uint8_t *nv21, uint8_t *bgra, int width, int height) {
    const int frameSize = width * height;

    for (int y = 0; y < height; y++) {
        int uvRowStart = frameSize + (y >> 1) * width;  // начало строки UV
        for (int x = 0; x < width; x++) {
            int yIndex = y * width + x;
            int uvIndex = uvRowStart + (x & ~1);  // x & ~1 == x, округлённый вниз до чётного

            int Y = nv21[yIndex] & 0xFF;
            int V = nv21[uvIndex] - 128;
            int U = nv21[uvIndex + 1] - 128;

            int R = Y + (int) (1.370705 * V);
            int G = Y - (int) (0.698001 * V + 0.337633 * U);
            int B = Y + (int) (1.732446 * U);

            int pixelIndex = yIndex * 4;
            bgra[pixelIndex + 0] = (uint8_t) B;
            bgra[pixelIndex + 1] = (uint8_t) G;
            bgra[pixelIndex + 2] = (uint8_t) R;
            bgra[pixelIndex + 3] = 255; // Alpha
        }
    }
}
