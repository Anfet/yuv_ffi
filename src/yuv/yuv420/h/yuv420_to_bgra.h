#ifndef YUV420_TO_BGRA_H
#define YUV420_TO_BGRA_H

#include <stdint.h>


void yuv420_to_bgra8888(
        const YUVDef *src,
        uint8_t *outBgra
);

#endif
