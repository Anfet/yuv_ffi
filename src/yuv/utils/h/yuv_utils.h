#ifndef YUV_UTILS_H
#define YUV_UTILS_H

#include <string.h>
#include <stdint.h>

// Макрос для вычисления индекса пикселя в изображении YUV
#define yuv_index(x, y, rowStride, pixelStride) ((y) * (rowStride) + (x) * (pixelStride))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define CLAMP(x) ((x) < 0 ? 0 : ((x) > 255 ? 255 : (x)))

static inline void swap_bytes(void* a, void* b, size_t len) {
    if (len == 1) {
        uint8_t tmp = *(uint8_t*)a;
        *(uint8_t*)a = *(uint8_t*)b;
        *(uint8_t*)b = tmp;
    } else {
        uint8_t temp[len];
        memcpy(temp, b, len);
        memcpy(b, a, len);
        memcpy(a, temp, len);
    }
}

#endif // YUV_UTILS_H