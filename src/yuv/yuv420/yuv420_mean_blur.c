#include "../yuv.h"

FFI_PLUGIN_EXPORT void yuv420_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    uint8_t *y_src = image->y;

    const int height = image->height;
    const int width = image->width;
    const int rowStride = image->yRowStride;
    const int pixelStride = image->yPixelStride;

    const int k = radius / 2;

    int left = rect ? rect[0] : 0;
    int top = rect ? rect[1] : 0;
    int right = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            int sum = 0;
            int count = 0;

            for (int dy = -k; dy <= k; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= height) continue;

                for (int dx = -k; dx <= k; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= width) continue;

                    int src_index = yuv_index(nx, ny, rowStride, pixelStride);
                    sum += y_src[src_index];
                    count++;
                }
            }

            int dst_index = yuv_index(x, y, rowStride, pixelStride);
            y_src[dst_index] = sum / count;
        }
    }
}
