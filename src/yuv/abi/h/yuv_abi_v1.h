#ifndef YUV_ABI_V1_H
#define YUV_ABI_V1_H

#include <stdint.h>
#include <stddef.h>

/*
 * Public wire-stable native ABI v1 for yuv_ffi 0.3.0.
 *
 * This header is the single source of truth for the descriptor, options, and
 * status types described in docs/api-abi-0.3-design.md sections 9 and 10.
 * Values and member order are copied from that document literally; this file
 * does not invent an alternative contract.
 *
 * Scope note (YUV-36a): this header declares TYPES ONLY. The eleven
 * `yuv_*_v1` entry points of section 11 are declared and implemented by
 * YUV-36b in src/yuv/abi/h/yuv_ops_v1.h; nothing here is an exported symbol,
 * so including this header adds no ABI surface on its own.
 *
 * The internal validation logic that consumes these types lives in
 * src/yuv/utils/h/validated_view.h (YUV-33c). That header deliberately
 * declares its own view structs rather than these, so that validation could
 * land before the public ABI. The two layouts are member-compatible by
 * construction; YUV-36b builds the views from these structs.
 */

/* ===========================================================================
 * Status (section 9)
 *
 * A fixed-width integer, never a compiler-sized C enum: the value crosses the
 * native/wasm boundary and is read back by Dart as a 32-bit integer.
 * =========================================================================== */

typedef int32_t YuvStatus;

#define YUV_STATUS_OK                 ((YuvStatus)0)
#define YUV_STATUS_INVALID_ARGUMENT   ((YuvStatus)1)
#define YUV_STATUS_UNSUPPORTED_FORMAT ((YuvStatus)2)
#define YUV_STATUS_UNSUPPORTED_LAYOUT ((YuvStatus)3)
#define YUV_STATUS_OVERFLOW           ((YuvStatus)4)
#define YUV_STATUS_ALLOCATION_FAILED  ((YuvStatus)5)
#define YUV_STATUS_INTERNAL_ERROR     ((YuvStatus)6)
#define YUV_STATUS_UNSUPPORTED_COLOR  ((YuvStatus)7)

/* ===========================================================================
 * Numeric contract constants (section 9)
 * =========================================================================== */

/* The only ABI version accepted by v1 entry points. */
#define YUV_ABI_VERSION_1 ((uint32_t)1)

#define YUV_FORMAT_I420     ((uint32_t)1)
#define YUV_FORMAT_NV12     ((uint32_t)2)
#define YUV_FORMAT_BGRA8888 ((uint32_t)3)
#define YUV_FORMAT_RGBA8888 ((uint32_t)4)

#define YUV_COLOR_MATRIX_NONE   ((uint32_t)0)
#define YUV_COLOR_MATRIX_BT601  ((uint32_t)1)
#define YUV_COLOR_RANGE_NONE    ((uint32_t)0)
#define YUV_COLOR_RANGE_LIMITED ((uint32_t)1)

#define YUV_BORDER_CLAMP ((uint32_t)1)

#define YUV_FLIP_HORIZONTAL ((uint32_t)1)
#define YUV_FLIP_VERTICAL   ((uint32_t)2)

/* ===========================================================================
 * Frame and plane descriptors (section 9)
 * =========================================================================== */

typedef struct {
    uint64_t length;
    uint64_t rowStride;
    uint32_t pixelStride;
    uint32_t sampleBytes;
    const uint8_t *data;
} YuvConstPlaneV1;

typedef struct {
    uint64_t length;
    uint64_t rowStride;
    uint32_t pixelStride;
    uint32_t sampleBytes;
    uint8_t *data;
} YuvMutablePlaneV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint32_t format;
    uint32_t planeCount;
    uint32_t width;
    uint32_t height;
    uint32_t colorMatrix;
    uint32_t colorRange;
    YuvConstPlaneV1 planes[3];
    uint64_t reserved[4];
} YuvConstFrameV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint32_t format;
    uint32_t planeCount;
    uint32_t width;
    uint32_t height;
    uint32_t colorMatrix;
    uint32_t colorRange;
    YuvMutablePlaneV1 planes[3];
    uint64_t reserved[4];
} YuvMutableFrameV1;

