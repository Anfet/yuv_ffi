#ifndef YUV420_TO_BGRA_H
#define YUV420_TO_BGRA_H

#include <stdint.h>

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
);

#endif
