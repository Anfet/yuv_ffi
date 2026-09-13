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
  static int planeCountFor(YuvFileFormat format) => switch (format) {
        YuvFileFormat.bgra8888 => 1,
        YuvFileFormat.nv21 => 2,
        YuvFileFormat.i420 => 3,
      };

  /// Bytes per sample in the luma/packed plane of [format].
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

  /// Validates a full image description before it reaches native code.
  ///
  /// [planes] must already be in format order: `[Y]` for BGRA8888, `[Y, UV]`
  /// for NV, and `[Y, U, V]` for I420.
  ///
  /// Throws [ArgumentError] when the geometry is inconsistent.
  static void validateImage({
    required YuvFileFormat format,
    required int width,
    required int height,
    required List<YuvPlane> planes,
  }) {
    validateDimensions(width, height);

    final expectedPlanes = planeCountFor(format);
    if (planes.length != expectedPlanes) {
      throw ArgumentError.value(
        planes.length,
        'planes.length',
        'Format ${format.name} requires exactly $expectedPlanes plane(s)',
      );
    }

    validatePlane(
      plane: planes[0],
      label: 'yPlane',
      expectedHeight: height,
      expectedWidth: width,
      sampleBytes: _lumaSampleBytes(format),
    );

    if (format == YuvFileFormat.bgra8888) {
      return;
    }

    final uvHeight = chromaHeight(height);
    final uvWidth = chromaWidth(width);

    // NV keeps one interleaved chroma plane; I420 keeps two planar ones. An
    // interleaved NV row holds a (U, V) pair per chroma sample, so its last
    // sample needs one extra byte beyond the luma-style minimum.
    if (format == YuvFileFormat.nv21) {
      validatePlane(
        plane: planes[1],
        label: 'uvPlane',
        expectedHeight: uvHeight,
        expectedWidth: uvWidth,
        sampleBytes: 2,
      );
      return;
    }

    validatePlane(plane: planes[1], label: 'uPlane', expectedHeight: uvHeight, expectedWidth: uvWidth, sampleBytes: 1);
    validatePlane(plane: planes[2], label: 'vPlane', expectedHeight: uvHeight, expectedWidth: uvWidth, sampleBytes: 1);
  }

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
      throw ArgumentError.value(
        plane.height,
        '$label.height',
        'Expected $expectedHeight rows for this image geometry',
      );
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
}