/* ===========================================================================
 * Options (section 10)
 *
 * Each options struct is a distinct fixed-width type. Positional scalar tails
 * are not permitted, so an added field is a new struct size negotiated through
 * `structSize`, never a reinterpreted trailing argument.
 * =========================================================================== */

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
    uint32_t enabled;
    uint32_t reserved0;
} YuvRegionOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint32_t radius;
    uint32_t borderMode;
    double sigma;
    YuvRegionOptionsV1 region;
    uint64_t reserved[2];
} YuvBlurOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    YuvRegionOptionsV1 region;
    uint64_t reserved[2];
} YuvEffectOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint64_t reserved[3];
} YuvConvertOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    int32_t left;
    int32_t top;
    uint32_t width;
    uint32_t height;
    uint64_t reserved[1];
} YuvCropOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint32_t direction;
    uint32_t reserved0;
    uint64_t reserved[2];
} YuvFlipOptionsV1;

typedef struct {
    uint32_t structSize;
    uint32_t abiVersion;
    uint32_t rotationDegrees;
    uint32_t reserved0;
    uint64_t reserved[2];
} YuvRotateOptionsV1;

/* ===========================================================================
 * Layout assertions
 *
 * Every row of the two offset tables in sections 9 and 10 is asserted here.
 * The design document calls this "a required build assertion, not an
 * assumption": a target whose layout differs must fail to compile rather than
 * silently exchange misaligned descriptors with Dart or with a WASM module.
 *
 * The assertion is a negative-array typedef rather than `static_assert`,
 * because this header must hold under C99 without <assert.h>, and because an
 * `assert()`-based check would vanish under NDEBUG in exactly the release
 * builds that ship.
 *
 * Every plane `data` member is asserted against `sizeof(void *)` rather than
 * a literal 8: the whole point of the v1 layout is that it is identical on
 * native64, native32, and wasm32, and the pointer is the one member whose
 * width legitimately differs between them.
 * =========================================================================== */

#define YUV_ABI_STATIC_ASSERT(condition, name) \
    typedef char yuv_abi_static_assert_##name[(condition) ? 1 : -1]

/* --- Plane descriptors: identical layout for const and mutable. --- */

YUV_ABI_STATIC_ASSERT(offsetof(YuvConstPlaneV1, length) == 0, const_plane_length);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstPlaneV1, rowStride) == 8, const_plane_row_stride);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstPlaneV1, pixelStride) == 16, const_plane_pixel_stride);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstPlaneV1, sampleBytes) == 20, const_plane_sample_bytes);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstPlaneV1, data) == 24, const_plane_data);
YUV_ABI_STATIC_ASSERT(sizeof(((YuvConstPlaneV1 *)0)->data) == sizeof(void *), const_plane_data_width);
YUV_ABI_STATIC_ASSERT(sizeof(YuvConstPlaneV1) == 32, const_plane_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvMutablePlaneV1, length) == 0, mutable_plane_length);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutablePlaneV1, rowStride) == 8, mutable_plane_row_stride);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutablePlaneV1, pixelStride) == 16, mutable_plane_pixel_stride);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutablePlaneV1, sampleBytes) == 20, mutable_plane_sample_bytes);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutablePlaneV1, data) == 24, mutable_plane_data);
YUV_ABI_STATIC_ASSERT(sizeof(((YuvMutablePlaneV1 *)0)->data) == sizeof(void *), mutable_plane_data_width);
YUV_ABI_STATIC_ASSERT(sizeof(YuvMutablePlaneV1) == 32, mutable_plane_size);

/* --- Frame descriptors: 32-byte scalar prefix, three planes, reserved tail. --- */

YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, structSize) == 0, const_frame_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, abiVersion) == 4, const_frame_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, format) == 8, const_frame_format);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, planeCount) == 12, const_frame_plane_count);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, width) == 16, const_frame_width);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, height) == 20, const_frame_height);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, colorMatrix) == 24, const_frame_color_matrix);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, colorRange) == 28, const_frame_color_range);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, planes) == 32, const_frame_planes);
/* planes[1] and planes[2] are asserted through the element size rather than
 * offsetof(..., planes[1]): MSVC does not accept offsetof on a nested array
 * element as a constant expression (C2057). Element size times index is the
 * same guarantee -- the array is contiguous by definition -- and it holds on
 * every toolchain. */
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, planes) + sizeof(YuvConstPlaneV1) == 64, const_frame_planes_1);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, planes) + 2 * sizeof(YuvConstPlaneV1) == 96, const_frame_planes_2);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConstFrameV1, reserved) == 128, const_frame_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvConstFrameV1) == 160, const_frame_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, structSize) == 0, mutable_frame_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, abiVersion) == 4, mutable_frame_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, format) == 8, mutable_frame_format);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, planeCount) == 12, mutable_frame_plane_count);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, width) == 16, mutable_frame_width);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, height) == 20, mutable_frame_height);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, colorMatrix) == 24, mutable_frame_color_matrix);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, colorRange) == 28, mutable_frame_color_range);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, planes) == 32, mutable_frame_planes);
/* planes[1] and planes[2] are asserted through the element size rather than
 * offsetof(..., planes[1]): MSVC does not accept offsetof on a nested array
 * element as a constant expression (C2057). Element size times index is the
 * same guarantee -- the array is contiguous by definition -- and it holds on
 * every toolchain. */
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, planes) + sizeof(YuvMutablePlaneV1) == 64, mutable_frame_planes_1);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, planes) + 2 * sizeof(YuvMutablePlaneV1) == 96, mutable_frame_planes_2);
YUV_ABI_STATIC_ASSERT(offsetof(YuvMutableFrameV1, reserved) == 128, mutable_frame_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvMutableFrameV1) == 160, mutable_frame_size);

/* --- Alignment. The frame/plane descriptors carry uint64_t members, so the
 * whole v1 layout depends on uint64_t being 8-byte aligned; a target that
 * aligns it to 4 would pack every table above differently. --- */

/* The probes are named types rather than anonymous structs written inline in
 * offsetof(): MSVC reports C4116 for an unnamed type definition in parentheses,
 * and the test harness compiles with /W4 /WX. */
typedef struct { char c; uint64_t v; } YuvAbiUint64AlignProbe;
typedef struct { char c; double v; } YuvAbiDoubleAlignProbe;

YUV_ABI_STATIC_ASSERT(sizeof(uint64_t) == 8, uint64_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiUint64AlignProbe, v) == 8, uint64_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiDoubleAlignProbe, v) == 8, double_alignment);

/* --- Options (section 10). --- */

YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, structSize) == 0, region_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, abiVersion) == 4, region_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, left) == 8, region_left);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, top) == 12, region_top);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, right) == 16, region_right);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, bottom) == 20, region_bottom);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, enabled) == 24, region_enabled);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRegionOptionsV1, reserved0) == 28, region_reserved0);
YUV_ABI_STATIC_ASSERT(sizeof(YuvRegionOptionsV1) == 32, region_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, structSize) == 0, blur_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, abiVersion) == 4, blur_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, radius) == 8, blur_radius);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, borderMode) == 12, blur_border_mode);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, sigma) == 16, blur_sigma);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, region) == 24, blur_region);
YUV_ABI_STATIC_ASSERT(offsetof(YuvBlurOptionsV1, reserved) == 56, blur_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvBlurOptionsV1) == 72, blur_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvEffectOptionsV1, structSize) == 0, effect_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvEffectOptionsV1, abiVersion) == 4, effect_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvEffectOptionsV1, region) == 8, effect_region);
YUV_ABI_STATIC_ASSERT(offsetof(YuvEffectOptionsV1, reserved) == 40, effect_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvEffectOptionsV1) == 56, effect_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvConvertOptionsV1, structSize) == 0, convert_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConvertOptionsV1, abiVersion) == 4, convert_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvConvertOptionsV1, reserved) == 8, convert_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvConvertOptionsV1) == 32, convert_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, structSize) == 0, crop_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, abiVersion) == 4, crop_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, left) == 8, crop_left);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, top) == 12, crop_top);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, width) == 16, crop_width);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, height) == 20, crop_height);
YUV_ABI_STATIC_ASSERT(offsetof(YuvCropOptionsV1, reserved) == 24, crop_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvCropOptionsV1) == 32, crop_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvFlipOptionsV1, structSize) == 0, flip_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvFlipOptionsV1, abiVersion) == 4, flip_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvFlipOptionsV1, direction) == 8, flip_direction);
YUV_ABI_STATIC_ASSERT(offsetof(YuvFlipOptionsV1, reserved0) == 12, flip_reserved0);
YUV_ABI_STATIC_ASSERT(offsetof(YuvFlipOptionsV1, reserved) == 16, flip_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvFlipOptionsV1) == 32, flip_size);

