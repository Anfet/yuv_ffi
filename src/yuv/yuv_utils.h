#ifndef YUV_UTILS_H
#define YUV_UTILS_H

// Макрос для вычисления индекса пикселя в изображении YUV
#define yuv_index(x, y, rowStride, pixelStride) ((y) * (rowStride) + (x) * (pixelStride))

#endif // YUV_UTILS_H