#include "yuv/yuv.h"

void yuv420_from_rgba8888(const uint8_t *rgba, const YUVDef *dst);
void nv21_from_rgba8888(const uint8_t *rgba, const YUVDef *dst);
void yuv420_i420_to_nv21(const YUVDef *src, const YUVDef *dst);
void nv21_to_i420(const YUVDef *src, const YUVDef *dst);
void nvXX_to_nvYY(uint8_t *src, uint8_t *dst, int width, int height, int stride);

static uint8_t *checked_alloc(size_t length) {
    uint8_t *bytes = (uint8_t *)malloc(length);
    if (bytes == NULL) {
        fprintf(stderr, "allocation failed for %zu bytes\n", length);
        exit(2);
    }
    memset(bytes, 0xA5, length);
    return bytes;
}

static int is_logical_offset(int offset, int logical_width, int pixel_stride, int sample_bytes) {
    for (int column = 0; column < logical_width; ++column) {
        const int start = column * pixel_stride;
        if (offset >= start && offset < start + sample_bytes) {
            return 1;
        }
    }
    return 0;
}

static void require_padding_canary(
    const char *label,
    const uint8_t *plane,
    int height,
    int row_stride,
    int logical_width,
    int pixel_stride,
    int sample_bytes
) {
    for (int row = 0; row < height; ++row) {
        for (int offset = 0; offset < row_stride; ++offset) {
            if (!is_logical_offset(offset, logical_width, pixel_stride, sample_bytes) &&
                plane[(size_t)row * row_stride + offset] != 0xA5) {
                fprintf(stderr, "%s padding changed at row=%d offset=%d\n", label, row, offset);
                exit(3);
            }
        }
    }
}

static void require_equal(const char *label, uint8_t actual, uint8_t expected, int row, int column) {
    if (actual != expected) {
        fprintf(
            stderr,
            "%s mismatch at row=%d column=%d: actual=%u expected=%u\n",
            label,
            row,
            column,
            (unsigned)actual,
            (unsigned)expected
        );
        exit(4);
    }
}

