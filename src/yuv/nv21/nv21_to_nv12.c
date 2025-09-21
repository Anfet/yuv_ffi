#include "../yuv.h"


// NV21 (Y + interleaved VU) -> I420 (Y + planar U, V)
// src->y : Y-плоскость NV21
// src->u : интерлив VU (ширина строки = W)
// src->v : не используется
// dst    : I420, где dst->u — U-план, dst->v — V-план (обе размером W/2 x H/2)
FFI_PLUGIN_EXPORT void nvXX_to_nvYY(uint8_t *srcVU, uint8_t *dstUV, int width, int height, int stride) {
    int uvWidth = width / 2;
    int uvHeight = height / 2;
    for (int y = 0; y < uvHeight; ++y) {
        const uint8_t *rowIn  = srcVU + y * stride;
        uint8_t *rowOut = dstUV + y * stride;
        for (int x = 0; x < uvWidth; ++x) {
            rowOut[x * 2 + 0] = rowIn[x * 2 + 1]; // U
            rowOut[x * 2 + 1] = rowIn[x * 2 + 0]; // V
        }
    }
}
