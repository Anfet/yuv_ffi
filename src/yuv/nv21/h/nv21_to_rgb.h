#ifndef NV21_TO_RGB_H
#define NV21_TO_RGB_H

#include <stdint.h>

void nv21_to_rgb(uint8_t* nv21, uint8_t* rgb_out, int width, int height);

#endif
