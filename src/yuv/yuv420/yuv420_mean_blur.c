#include "../yuv.h"

/*
 * meanBlur is the same uniform-average filter as boxBlur (0.3.0 contract: both
 * public entry points share one kernel/border/rounding definition). Delegating
 * to yuv420_box_blur avoids a second, potentially diverging implementation.
 */
FFI_PLUGIN_EXPORT void yuv420_box_blur(YUVDef *image, int radius, const uint32_t *rect);

FFI_PLUGIN_EXPORT void yuv420_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    yuv420_box_blur(image, radius, rect);
}