YUV_ABI_STATIC_ASSERT(offsetof(YuvRotateOptionsV1, structSize) == 0, rotate_struct_size);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRotateOptionsV1, abiVersion) == 4, rotate_abi_version);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRotateOptionsV1, rotationDegrees) == 8, rotate_rotation_degrees);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRotateOptionsV1, reserved0) == 12, rotate_reserved0);
YUV_ABI_STATIC_ASSERT(offsetof(YuvRotateOptionsV1, reserved) == 16, rotate_reserved);
YUV_ABI_STATIC_ASSERT(sizeof(YuvRotateOptionsV1) == 32, rotate_size);

/* --- Per-struct alignment (section 10: "sizeof, alignment, and offsetof
 * compile assertions are required"). Size and offsets alone do not pin
 * alignment down: a type can have the right layout internally and still be
 * placed differently when embedded in another struct or in an array, which is
 * exactly what YuvRegionOptionsV1 does inside the blur and effect options.
 *
 * Alignment is measured with the same named-probe trick used above, because
 * C99 has no _Alignof: the offset of a member placed after a single char is
 * that member's alignment requirement. */

typedef struct { char c; YuvRegionOptionsV1 v; } YuvAbiRegionAlignProbe;
typedef struct { char c; YuvBlurOptionsV1 v; } YuvAbiBlurAlignProbe;
typedef struct { char c; YuvEffectOptionsV1 v; } YuvAbiEffectAlignProbe;
typedef struct { char c; YuvConvertOptionsV1 v; } YuvAbiConvertAlignProbe;
typedef struct { char c; YuvCropOptionsV1 v; } YuvAbiCropAlignProbe;
typedef struct { char c; YuvFlipOptionsV1 v; } YuvAbiFlipAlignProbe;
typedef struct { char c; YuvRotateOptionsV1 v; } YuvAbiRotateAlignProbe;
typedef struct { char c; YuvConstPlaneV1 v; } YuvAbiConstPlaneAlignProbe;
typedef struct { char c; YuvMutablePlaneV1 v; } YuvAbiMutablePlaneAlignProbe;
typedef struct { char c; YuvConstFrameV1 v; } YuvAbiConstFrameAlignProbe;
typedef struct { char c; YuvMutableFrameV1 v; } YuvAbiMutableFrameAlignProbe;

/* Region is all-32-bit and therefore 4-byte aligned; every struct carrying a
 * double or a uint64_t is 8-byte aligned. */
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiRegionAlignProbe, v) == 4, region_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiBlurAlignProbe, v) == 8, blur_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiEffectAlignProbe, v) == 8, effect_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiConvertAlignProbe, v) == 8, convert_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiCropAlignProbe, v) == 8, crop_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiFlipAlignProbe, v) == 8, flip_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiRotateAlignProbe, v) == 8, rotate_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiConstPlaneAlignProbe, v) == 8, const_plane_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiMutablePlaneAlignProbe, v) == 8, mutable_plane_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiConstFrameAlignProbe, v) == 8, const_frame_alignment);
YUV_ABI_STATIC_ASSERT(offsetof(YuvAbiMutableFrameAlignProbe, v) == 8, mutable_frame_alignment);

#endif  /* YUV_ABI_V1_H */
