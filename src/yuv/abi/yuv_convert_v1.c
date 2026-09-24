#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"
#include "h/yuv_kernel_v1.h"

/*
 * Conversion across the RGBA/BGRA/I420/NV12 matrix at identical geometry.
 *
 * RGBA8888 appears only on the source side: it is an accepted input encoding,
 * but 0.4.0 does not publish it as an output. A same-format pair is legal and
 * means a stride-aware deep copy, which is why the source/destination overlap
 * check in the shared prologue matters most here.
 */
typedef struct {
    const YuvValidatedConstFrameView *source;
} YuvConvertContextV1;

static YuvRgbaPixelV1 yuv_convert_v1_produce(void *context, uint32_t x, uint32_t y) {
    const YuvConvertContextV1 *convert = (const YuvConvertContextV1 *)context;
    return yuv_kernel_v1_read_pixel(convert->source, x, y);
}

/* Identity map for the same-format deep copy. */
static void yuv_convert_v1_identity(
    void *context, uint32_t destinationX, uint32_t destinationY, uint32_t *outSourceX, uint32_t *outSourceY) {
    (void)context;
    *outSourceX = destinationX;
    *outSourceY = destinationY;
}

/*
 * True for the I420 <-> NV12 pair, the one cross-format conversion that stores
 * exactly the same samples in a different layout.
 */
static int yuv_convert_v1_is_relayout(uint32_t sourceFormat, uint32_t destinationFormat) {
    return (sourceFormat == YUV_VIEW_FORMAT_I420 && destinationFormat == YUV_VIEW_FORMAT_NV12) ||
           (sourceFormat == YUV_VIEW_FORMAT_NV12 && destinationFormat == YUV_VIEW_FORMAT_I420);
}

/*
 * Moves I420 <-> NV12 as stored samples: Y byte for byte, and each chroma
 * sample de-interleaved or interleaved in place.
 *
 * Both formats are BT.601 limited-range 4:2:0 with identical logical sample
 * geometry -- only the chroma *layout* differs (two planar planes versus one
 * interleaved plane). Routing the pair through decode-to-RGB and re-encode
 * would quantize a frame that lost nothing to begin with: it perturbs every Y
 * sample and re-averages chroma that was already at final resolution. The
 * independent reference oracle
 * (tool/reference/generate_test_pattern_references.dart, `i420ToNv21Uv`)
 * defines this conversion as the pure relayout implemented here, and compares
 * it byte-exact.
 *
 * Both views are already validated, so every sample address below is in
 * bounds; active samples move through each descriptor's own strides and no
 * padding byte is read or written.
 */
static void yuv_convert_v1_relayout(
    const YuvValidatedConstFrameView *source, const YuvValidatedMutableFrameView *destination) {
    for (uint32_t y = 0; y < destination->height; y++) {
        for (uint32_t x = 0; x < destination->width; x++) {
            const uint8_t *fromLuma = yuv_kernel_v1_const_sample(&source->planes[0], x, y);
            uint8_t *toLuma = yuv_kernel_v1_mutable_sample(&destination->planes[0], x, y);
            if (fromLuma == NULL || toLuma == NULL) {
                return;
            }
            toLuma[0] = fromLuma[0];
        }
    }

    uint32_t chromaWidth = (destination->width + 1u) / 2u;
    uint32_t chromaHeight = (destination->height + 1u) / 2u;

    for (uint32_t y = 0; y < chromaHeight; y++) {
        for (uint32_t x = 0; x < chromaWidth; x++) {
            uint8_t u;
            uint8_t v;

            if (source->format == YUV_VIEW_FORMAT_I420) {
                const uint8_t *fromU = yuv_kernel_v1_const_sample(&source->planes[1], x, y);
                const uint8_t *fromV = yuv_kernel_v1_const_sample(&source->planes[2], x, y);
                if (fromU == NULL || fromV == NULL) {
                    return;
                }
                u = fromU[0];
                v = fromV[0];
            } else {
                const uint8_t *fromUv = yuv_kernel_v1_const_sample(&source->planes[1], x, y);
                if (fromUv == NULL) {
                    return;
                }
                u = fromUv[0];
                v = fromUv[1];
            }

            if (destination->format == YUV_VIEW_FORMAT_I420) {
                uint8_t *toU = yuv_kernel_v1_mutable_sample(&destination->planes[1], x, y);
                uint8_t *toV = yuv_kernel_v1_mutable_sample(&destination->planes[2], x, y);
                if (toU == NULL || toV == NULL) {
                    return;
                }
                toU[0] = u;
                toV[0] = v;
            } else {
                uint8_t *toUv = yuv_kernel_v1_mutable_sample(&destination->planes[1], x, y);
                if (toUv == NULL) {
                    return;
                }
                toUv[0] = u;
                toUv[1] = v;
            }
        }
    }
}

