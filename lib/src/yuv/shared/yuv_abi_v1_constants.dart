/// Mirrors of the native ABI v1 numeric constants
/// (`src/yuv/abi/h/yuv_abi_v1.h`, `doc/api-abi-0.4-design.md` section 9).
///
/// This file is hand-kept in sync with the C header rather than generated,
/// because ffigen does not emit `#define` numeric macros as Dart constants --
/// only the struct/function declarations that reference them. The
/// `abi_symbol_manifest` coverage planned for YUV-36e is the intended guard
/// against the two drifting; until it lands, a change to these values in the
/// header must be mirrored here by hand.
library;

/// The only ABI version the typed IO runner negotiates.
const int yuvAbiVersion1 = 1;

/// Planar YUV 4:2:0, three planes (Y, U, V), `sampleBytes` 1 for every plane.
const int yuvFormatI420 = 1;

/// Semi-planar YUV 4:2:0, two planes (Y, interleaved UV),
/// `sampleBytes` 1 for Y and 2 for UV.
///
/// This is the canonical ABI v1 storage; the project's legacy `nv21` label
/// keeps its historical `(U, V)` byte order under this same numeric format
/// id (Engineer decision Q1, `doc/api-abi-0.4-design.md` section 14) -- ABI
/// v1 does not define a separate NV21 format value.
const int yuvFormatNv12 = 2;

/// Packed BGRA, one plane, `sampleBytes` 4.
const int yuvFormatBgra8888 = 3;

/// Packed RGBA, one plane, `sampleBytes` 4. Valid only as a
/// `yuv_convert_v1` source; ABI v1 does not publish it as a destination.
const int yuvFormatRgba8888 = 4;

/// No declared color matrix; required for BGRA/RGBA frames.
const int yuvColorMatrixNone = 0;

/// BT.601 matrix; required for I420/NV12 frames.
const int yuvColorMatrixBt601 = 1;

/// No declared color range; required for BGRA/RGBA frames.
const int yuvColorRangeNone = 0;

/// Limited range; required for I420/NV12 frames.
const int yuvColorRangeLimited = 1;

/// The only border mode ABI v1 defines for blur.
const int yuvBorderClamp = 1;

/// `YuvFlipOptionsV1.direction`: mirror left-right.
const int yuvFlipHorizontal = 1;

/// `YuvFlipOptionsV1.direction`: mirror top-bottom.
const int yuvFlipVertical = 2;

/// Number of planes [format] requires (`yuv_validated_view_plane_count` in
/// `src/yuv/utils/validated_view.c`), or `0` for an unknown format id.
int yuvAbiV1PlaneCount(int format) {
  switch (format) {
    case yuvFormatI420:
      return 3;
    case yuvFormatNv12:
      return 2;
    case yuvFormatBgra8888:
    case yuvFormatRgba8888:
      return 1;
    default:
      return 0;
  }
}

/// `sampleBytes` for plane [planeIndex] of [format]
/// (`yuv_validated_view_plane_sample_layout` in
/// `src/yuv/utils/validated_view.c`, section 11's format matrix): 1 for every
/// I420 plane, 1 for NV12's Y and 2 for its interleaved UV, 4 for the single
/// BGRA/RGBA plane.
///
/// Throws [RangeError] for a [planeIndex] outside `0..yuvAbiV1PlaneCount(format)`
/// or an unknown [format] -- the runner only calls this after both have
/// already been validated against a known format, so this is a programming
/// error in the runner itself, not a caller-facing native status.
int yuvAbiV1SampleBytes(int format, int planeIndex) {
  final int planeCount = yuvAbiV1PlaneCount(format);
  if (planeCount == 0 || planeIndex < 0 || planeIndex >= planeCount) {
    throw RangeError.value(planeIndex, 'planeIndex', 'Not a valid plane index for format $format');
  }
  switch (format) {
    case yuvFormatI420:
      return 1;
    case yuvFormatNv12:
      return planeIndex == 0 ? 1 : 2;
    case yuvFormatBgra8888:
    case yuvFormatRgba8888:
      return 4;
    default:
      throw StateError('unreachable: planeCount already rejected format $format');
  }
}

/// The `colorMatrix` value ABI v1 requires for [format]
/// (`yuv_validate_v1_color` in `src/yuv/abi/yuv_validate_v1.c`, section 9):
/// BT.601 for I420/NV12, none for BGRA/RGBA. Throws [ArgumentError] for an
/// unknown format.
int yuvAbiV1ColorMatrixFor(int format) {
  switch (format) {
    case yuvFormatI420:
    case yuvFormatNv12:
      return yuvColorMatrixBt601;
    case yuvFormatBgra8888:
    case yuvFormatRgba8888:
      return yuvColorMatrixNone;
    default:
      throw ArgumentError.value(format, 'format', 'Unknown ABI v1 format id');
  }
}

/// The `colorRange` value ABI v1 requires for [format], mirroring
/// [yuvAbiV1ColorMatrixFor]: limited for I420/NV12, none for BGRA/RGBA.
int yuvAbiV1ColorRangeFor(int format) {
  switch (format) {
    case yuvFormatI420:
    case yuvFormatNv12:
      return yuvColorRangeLimited;
    case yuvFormatBgra8888:
    case yuvFormatRgba8888:
      return yuvColorRangeNone;
    default:
      throw ArgumentError.value(format, 'format', 'Unknown ABI v1 format id');
  }
}

/// Logical chroma width for a 4:2:0 plane: `ceil(width / 2)`.
///
/// Mirrors `yuv_checked_ceil_half` in `src/yuv/utils/checked_arithmetic.c`.
/// Dart integers do not overflow the way the C helper guards against, so this
/// is the direct formula rather than a checked variant.
int yuvAbiV1ChromaExtent(int extent) => (extent + 1) ~/ 2;
