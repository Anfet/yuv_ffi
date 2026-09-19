#include "../yuv.h"

/*
 * Inclusive sum over the rectangle [x1, x2] x [y1, y2] of a summed-area table
 * whose rows are `width` entries wide. Mirrors
 * src/yuv/bgra8888/bgra8888_mean_blur.c::yuv_sat_rect.
 *
 * Entries are int64_t rather than int32_t: the bottom-right SAT cell sums
 * every sample in the plane, up to width * height * 255. A 4K luma plane
 * alone (4096 * 2160 * 255 = 2,256,076,800) already exceeds INT32_MAX, so a
 * 32-bit accumulator would overflow during the table build — signed
 * overflow, undefined behavior in C on its own terms. In practice every
 * query this file issues is bounded by the kernel
 * (2 * radius + 1, capped at 513 by YuvGeometry.maxBlurRadius), so no single
 * query result approaches INT32_MAX even on a huge frame, and paired
 * inclusion-exclusion reads reconstruct the right sum modulo 2^32 regardless
 * of whether the stored cells wrapped — see the longer argument in
 * bgra8888_mean_blur.c, which this file mirrors. The widening removes real
 * UB and guards against a query shape this file does not currently have; it
 * is not evidence of an observed wrong blur.
 */
static int64_t yuv_sat_rect(const int64_t *sat, int width, int x1, int y1, int x2, int y2) {
    int64_t sum = sat[(int64_t) y2 * width + x2];
    if (y1 > 0) sum -= sat[(int64_t) (y1 - 1) * width + x2];
    if (x1 > 0) sum -= sat[(int64_t) y2 * width + (x1 - 1)];
    if (x1 > 0 && y1 > 0) sum += sat[(int64_t) (y1 - 1) * width + (x1 - 1)];
    return sum;
}

/*
 * Box blur over one plane, honouring rowStride/pixelStride, via a single 2D
 * summed-area table. `src` and `dst` may be the same buffer: every read goes
 * through the SAT built from `src`, and `dst` is only ever written at the very
 * end, so this is safe as an in-place update.
 *
 * The kernel is always the full `2 * radius + 1` squared, with clamp-to-edge
 * replication at the border (the mandated 0.3.0 blur contract): a window cell
 * that falls outside the plane is replaced by the nearest in-bounds row/column
 * rather than shrinking the averaging window. Replication is expressed as
 * integer weights over SAT rectangles (base window + edge bands + corners),
 * the same decomposition YUV-42 uses for bgra8888_mean_blur, so the average is
 * one rounding step instead of the two a separable horizontal-then-vertical
 * pass would introduce.
 */
static void yuv_box_blur_plane(
        const uint8_t *src,
        uint8_t *dst,
        int width,
        int height,
        int rowStride,
        int pixelStride,
        int radius,
        int left,
        int top,
        int right,
        int bottom
) {
    int64_t *sat = (int64_t *) calloc((size_t) width * (size_t) height, sizeof(int64_t));
    uint8_t *temp = (uint8_t *) malloc((size_t) height * rowStride);
    if (!sat || !temp) {
        free(sat);
        free(temp);
        return;
    }
    memcpy(temp, src, (size_t) height * rowStride);

    for (int y = 0; y < height; ++y) {
        int64_t rowSum = 0;
        const uint8_t *row = src + y * rowStride;
        for (int x = 0; x < width; ++x) {
            rowSum += row[x * pixelStride];
            const int64_t satIdx = (int64_t) y * width + x;
            sat[satIdx] = rowSum + (y > 0 ? sat[(int64_t) (y - 1) * width + x] : 0);
        }
    }

    const int kernel = 2 * radius + 1;
    const int area = kernel * kernel;
    const int half = area / 2;

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

            // Base rectangle, each sample once; replicated edge bands; then
            // corners, missing from both a row and a column and so counted
            // padTop*padLeft times and so on.
            int64_t sum = 0;
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
                if (weight == 0) continue;
                sum += (int64_t) weight * yuv_sat_rect(sat, width, parts[i].x1, parts[i].y1, parts[i].x2, parts[i].y2);
            }

            temp[y * rowStride + x * pixelStride] = (uint8_t)((sum + half) / area);
        }
    }

    memcpy(dst, temp, (size_t) height * rowStride);

    free(sat);
    free(temp);
}

FFI_PLUGIN_EXPORT void yuv420_box_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    const int width = image->width;
    const int height = image->height;

    // Chroma dimensions round up on odd luma sizes, matching
    // YuvGeometry.chromaWidth/chromaHeight on the Dart side.
    const int uvWidth = (width + 1) / 2;
    const int uvHeight = (height + 1) / 2;

    int left = 0, top = 0, right = width, bottom = height;
    if (rect) {
        left = (int) rect[0];
        top = (int) rect[1];
        right = (int) rect[2];
        bottom = (int) rect[3];
    }
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > width) right = width;
    if (bottom > height) bottom = height;

    if (left >= right || top >= bottom) {
        // Empty ROI: nothing to blur.
        return;
    }

    yuv_box_blur_plane(image->y, image->y, width, height, image->yRowStride, image->yPixelStride, radius, left, top, right, bottom);

    // Chroma ROI is the luma ROI's footprint at half resolution, rounded
    // outward so a luma-odd edge is still covered.
    const int uvLeft = left / 2;
    const int uvTop = top / 2;
    const int uvRight = MIN(uvWidth, (right + 1) / 2);
    const int uvBottom = MIN(uvHeight, (bottom + 1) / 2);
    if (uvLeft < uvRight && uvTop < uvBottom) {
        yuv_box_blur_plane(
                image->u, image->u, uvWidth, uvHeight, image->uvRowStride, image->uvPixelStride, radius, uvLeft, uvTop, uvRight, uvBottom);
        yuv_box_blur_plane(
                image->v, image->v, uvWidth, uvHeight, image->uvRowStride, image->uvPixelStride, radius, uvLeft, uvTop, uvRight, uvBottom);
    }
}