static void run_size(int width, int height) {
    const int chroma_width = (width + 1) / 2;
    const int chroma_height = (height + 1) / 2;
    const int y_pixel_stride = 3;
    const int y_row_stride = (width - 1) * y_pixel_stride + 1 + 5;
    const int uv_pixel_stride = 2;
    const int i420_uv_row_stride = (chroma_width - 1) * uv_pixel_stride + 1 + 5;
    const int nv_uv_row_stride = chroma_width * 2 + 5;
    const size_t rgba_length = (size_t)width * height * 4;

    uint8_t *rgba = checked_alloc(rgba_length);
    for (size_t index = 0; index < rgba_length; index += 4) {
        rgba[index + 0] = 255;
        rgba[index + 1] = 0;
        rgba[index + 2] = 0;
        rgba[index + 3] = 255;
    }

    YUVDef i420 = {
        .y = checked_alloc((size_t)height * y_row_stride),
        .u = checked_alloc((size_t)chroma_height * i420_uv_row_stride),
        .v = checked_alloc((size_t)chroma_height * i420_uv_row_stride),
        .width = width,
        .height = height,
        .yRowStride = y_row_stride,
        .yPixelStride = y_pixel_stride,
        .uvRowStride = i420_uv_row_stride,
        .uvPixelStride = uv_pixel_stride,
    };
    yuv420_from_rgba8888(rgba, &i420);
    require_padding_canary("i420.y", i420.y, height, y_row_stride, width, y_pixel_stride, 1);
    require_padding_canary("i420.u", i420.u, chroma_height, i420_uv_row_stride, chroma_width, uv_pixel_stride, 1);
    require_padding_canary("i420.v", i420.v, chroma_height, i420_uv_row_stride, chroma_width, uv_pixel_stride, 1);
    for (int row = 0; row < height; ++row) {
        for (int column = 0; column < width; ++column) {
            require_equal("i420 Y", i420.y[row * y_row_stride + column * y_pixel_stride], 82, row, column);
        }
    }
    for (int row = 0; row < chroma_height; ++row) {
        for (int column = 0; column < chroma_width; ++column) {
            const int offset = row * i420_uv_row_stride + column * uv_pixel_stride;
            require_equal("i420 U", i420.u[offset], 90, row, column);
            require_equal("i420 V", i420.v[offset], 240, row, column);
        }
    }

    YUVDef nv = {
        .y = checked_alloc((size_t)height * y_row_stride),
        .u = checked_alloc((size_t)chroma_height * nv_uv_row_stride),
        .v = NULL,
        .width = width,
        .height = height,
        .yRowStride = y_row_stride,
        .yPixelStride = y_pixel_stride,
        .uvRowStride = nv_uv_row_stride,
        .uvPixelStride = 2,
    };
    nv21_from_rgba8888(rgba, &nv);
    require_padding_canary("nv.y", nv.y, height, y_row_stride, width, y_pixel_stride, 1);
    require_padding_canary("nv.uv", nv.u, chroma_height, nv_uv_row_stride, chroma_width, 2, 2);

    for (int row = 0; row < chroma_height; ++row) {
        for (int column = 0; column < chroma_width; ++column) {
            const int planar = row * i420_uv_row_stride + column * uv_pixel_stride;
            const int interleaved = row * nv_uv_row_stride + column * 2;
            require_equal("direct U", nv.u[interleaved], i420.u[planar], row, column);
            require_equal("direct V", nv.u[interleaved + 1], i420.v[planar], row, column);
        }
    }

    const int tight_y_stride = width;
    const int tight_uv_stride = chroma_width * 2;
    YUVDef converted_nv = {
        .y = checked_alloc((size_t)height * tight_y_stride),
        .u = checked_alloc((size_t)chroma_height * tight_uv_stride),
        .v = NULL,
        .width = width,
        .height = height,
        .yRowStride = tight_y_stride,
        .yPixelStride = 1,
        .uvRowStride = tight_uv_stride,
        .uvPixelStride = 2,
    };
    yuv420_i420_to_nv21(&i420, &converted_nv);
    for (int row = 0; row < height; ++row) {
        for (int column = 0; column < width; ++column) {
            require_equal(
                "i420->nv Y",
                converted_nv.y[row * tight_y_stride + column],
                i420.y[row * y_row_stride + column * y_pixel_stride],
                row,
                column
            );
        }
    }

    YUVDef converted_i420 = {
        .y = checked_alloc((size_t)height * y_row_stride),
        .u = checked_alloc((size_t)chroma_height * i420_uv_row_stride),
        .v = checked_alloc((size_t)chroma_height * i420_uv_row_stride),
        .width = width,
        .height = height,
        .yRowStride = y_row_stride,
        .yPixelStride = y_pixel_stride,
        .uvRowStride = i420_uv_row_stride,
        .uvPixelStride = uv_pixel_stride,
    };
    nv21_to_i420(&nv, &converted_i420);
    require_padding_canary("converted i420.y", converted_i420.y, height, y_row_stride, width, y_pixel_stride, 1);
    require_padding_canary(
        "converted i420.u",
        converted_i420.u,
        chroma_height,
        i420_uv_row_stride,
        chroma_width,
        uv_pixel_stride,
        1
    );
    require_padding_canary(
        "converted i420.v",
        converted_i420.v,
        chroma_height,
        i420_uv_row_stride,
        chroma_width,
        uv_pixel_stride,
        1
    );

    uint8_t *swapped = checked_alloc((size_t)chroma_height * nv_uv_row_stride);
    nvXX_to_nvYY(nv.u, swapped, width, height, nv_uv_row_stride);
    require_padding_canary("swapped uv", swapped, chroma_height, nv_uv_row_stride, chroma_width, 2, 2);
    for (int row = 0; row < chroma_height; ++row) {
        for (int column = 0; column < chroma_width; ++column) {
            const int offset = row * nv_uv_row_stride + column * 2;
            require_equal("swapped first", swapped[offset], nv.u[offset + 1], row, column);
            require_equal("swapped second", swapped[offset + 1], nv.u[offset], row, column);
        }
    }

    free(swapped);
    free(converted_i420.v);
    free(converted_i420.u);
    free(converted_i420.y);
    free(converted_nv.u);
    free(converted_nv.y);
    free(nv.u);
    free(nv.y);
    free(i420.v);
    free(i420.u);
    free(i420.y);
    free(rgba);
}

int main(void) {
    run_size(1, 1);
    run_size(3, 5);
    run_size(127, 255);
    puts("YUV-05 ASan harness passed: 3 sizes, 5 conversion paths.");
    return 0;
}
