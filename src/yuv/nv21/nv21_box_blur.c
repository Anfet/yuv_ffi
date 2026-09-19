#include "../yuv.h"

/*
 * Inclusive sum over the rectangle [x1, x2] x [y1, y2] of a summed-area table
 * whose rows are `width` entries wide. Mirrors
 * src/yuv/bgra8888/bgra8888_mean_blur.c::yuv_sat_rect.
 *
 * Entries are int64_t rather than int32_t: the bottom-right SAT cell sums
 * every sample in the plane, up to width * height * 255. A 4K luma plane
 * alone (4096 * 2160 * 255 = 2,256,076,800) already exceeds INT32_MAX, so a
 * 32-bit accumulator would silently overflow into undefined behavior and a
 * wrong blur on any 4K-or-larger frame.
 */
static int64_t yuv_sat_rect(const int64_t *sat, int width, int x1, int y1, int x2, int y2) {
    int64_t sum = sat[(int64_t) y2 * width + x2];
    if (y1 > 0) sum -= sat[(int64_t) (y1 - 1) * width + x2];
    if (x1 > 0) sum -= sat[(int64_t) y2 * width + (x1 - 1)];
    if (x1 > 0 && y1 > 0) sum += sat[(int64_t) (y1 - 1) * width + (x1 - 1)];
    return sum;
}

/*
 * Box blur over a single-channel plane read through `stride`, via a 2D
 * summed-area table. `src` and `dst` may be the same buffer: every read goes
 * through the SAT built from `src` up front, and `dst` is only written from a
 * separate `temp` snapshot at the end.
 *
 * Kernel is always the full `2 * radius + 1` squared with clamp-to-edge
 * replication at the border (the mandated 0.3.0 blur contract) — see
 * src/yuv/bgra8888/bgra8888_mean_blur.c for the weighted-rectangle
 * decomposition this reuses.
 */
static void yuv_box_blur_channel(
        const uint8_t *src,
        uint8_t *dst,
        int width,
        int height,
        int stride,
        int radius,
        int left,
        int top,
        int right,
        int bottom
) {
    int64_t *sat = (int64_t *) calloc((size_t) width * (size_t) height, sizeof(int64_t));
    uint8_t *temp = (uint8_t *) malloc((size_t) width * (size_t) height);
    if (!sat || !temp) {
        free(sat);
        free(temp);
        return;
    }
    for (int y = 0; y < height; ++y) {
        memcpy(temp + y * width, src + y * stride, (size_t) width);
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
        memcpy(dst + y * stride, temp + y * width, (size_t) width);
    }

    free(sat);
    free(temp);
}

FFI_PLUGIN_EXPORT void nv21_box_blur(
        YUVDef *image,
        int radius,
        const uint32_t *rect
) {
    const int width  = image->width;
    const int height = image->height;

    int left = 0, top = 0, right = width, bottom = height;
    if (rect) {
        left   = (int) rect[0];
        top    = (int) rect[1];
        right  = (int) rect[2];
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

    // --- Y plane ---
    // yuv_box_blur_channel walks its plane with a plain row stride (no pixel
    // stride), which matches every native call site: Y always arrives tight
    // per row in this legacy YUVDef ABI.
    yuv_box_blur_channel(image->y, image->y, width, height, image->yRowStride, radius, left, top, right, bottom);

    // --- Chroma ((U, V) interleaved) ---
    //
    // NOTE ON LOCAL NAMES: the v_plane/u_plane identifiers below are
    // historical and do NOT reflect the actual byte order — byte 0 of each
    // pair is U, not V. Unpack and repack use the same (mis)naming
    // symmetrically, so the output is correct; renaming only one of the two
    // loops would silently swap chroma.
    //
    // Chroma dimensions round up on odd luma sizes, matching
    // YuvGeometry.chromaWidth/chromaHeight on the Dart side.
    const int uv_width  = (width + 1) / 2;
    const int uv_height = (height + 1) / 2;

    // Chroma ROI is the luma ROI's footprint at half resolution, rounded
    // outward so a luma-odd edge is still covered.
    const int uvLeft = left / 2;
    const int uvTop = top / 2;
    const int uvRight = MIN(uv_width, (right + 1) / 2);
    const int uvBottom = MIN(uv_height, (bottom + 1) / 2);
    if (uvLeft >= uvRight || uvTop >= uvBottom) {
        return;
    }

    uint8_t *u_plane = (uint8_t *) malloc((size_t) uv_width * uv_height);
    uint8_t *v_plane = (uint8_t *) malloc((size_t) uv_width * uv_height);
    if (!u_plane || !v_plane) {
        free(u_plane);
        free(v_plane);
        return;
    }

    // Unpack into two tight, deinterleaved planes so the shared box-blur
    // helper can walk them like any other single-channel plane.
    for (int y = 0; y < uv_height; ++y) {
        const uint8_t *row = image->u + y * image->uvRowStride;
        for (int x = 0; x < uv_width; ++x) {
            v_plane[y * uv_width + x] = row[x * 2 + 0];
            u_plane[y * uv_width + x] = row[x * 2 + 1];
        }
    }

    yuv_box_blur_channel(u_plane, u_plane, uv_width, uv_height, uv_width, radius, uvLeft, uvTop, uvRight, uvBottom);
    yuv_box_blur_channel(v_plane, v_plane, uv_width, uv_height, uv_width, radius, uvLeft, uvTop, uvRight, uvBottom);

    // Pack back into the interleaved chroma plane, mirroring the unpack above.
    for (int y = 0; y < uv_height; ++y) {
        uint8_t *row = image->u + y * image->uvRowStride;
        for (int x = 0; x < uv_width; ++x) {
            row[x * 2 + 0] = v_plane[y * uv_width + x];
            row[x * 2 + 1] = u_plane[y * uv_width + x];
        }
    }

    free(u_plane);
    free(v_plane);
}
