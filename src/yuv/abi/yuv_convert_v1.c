#include "h/yuv_ops_v1.h"
#include "h/yuv_validate_v1.h"

/*
 * Conversion across the RGBA/BGRA/I420/NV12 matrix at identical geometry.
 *
 * RGBA8888 appears only on the source side: it is an accepted input encoding,
 * but 0.3.0 does not publish it as an output. A same-format pair is legal and
 * means a stride-aware deep copy, which is why the source/destination overlap
 * check in the shared prologue matters most here.
 */
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

    /* Validation is complete and both descriptors are sound, but the conversion kernel
     * has not landed yet -- YUV-32 owns it. Returning INTERNAL_ERROR without
     * writing a single destination byte keeps the atomicity contract honest in
     * the meantime: a caller sees a clean failure, never a half-written frame.
     *
     * Replace this with the real kernel -- never with a bare YUV_STATUS_OK,
     * which would report success for an untouched frame.
     */
    return YUV_STATUS_INTERNAL_ERROR;
}
