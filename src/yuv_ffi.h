#ifndef YUV_FFI_H
#define YUV_FFI_H

#include <stdint.h>
#include "yuv/utils/h/log.h"
#include "yuv/utils/h/yuv_utils.h"
#include "yuv/yuv420.h"

#ifdef __cplusplus
extern "C" {
#endif

void nv21_to_rgb(uint8_t *nv21, uint8_t *rgb_out, int width, int height);


#ifdef __cplusplus
}
#endif

#endif // YUV_FFI_H