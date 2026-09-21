#include "../yuv.h"


FFI_PLUGIN_EXPORT void yuv420_gaussblur(
        YUVDef *image,
        int radius,
        int sigma
) {
    const int width = image->width;
    const int height = image->height;
    uint8_t *y_src = image->y;
    uint8_t *y_dst = image->y;
    uint8_t *u_src = image->u;
    uint8_t *u_dst = image->u;
    uint8_t *v_src = image->v;
    uint8_t *v_dst = image->v;
    const int y_row_stride = image->yRowStride;
    const int y_pixel_stride = image->yPixelStride;
    const int uv_row_stride = image->uvRowStride;
    const int uv_pixel_stride = image->uvPixelStride;

    // gaussian_blur_plane_strided takes sigma as float; the public signature
    // keeps it int (matches the generated FFI binding), so the conversion is
    // made explicit here rather than left to an implicit narrowing/widening
    // conversion MSVC's /W4 flags as C4244.
    const float sigmaF = (float) sigma;

    // Chroma dimensions round up on odd luma sizes, matching
    // YuvGeometry.chromaWidth/chromaHeight on the Dart side.
    const int uv_width = (width + 1) / 2;
    const int uv_height = (height + 1) / 2;

    // One kernel and one bounded scratch set for the whole call instead of
    // one triple per plane: the luma plane is always >= each chroma plane in
    // both dimensions, so sizing scratch for it covers Y, U and V alike.
    float *kernel = (float *) malloc((size_t) (2 * radius + 1) * sizeof(float));
    const int lineLen = width > height ? width : height;
    uint8_t *line_in = (uint8_t *) malloc((size_t) lineLen);
    uint8_t *line_out = (uint8_t *) malloc((size_t) lineLen);
    uint8_t *tmp = (uint8_t *) malloc((size_t) width * (size_t) height);
    if (!kernel || !line_in || !line_out || !tmp) {
        free(kernel);
        free(line_in);
        free(line_out);
        free(tmp);
        return;
    }
    generate_gaussian_kernel(kernel, radius, sigmaF);
    YuvGaussianScratch scratch = {line_in, line_out, tmp};

    gaussian_blur_plane_strided_with_kernel(
            y_src, y_dst,
            width, height,
            y_row_stride, y_pixel_stride,
            radius, kernel, &scratch
    );

    gaussian_blur_plane_strided_with_kernel(
            u_src, u_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, kernel, &scratch
    );

    gaussian_blur_plane_strided_with_kernel(
            v_src, v_dst,
            uv_width, uv_height,
            uv_row_stride, uv_pixel_stride,
            radius, kernel, &scratch
    );

    free(kernel);
    free(line_in);
    free(line_out);
    free(tmp);
}


