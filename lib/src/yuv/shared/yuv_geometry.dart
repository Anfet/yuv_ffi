import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// Shared geometry and plane-layout validation for every backend.
///
/// Both the native (`io`) and the Web (`wasm`) implementations run these checks
/// before any FFI/WASM call, so the two backends accept and reject exactly the
/// same geometry. Native code walks planes using `width`, `height` and the
/// declared strides rather than the Dart buffer length, so a plane that is too
/// small for its declared geometry would be read and written out of bounds.
///
/// Every failure throws [ArgumentError] before any native allocation happens.
abstract final class YuvGeometry {
  /// Number of planes required by [format].
  // ignore: deprecated_member_use_from_same_package
  static int planeCountFor(YuvFileFormat format) => switch (format) {
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.bgra8888 => 1,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.nv21 => 2,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.i420 => 3,
  };

  /// Bytes per sample in the luma/packed plane of [format].
  // ignore: deprecated_member_use_from_same_package
  static int _lumaSampleBytes(YuvFileFormat format) => format == YuvFileFormat.bgra8888 ? 4 : 1;

  /// Chroma plane height for [height] rows, rounded up for odd sizes.
  ///
  /// Odd dimensions keep the trailing half-row, matching the `ceil` allocation
  /// used by the image constructors.
  static int chromaHeight(int height) => (height + 1) ~/ 2;

  /// Chroma plane width in samples for [width] columns, rounded up.
  static int chromaWidth(int width) => (width + 1) ~/ 2;

