#include <stdint.h>
#include <stdlib.h>
#include <math.h>

static inline uint8_t

clamp(int value) {
    return (uint8_t)(value < 0 ? 0 : (value > 255 ? 255 : value));
}

void yuv420_to_bgra8888(
        const uint8_t *yPlane,
        const uint8_t *uPlane,
        const uint8_t *vPlane,
        int yRowStride,
        int uvRowStride,
        int uvPixelStride,
        int width,
        int height,
        uint8_t *outBgra
) {
    int uvIndex, yIndex;
    int yp, up, vp;
    int r, g, b;

    for (int y = 0; y < height; y++) {
        int yRowStart = y * yRowStride;
        int uvRowStart = (y >> 1) * uvRowStride;

        for (int x = 0; x < width; x++) {
            yIndex = yRowStart + x;
            uvIndex = uvRowStart + (x >> 1) * uvPixelStride;

            yp = yPlane[yIndex];
            up = uPlane[uvIndex] - 128;
            vp = vPlane[uvIndex] - 128;

            r = (int) (yp + 1.370705 * vp);
            g = (int) (yp - 0.337633 * up - 0.698001 * vp);
            b = (int) (yp + 1.732446 * up);

            int outIndex = (y * width + x) * 4;
            outBgra[outIndex + 0] = clamp(b);
            outBgra[outIndex + 1] = clamp(g);
            outBgra[outIndex + 2] = clamp(r);
            outBgra[outIndex + 3] = 255;
        }
    }
}
