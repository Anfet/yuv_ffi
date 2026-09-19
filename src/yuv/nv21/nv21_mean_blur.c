#include "../yuv.h"

FFI_PLUGIN_EXPORT void nv21_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    uint8_t *yData = image->y;
    // Interleaved chroma in (U, V) order: U at byte 0, V at byte 1.
    // NOTE ON LOCAL NAMES: vuData and the sumV/sumU pair below are historical
    // and do NOT reflect that order. They are used symmetrically when reading
    // and writing, so the output is correct; renaming only one side would
    // silently swap chroma. Deferred until the currently red blur reference
    // cases are restored.
    uint8_t *vuData = image->u;

    const int width = image->width;
    const int height = image->height;

    int left   = rect ? rect[0] : 0;
    int top    = rect ? rect[1] : 0;
    int right  = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    // --- Y plane ---
    uint8_t *tempY = (uint8_t*) malloc(width * height);
    memcpy(tempY, yData, width * height);

    int k = radius / 2;

    for (int y = top; y < bottom; ++y) {
        for (int x = left; x < right; ++x) {
            int sum = 0, count = 0;
            for (int dy = -k; dy <= k; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= height) continue;
                for (int dx = -k; dx <= k; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= width) continue;
                    sum += tempY[ny * width + nx];
                    count++;
                }
            }
            yData[y * width + x] = (uint8_t)(sum / count);
        }
    }

    free(tempY);

    // --- Chroma plane ---
    int uvWidth = width / 2;
    int uvHeight = height / 2;
    uint8_t *tempVU = (uint8_t*) malloc(uvWidth * uvHeight * 2);
    memcpy(tempVU, vuData, uvWidth * uvHeight * 2);

    for (int y = 0; y < uvHeight; ++y) {
        for (int x = 0; x < uvWidth; ++x) {
            int sumV = 0, sumU = 0, count = 0;
            for (int dy = -k; dy <= k; ++dy) {
                int ny = y + dy;
                if (ny < 0 || ny >= uvHeight) continue;
                for (int dx = -k; dx <= k; ++dx) {
                    int nx = x + dx;
                    if (nx < 0 || nx >= uvWidth) continue;
                    int idx = (ny * uvWidth + nx) * 2;
                    sumV += tempVU[idx + 0];
                    sumU += tempVU[idx + 1];
                    count++;
                }
            }
            int dstIdx = (y * uvWidth + x) * 2;
            vuData[dstIdx + 0] = (uint8_t)(sumV / count);
            vuData[dstIdx + 1] = (uint8_t)(sumU / count);
        }
    }

    free(tempVU);
}
