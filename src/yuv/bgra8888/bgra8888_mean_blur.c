#include "../yuv.h"

/*
 * Inclusive sum over the rectangle [x1, x2] x [y1, y2] of a summed-area table
 * whose rows are `width` entries wide.
 *
 * The inclusion-exclusion terms read the row above and the column left of the
 * rectangle, so they are only subtracted when that row/column exists.
 *
 * Entries are int64_t rather than int32_t: a single-channel SAT cell at the
 * bottom-right corner sums every sample in the plane, up to width * height *
 * 255. That already exceeds INT32_MAX past roughly 2160p (4096 * 2160 * 255 =
 * 2,256,076,800), so a 4K or larger frame would overflow a 32-bit accumulator
 * during the table build — signed overflow, which is undefined behavior in C
 * regardless of what a specific compiler happens to do with it.
 *
 * In practice, every caller of this function passes a rectangle bounded by
 * the kernel (2 * radius + 1, capped at 513 by YuvGeometry.maxBlurRadius), so
 * the *result* of any one query never approaches INT32_MAX even on a huge
 * frame; two's-complement add/subtract is exact modulo 2^32, so a paired
 * inclusion-exclusion query reconstructs the right rectangle sum even from
 * wrapped int32_t cells. The one query shape that reads a table cell
 * unpaired (x1 == 0 && y1 == 0, no subtraction at all) only occurs for the
 * top-left pixel's own kernel, which is bounded the same way. So the
 * overflow was UB and worth removing on its own terms, but it did not
 * produce a wrong average at any legal radius — this widening is defense in
 * depth against UB and against a query shape this file does not currently
 * have, not a fix for an observed wrong blur.
 */
static int64_t yuv_sat_rect(const int64_t *sat, int width, int x1, int y1, int x2, int y2) {
    int64_t sum = sat[(int64_t) y2 * width + x2];
    if (y1 > 0) sum -= sat[(int64_t) (y1 - 1) * width + x2];
    if (x1 > 0) sum -= sat[(int64_t) y2 * width + (x1 - 1)];
    if (x1 > 0 && y1 > 0) sum += sat[(int64_t) (y1 - 1) * width + (x1 - 1)];
    return sum;
}

