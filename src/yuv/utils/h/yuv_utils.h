#ifndef YUV_UTILS_H
#define YUV_UTILS_H

// Макрос для вычисления индекса пикселя в изображении YUV
#define yuv_index(x, y, rowStride, pixelStride) ((y) * (rowStride) + (x) * (pixelStride))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define CLAMP(x) ((x) < 0 ? 0 : ((x) > 255 ? 255 : (x)))


#endif // YUV_UTILS_H