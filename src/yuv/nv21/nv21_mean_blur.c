#include "../yuv.h"

/*
 * meanBlur is the same uniform-average filter as boxBlur (0.3.0 contract: both
 * public entry points share one kernel/border/rounding definition). Delegating
 * to nv21_box_blur avoids a second, potentially diverging implementation.
 */
FFI_PLUGIN_EXPORT void nv21_box_blur(YUVDef *image, int radius, const uint32_t *rect);

FFI_PLUGIN_EXPORT void nv21_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    nv21_box_blur(image, radius, rect);
}
