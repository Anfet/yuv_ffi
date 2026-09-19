#ifndef YUV_H
#define YUV_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "utils/h/yuv_utils.h"
#include "utils/h/log.h"
#include "utils/h/gauss.h"

#ifdef _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

/*
 * Legacy pre-0.3 descriptor. It carries no buffer length field, only pointers
 * and strides, so an adapter that builds a validated view (see
 * src/yuv/utils/h/validated_view.h) from a YUVDef can validate only what
 * YUVDef itself carries: non-null pointers and positive geometry/strides. It
 * cannot verify that the caller's real allocation is at least the computed
 * minimum span/size, because that length was never given to it. Full
 * caller-verified length checking arrives with the section-9 ABI's explicit
 * `length` field (YUV-36); do not treat a YUVDef-based adapter as having
 * proven the same guarantee as a length-aware YuvConstPlaneV1/YuvMutablePlaneV1.
 */
typedef struct {
    uint8_t *y;
    uint8_t *u;
    uint8_t *v;
    int width;
    int height;
    int yRowStride;
    int yPixelStride;
    int uvRowStride;
    int uvPixelStride;
} YUVDef;

#endif