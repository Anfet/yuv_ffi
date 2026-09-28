#ifndef YUV_OPS_V1_H
#define YUV_OPS_V1_H

#include "yuv_abi_v1.h"

/*
 * The eleven exported processing entry points of ABI v1
 * declared by this header.
 *
 * Every operation takes its arguments in the order (source, destination,
 * options) and returns a YuvStatus. There are no variadic, nullable-options,
 * or format-specific overloads. The format matrix is resolved from the frame
 * descriptors, never from the symbol name.
 *
 * Contract shared by all entry points:
 *
 *  - Every descriptor and options pointer is validated BEFORE the first
 *    destination write. After writing starts no fallible step is permitted,
 *    so a non-OK return guarantees the destination is byte-for-byte unchanged
 *    and the caller may safely discard it without rolling anything back.
 *  - The source is const and is never written. Active source and destination
 *    spans must not overlap in ABI v1.
 *  - The destination is caller-owned. These functions allocate no buffer the
 *    caller must free; there is no hidden ownership transfer.
 */

/* Guarded so a translation unit that also picks the macro up from elsewhere
 * does not hit a macro-redefinition warning, which the test harness's /WX
 * turns into a build failure. */
#ifndef FFI_PLUGIN_EXPORT
#ifdef _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif
#endif

/*
 * Conversion across the RGBA/BGRA/I420/NV12 matrix. RGBA8888 is accepted only
 * as a source. A same-format conversion is a stride-aware deep copy, never
 * aliasing. Destination geometry equals source geometry.
 */
FFI_PLUGIN_EXPORT YuvStatus yuv_convert_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvConvertOptionsV1 *options);

/* Visible-pixel effects. I420 to I420, NV12 to NV12, and BGRA to BGRA; destination
 * geometry equals source geometry. */
FFI_PLUGIN_EXPORT YuvStatus yuv_black_white_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_grayscale_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_negate_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options);

/* Blur. Mean and box use uniform weights; Gaussian weights depend on `sigma`.
 * All three replicate edge pixels at image borders. */
FFI_PLUGIN_EXPORT YuvStatus yuv_gaussian_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvBlurOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_mean_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvBlurOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_box_blur_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvBlurOptionsV1 *options);

/* Geometric transforms. Crop takes its destination geometry from the options
 * rectangle; rotation by 90/270 transposes it. */
FFI_PLUGIN_EXPORT YuvStatus yuv_crop_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvCropOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_flip_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvFlipOptionsV1 *options);
FFI_PLUGIN_EXPORT YuvStatus yuv_rotate_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvRotateOptionsV1 *options);

/* Swaps U and V sample values without changing the NV12 format. The operation
 * accepts NV12 frames only and requires the effect region to be disabled. */
FFI_PLUGIN_EXPORT YuvStatus yuv_chroma_swap_v1(const YuvConstFrameV1 *source, YuvMutableFrameV1 *destination,
    const YuvEffectOptionsV1 *options);

#endif  /* YUV_OPS_V1_H */