  /// Validates image dimensions.
  ///
  /// Throws [ArgumentError] when [width] or [height] is not positive.
  static void validateDimensions(int width, int height) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Image width must be greater than zero');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'Image height must be greater than zero');
    }
  }

  /// Pixel stride required by an interleaved NV chroma plane.
  ///
  /// The native converters address an NV chroma sample as a packed `(U, V)`
  /// pair at `index * 2`, so any other stride would be read and written at the
  /// wrong offsets.
  static const int nvChromaPixelStride = 2;

  /// Validates a full image description before it reaches native code.
  ///
  /// [planes] must already be in format order: `[Y]` for BGRA8888, `[Y, UV]`
  /// for NV, and `[Y, U, V]` for I420.
  ///
  /// [allowLargerNvChromaStride] relaxes the interleaved-chroma check from
  /// "exactly [nvChromaPixelStride]" to "at least [nvChromaPixelStride]".
  /// Native code (`validated_view.c`/`yuv_kernel_v1.c`) already addresses every
  /// sample through its declared `rowStride`/`pixelStride` generically and only
  /// enforces a *minimum* pixel stride, so a larger explicit stride is real,
  /// native-supported padding (design doc section 11: "Positive larger pixel/row
  /// strides are supported"), not a layout native code cannot express. This
  /// defaults to `false` so the legacy `nv21` entry points keep their 0.3.0
  /// exact-two behavior unchanged; only the truthfully named `nv12` construction
  /// path opts into the relaxed check (REL-03).
  ///
  /// Throws [ArgumentError] when the geometry is inconsistent.
  static void validateImage({
    // ignore: deprecated_member_use_from_same_package
    required YuvFileFormat format,
    required int width,
    required int height,
    required List<YuvPlane> planes,
    bool allowLargerNvChromaStride = false,
  }) {
    validateDimensions(width, height);

    final expectedPlanes = planeCountFor(format);
    if (planes.length != expectedPlanes) {
      throw ArgumentError.value(planes.length, 'planes.length', 'Format ${format.name} requires exactly $expectedPlanes plane(s)');
    }

    validatePlane(plane: planes[0], label: 'yPlane', expectedHeight: height, expectedWidth: width, sampleBytes: _lumaSampleBytes(format));

    // ignore: deprecated_member_use_from_same_package
    if (format == YuvFileFormat.bgra8888) {
      return;
    }

    final uvHeight = chromaHeight(height);
    final uvWidth = chromaWidth(width);

    // NV keeps one interleaved chroma plane; I420 keeps two planar ones. An
    // interleaved NV row holds a (U, V) pair per chroma sample, so its last
    // sample needs one extra byte beyond the luma-style minimum.
    // ignore: deprecated_member_use_from_same_package
    if (format == YuvFileFormat.nv21) {
      // The converters index chroma as a packed pair, so a stride below two
      // cannot hold it and is always rejected. A stride above two is a pixel
      // gap -- real padding a generic stride-aware kernel supports -- but the
      // legacy nv21 entry points keep rejecting it unless the caller opted into
      // the relaxed nv12 check above.
      final bool valid = allowLargerNvChromaStride ? planes[1].pixelStride >= nvChromaPixelStride : planes[1].pixelStride == nvChromaPixelStride;
      if (!valid) {
        throw ArgumentError.value(
          planes[1].pixelStride,
          'uvPlane.pixelStride',
          allowLargerNvChromaStride
              ? 'Interleaved NV chroma requires a pixel stride of at least $nvChromaPixelStride'
              : 'Interleaved NV chroma requires a pixel stride of exactly $nvChromaPixelStride',
        );
      }
      validatePlane(plane: planes[1], label: 'uvPlane', expectedHeight: uvHeight, expectedWidth: uvWidth, sampleBytes: nvChromaPixelStride);
      return;
    }

    validatePlane(plane: planes[1], label: 'uPlane', expectedHeight: uvHeight, expectedWidth: uvWidth, sampleBytes: 1);
    validatePlane(plane: planes[2], label: 'vPlane', expectedHeight: uvHeight, expectedWidth: uvWidth, sampleBytes: 1);

    // I420 chroma planes are addressed with a shared uvRowStride and
    // uvPixelStride in the native struct, so a mismatch between U and V would
    // make one of them be walked with the other's geometry.
    if (planes[1].rowStride != planes[2].rowStride || planes[1].pixelStride != planes[2].pixelStride) {
      throw ArgumentError.value(
        '${planes[2].rowStride}/${planes[2].pixelStride}',
        'vPlane',
        'I420 U and V planes must share the same rowStride and pixelStride '
            '(U is ${planes[1].rowStride}/${planes[1].pixelStride})',
      );
    }
  }

  /// Geometry a plane must declare to belong to this image, or `null` when
  /// [planeIndex] is not a plane of [format].
  ///
  /// Returns the expected row count and the smallest legal row stride, both
  /// derived from [format], [width] and [height] alone. A decoder can therefore
  /// judge a plane from its metadata, before buffering the bytes that metadata
  /// describes.
  static ({int height, int minRowStride})? expectedPlaneMetadata({
    // ignore: deprecated_member_use_from_same_package
    required YuvFileFormat format,
    required int width,
    required int height,
    required int planeIndex,
    required int pixelStride,
  }) {
    if (planeIndex < 0 || planeIndex >= planeCountFor(format) || pixelStride <= 0) {
      return null;
    }
    if (planeIndex == 0) {
      return (height: height, minRowStride: (width - 1) * pixelStride + _lumaSampleBytes(format));
    }
    // ignore: deprecated_member_use_from_same_package
    final sampleBytes = format == YuvFileFormat.nv21 ? nvChromaPixelStride : 1;
    return (height: chromaHeight(height), minRowStride: (chromaWidth(width) - 1) * pixelStride + sampleBytes);
  }

  /// Whether a BGRA plane is tightly packed for [width].
  ///
  /// Several native effects allocate a tight temporary buffer while addressing
  /// the source through its row stride, so a padded plane has to be repacked
  /// before such an operation instead of being passed through.
  static bool isTightBgra(YuvPlane plane, int width) => plane.rowStride == width * 4 && plane.pixelStride == 4;

  /// Validates a single plane against its expected geometry.
  ///
  /// [sampleBytes] is the number of bytes the native code reads at the last
  /// sample of a row, so the minimum row length accounts for the final sample
  /// rather than only the stride steps between samples.
  ///
  /// Throws [ArgumentError] when the plane cannot hold the declared geometry.
  static void validatePlane({
    required YuvPlane plane,
    required String label,
    required int expectedHeight,
    required int expectedWidth,
    required int sampleBytes,
  }) {
    if (plane.pixelStride <= 0) {
      throw ArgumentError.value(plane.pixelStride, '$label.pixelStride', 'Pixel stride must be greater than zero');
    }
    if (plane.rowStride <= 0) {
      throw ArgumentError.value(plane.rowStride, '$label.rowStride', 'Row stride must be greater than zero');
    }
    if (plane.height != expectedHeight) {
      throw ArgumentError.value(plane.height, '$label.height', 'Expected $expectedHeight rows for this image geometry');
    }

    // Last sample starts at (expectedWidth - 1) * pixelStride and occupies
    // sampleBytes bytes, so the row must be at least that long.
    final minRowStride = (expectedWidth - 1) * plane.pixelStride + sampleBytes;
    if (plane.rowStride < minRowStride) {
      throw ArgumentError.value(
        plane.rowStride,
        '$label.rowStride',
        'Row stride must be at least $minRowStride bytes for width $expectedWidth '
            '(pixelStride ${plane.pixelStride}, $sampleBytes byte(s) per sample)',
      );
    }

    final expectedLength = plane.height * plane.rowStride;
    if (plane.bytes.length != expectedLength) {
      throw ArgumentError.value(
        plane.bytes.length,
        '$label.bytes.length',
        'Expected exactly $expectedLength bytes (height ${plane.height} * rowStride ${plane.rowStride})',
      );
    }
  }

  /// Largest `radius` a box/mean/gaussian blur accepts.
  ///
  /// Matches the `1..256` bound documented for the native ABI in
  /// `doc/api-abi-0.4-design.md`. Native blur builds a SAT-style summed-area
  /// table and computes plane-wide row/column pad weights from `radius`; an
  /// unvalidated negative or absurdly large radius produces inverted SAT
  /// bounds and an out-of-bounds native read/write rather than a clean
  /// rejection.
  static const int maxBlurRadius = 256;

  /// Validates a blur `radius` before it reaches native code.
  ///
  /// `radius == 0` is the documented no-op and is accepted here; callers
  /// short-circuit on it before doing any allocation or native call. Throws
  /// [ArgumentError] for a negative radius or one above [maxBlurRadius].
  static void validateBlurRadius(int radius) {
    if (radius < 0 || radius > maxBlurRadius) {
      throw ArgumentError.value(radius, 'radius', 'Radius must be 0 (no-op) or between 1 and $maxBlurRadius');
    }
  }
}
