#include "../yuv.h"

// --- Gaussian blur for the legacy `nv21` format ---
// image->y = Y plane
// image->u = interleaved chroma plane in (U, V) order, image->v unused
//
// NOTE ON LOCAL NAMES: the vu_*/v_plane/u_plane identifiers below are
// historical and do NOT reflect the actual byte order — byte 0 of each pair
// is U, not V. They are left untouched deliberately: unpack and repack use
// the same (mis)naming symmetrically, so the output is correct, and renaming
// only one of the two loops would silently swap chroma. The blur reference
// cases that would catch such a mistake are currently red, so the rename is
// deferred until they are restored.
FFI_PLUGIN_EXPORT void nv21_gaussian_blur(
        YUVDef *image,
        int radius,
        float sigma
) {
    const int width = image->width;
    const int height = image->height;

    uint8_t *y_src = image->y;
    uint8_t *y_dst = image->y;
    uint8_t *vu_src = image->u;
    uint8_t *vu_dst = image->u;

    const int y_row_stride = image->yRowStride;
    const int y_pixel_stride = image->yPixelStride;
    const int uv_row_stride = image->uvRowStride;

    // --- Y plane ---
    gaussian_blur_plane_strided(
            y_src, y_dst,
            width, height,
            y_row_stride, y_pixel_stride,
            radius, sigma
    );

    // --- Chroma plane ((U, V) interleaved) ---
    const int uv_width = width / 2;
    const int uv_height = height / 2;

    uint8_t *u_plane = (uint8_t *) malloc(uv_width * uv_height);
    uint8_t *v_plane = (uint8_t *) malloc(uv_width * uv_height);

    // Unpack the interleaved chroma into two separate planes.
    // (Local names are historical — see the note at the top of this file.)
    for (int y = 0; y < uv_height; ++y) {
        const uint8_t *row = vu_src + y * uv_row_stride;
        for (int x = 0; x < uv_width; ++x) {
            v_plane[y * uv_width + x] = row[x * 2 + 0];
            u_plane[y * uv_width + x] = row[x * 2 + 1];
        }
    }

    // Blur U and V separately
    gaussian_blur_plane_strided(
            u_plane, u_plane,
            uv_width, uv_height,
            uv_width, 1,
            radius, sigma
    );
    gaussian_blur_plane_strided(
            v_plane, v_plane,
            uv_width, uv_height,
            uv_width, 1,
            radius, sigma
    );

    // Pack back into the interleaved chroma plane, mirroring the unpack above
    for (int y = 0; y < uv_height; ++y) {
        uint8_t *row = vu_dst + y * uv_row_stride;
        for (int x = 0; x < uv_width; ++x) {
            row[x * 2 + 0] = v_plane[y * uv_width + x];
            row[x * 2 + 1] = u_plane[y * uv_width + x];
        }
    }

    free(u_plane);
    free(v_plane);
}