FFI_PLUGIN_EXPORT YuvStatus yuv_convert_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvConvertOptionsV1 *options) {
    YuvStatus optionsStatus = yuv_validate_v1_options_header(options, (uint32_t)sizeof(YuvConvertOptionsV1));
    if (optionsStatus != YUV_STATUS_OK) {
        return optionsStatus;
    }
    if (options->reserved[0] != 0 || options->reserved[1] != 0 || options->reserved[2] != 0) {
        return YUV_STATUS_INVALID_ARGUMENT;
    }

    YuvValidatedConstFrameView sourceView;
    YuvValidatedMutableFrameView destinationView;
    YuvStatus framesStatus = yuv_validate_v1_frames(
        source, destination, YUV_GEOMETRY_V1_SAME, 0, 0, &sourceView, &destinationView);
    if (framesStatus != YUV_STATUS_OK) {
        return framesStatus;
    }

    /* The full matrix of section 11: each of I420, NV12, BGRA8888, RGBA8888 as
     * a source, into each of I420, NV12, BGRA8888. Convert options carry no
     * format fields of their own precisely so this pair cannot disagree with
     * the descriptors. */
    static const YuvFormatPairV1 convertPairs[12] = {
        {YUV_FORMAT_I420, YUV_FORMAT_I420},
        {YUV_FORMAT_I420, YUV_FORMAT_NV12},
        {YUV_FORMAT_I420, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_NV12, YUV_FORMAT_I420},
        {YUV_FORMAT_NV12, YUV_FORMAT_NV12},
        {YUV_FORMAT_NV12, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_I420},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_NV12},
        {YUV_FORMAT_BGRA8888, YUV_FORMAT_BGRA8888},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_I420},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_NV12},
        {YUV_FORMAT_RGBA8888, YUV_FORMAT_BGRA8888},
    };
    YuvStatus pairStatus =
        yuv_validate_v1_format_pair(sourceView.format, destinationView.format, convertPairs, 12);
    if (pairStatus != YUV_STATUS_OK) {
        return pairStatus;
    }

    /* A same-format pair is a deep copy, and it must stay bit-exact: routing
     * it through decode/re-encode would quantize a frame that the caller only
     * asked to duplicate, and for 4:2:0 would visibly shift chroma. The
     * transform driver already copies stored samples through both descriptors'
     * strides, and an identity map is trivially block aligned. */
    if (sourceView.format == destinationView.format) {
        yuv_kernel_v1_transform(&sourceView, &destinationView, yuv_convert_v1_identity, NULL, 1);
        return YUV_STATUS_OK;
    }

    /* I420 <-> NV12 is a layout change over identical samples, so it takes the
     * same "move stored bytes" treatment as the same-format copy rather than
     * the decode/re-encode path below. */
    if (yuv_convert_v1_is_relayout(sourceView.format, destinationView.format)) {
        yuv_convert_v1_relayout(&sourceView, &destinationView);
        return YUV_STATUS_OK;
    }

    /* Everything else goes through the one visible-pixel path: decode the
     * source to BT.601 limited-range RGB, then let the encode driver apply
     * the destination format's storage rules, including the clipped 2x2
     * chroma average on odd edges. The channel order of the input never
     * selects a different matrix -- that divergence is what YUV-32 exists to
     * remove. */
    YuvConvertContextV1 context;
    context.source = &sourceView;
    yuv_kernel_v1_encode_frame(&destinationView, yuv_convert_v1_produce, &context);

    return YUV_STATUS_OK;
}
