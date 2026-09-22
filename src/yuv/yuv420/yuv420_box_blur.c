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
 * overflow, undefined behavior in C. Under an explicit two's-complement
 * wraparound model, every query this file issues is bounded by the kernel
 * (2 * radius + 1, capped at 513 by YuvGeometry.maxBlurRadius), so paired
 * inclusion-exclusion reads would reconstruct the right sum regardless of
 * whether the stored cells wrapped — see the longer argument in
 * bgra8888_mean_blur.c, which this file mirrors. But that argument assumes a
 * wraparound guarantee C does not give: signed overflow is UB, not defined
 * wraparound, so the int32_t table build had no actual correctness
 * guarantee at any radius. This widening removes that UB outright and
 * additionally guards against a query shape this file does not currently
 * have.
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
 *
 * `sat` and `temp` are caller-owned scratch, at least width * height entries
 * each (int64_t and uint8_t respectively, tight -- not rowStride-sized): one
 * pair sized for the luma plane is reused for the smaller chroma planes,
 * instead of a fresh malloc/free pair per plane.
 *
 * CONTRACT: every call site passes src == dst (in-place blur on image->y/u/v).
 * The unpack loop only reads the `width` valid samples of each row through
 * pixelStride, and the final writeback loop only writes those same samples
 * back through pixelStride; padding bytes between samples (pixelStride > 1)
 * or past width (rowStride > width * pixelStride) are never read or written,
 * so they survive untouched only because src and dst are the same buffer. A
 * future caller with src != dst would need to also copy dst's padding from
 * src first, or the destination's gaps would be left uninitialized/stale.
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
        int bottom,
        int64_t *sat,
        uint8_t *temp
) {
    for (int y = 0; y < height; ++y) {
        const uint8_t *row = src + y * rowStride;
        for (int x = 0; x < width; ++x) {
            temp[y * width + x] = row[x * pixelStride];
        }
    }

    for (int y = 0; y < height; ++y) {
        int64_t rowSum = 0;
        for (int x = 0; x < width; ++x) {
            rowSum += temp[y * width + x];
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

            temp[y * width + x] = (uint8_t)((sum + half) / area);
        }
    }

    for (int y = 0; y < height; ++y) {
        uint8_t *row = dst + y * rowStride;
        for (int x = 0; x < width; ++x) {
            row[x * pixelStride] = temp[y * width + x];
        }
    }
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

    // One sat/temp scratch pair for the whole call, sized for the luma plane
    // (always >= each chroma plane in both dimensions) and reused for U and
    // V, instead of a fresh malloc/free pair per plane.
    int64_t *sat = (int64_t *) calloc((size_t) width * (size_t) height, sizeof(int64_t));
    uint8_t *temp = (uint8_t *) malloc((size_t) width * (size_t) height);
    if (!sat || !temp) {
        free(sat);
        free(temp);
        return;
    }

    yuv_box_blur_plane(image->y, image->y, width, height, image->yRowStride, image->yPixelStride, radius, left, top, right, bottom, sat, temp);

    // Chroma ROI is the luma ROI's footprint at half resolution, rounded
    // outward so a luma-odd edge is still covered.
    const int uvLeft = left / 2;
    const int uvTop = top / 2;
    const int uvRight = MIN(uvWidth, (right + 1) / 2);
    const int uvBottom = MIN(uvHeight, (bottom + 1) / 2);
    if (uvLeft < uvRight && uvTop < uvBottom) {
        yuv_box_blur_plane(
                image->u, image->u, uvWidth, uvHeight, image->uvRowStride, image->uvPixelStride, radius, uvLeft, uvTop, uvRight, uvBottom, sat, temp);
        yuv_box_blur_plane(
                image->v, image->v, uvWidth, uvHeight, image->uvRowStride, image->uvPixelStride, radius, uvLeft, uvTop, uvRight, uvBottom, sat, temp);
    }

    free(sat);
    free(temp);
}
