#ifndef GAUSS_NV21_H
#define GAUSS_NV21_H

#include <stdint.h>

void nv21_gaussian_blur(
        const YUVDef *src,
        int radius,
        float sigma
);

#endif