FFI_PLUGIN_EXPORT void bgra8888_mean_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    uint8_t *data = image->y;
    const int width = image->width;
    const int height = image->height;
    const int rowStride = image->yRowStride;   // width * 4
    const int bytesPerPixel = 4;

    int left   = rect ? rect[0] : 0;
    int top    = rect ? rect[1] : 0;
    int right  = rect ? rect[2] : width;
    int bottom = rect ? rect[3] : height;

    // Clamp ROI to image bounds
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > width) right = width;
    if (bottom > height) bottom = height;

    // Empty ROI is a no-op
    if (left >= right || top >= bottom) {
        return;
    }

    // Integral images. Alpha deliberately has no table: the blur contract
    // keeps alpha exact, so it is copied per pixel rather than averaged.
    //
    // width and height are cast to size_t before multiplying, so the
    // allocation size itself is computed without a 32-bit overflow even
    // though width/height stay declared int (the rest of the file indexes
    // them as int throughout).
    const size_t planeSamples = (size_t) width * (size_t) height;
    int64_t *satB = (int64_t*) calloc(planeSamples, sizeof(int64_t));
    int64_t *satG = (int64_t*) calloc(planeSamples, sizeof(int64_t));
    int64_t *satR = (int64_t*) calloc(planeSamples, sizeof(int64_t));

    if (!satB || !satG || !satR) {
        free(satB); free(satG); free(satR);
        return;
    }

    // Building the summed area table
    for (int y = 0; y < height; ++y) {
        int64_t rowB = 0, rowG = 0, rowR = 0;
        for (int x = 0; x < width; ++x) {
            int srcByteIdx = y * rowStride + x * bytesPerPixel;
            rowB += data[srcByteIdx + 0];
            rowG += data[srcByteIdx + 1];
            rowR += data[srcByteIdx + 2];

            const int64_t satIdx = (int64_t) y * width + x;
            const int64_t satPrevIdx = (int64_t) (y - 1) * width + x;

            satB[satIdx] = rowB + (y > 0 ? satB[satPrevIdx] : 0);
            satG[satIdx] = rowG + (y > 0 ? satG[satPrevIdx] : 0);
            satR[satIdx] = rowR + (y > 0 ? satR[satPrevIdx] : 0);
        }
    }

    // Blur: copy source to temp for deterministic pixel handling outside ROI
    uint8_t *temp = (uint8_t*) malloc(width * height * bytesPerPixel);
    if (!temp) {
        free(satB); free(satG); free(satR);
        return;
    }
    memcpy(temp, data, width * height * bytesPerPixel);

    // Kernel is always (2 * radius + 1)^2 samples. Where the window leaves the
    // image, clamp-to-edge replicates the border pixel, so a missing row or
    // column contributes a copy of the nearest in-bounds one instead of being
    // dropped. Averaging over the truncated in-bounds window would reweight the
    // borders: at (511, 511) with radius 5 that yields 117 where the replicated
    // kernel yields 85, which is what the reference expects.
    //
    // A clamped window is still a rectangle, so the replication is expressed as
    // integer row/column multipliers over the SAT rather than by summing the
    // kernel pixel by pixel: each in-bounds row of the window is counted
    // `rowWeight` times and each in-bounds column `colWeight` times, both 1 in
    // the interior.
    const int kernel = 2 * radius + 1;
    const int area = kernel * kernel;

    for (int y = top; y < bottom; ++y) {
        const int y1 = (y - radius < 0) ? 0 : y - radius;
        const int y2 = (y + radius >= height) ? height - 1 : y + radius;
        const int padTop = y1 - (y - radius);
        const int padBottom = (y + radius) - y2;

        for (int x = left; x < right; ++x) {
            const int x1 = (x - radius < 0) ? 0 : x - radius;
            const int x2 = (x + radius >= width) ? width - 1 : x + radius;
            const int padLeft = x1 - (x - radius);
            const int padRight = (x + radius) - x2;

            // The weighted window separates into the plain rectangle plus extra
            // copies of its edge rows/columns, so each part is one O(1) SAT
            // rectangle sum. Corner overlaps get padTop*padLeft and friends,
            // which is exactly what multiplying the row and column pads gives.
            // Base rectangle, each sample once; then the replicated edge bands;
            // then the corners, which are missing from both a row and a column
            // and so are counted padTop*padLeft times and so on.
            int64_t sumB = 0, sumG = 0, sumR = 0;
            const struct { int x1, y1, x2, y2, weight; } parts[] = {
                { x1, y1, x2, y2, 1 },
                { x1, y1, x2, y1, padTop },
                { x1, y2, x2, y2, padBottom },
                { x1, y1, x1, y2, padLeft },
                { x2, y1, x2, y2, padRight },
                { x1, y1, x1, y1, padTop * padLeft },
                { x2, y1, x2, y1, padTop * padRight },
                { x1, y2, x1, y2, padBottom * padLeft },
                { x2, y2, x2, y2, padBottom * padRight },
            };
            for (size_t i = 0; i < sizeof(parts) / sizeof(parts[0]); ++i) {
                const int weight = parts[i].weight;
                if (weight == 0) {
                    continue;
                }
                sumB += (int64_t) weight * yuv_sat_rect(satB, width, parts[i].x1, parts[i].y1, parts[i].x2, parts[i].y2);
                sumG += (int64_t) weight * yuv_sat_rect(satG, width, parts[i].x1, parts[i].y1, parts[i].x2, parts[i].y2);
                sumR += (int64_t) weight * yuv_sat_rect(satR, width, parts[i].x1, parts[i].y1, parts[i].x2, parts[i].y2);
            }

            // Round half up, matching the reference oracle's `value.round()`.
            // Truncating instead biases every channel down by up to one step.
            const int64_t half = area / 2;
            const int dstByteIdx = y * rowStride + x * bytesPerPixel;
            temp[dstByteIdx + 0] = (uint8_t)((sumB + half) / area);
            temp[dstByteIdx + 1] = (uint8_t)((sumG + half) / area);
            temp[dstByteIdx + 2] = (uint8_t)((sumR + half) / area);
            // Alpha stays exactly as it was: `temp` already holds the source
            // copy, so the byte is left untouched rather than averaged.
        }
    }

    memcpy(data, temp, width * height * bytesPerPixel);

    free(temp);
    free(satB); free(satG); free(satR);
}