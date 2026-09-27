import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// Shared tight-packing geometry and copy loop for every backend and for the
/// public `YuvImagePack.pack()` extension (PACK-01A/B).
///
/// Kept independent of any live [YuvImage] instance -- unlike
/// `YuvImagePack`, which reads an existing image's `format`/`width`/`height`
/// -- so [YuvImageState]'s constructor can pack caller-supplied `planes`
/// before an image object exists at all.
abstract final class YuvPlanePacking {
  /// Bytes per sample the plane at [planeIndex] of [format] is packed to.
  ///
  /// Index `0` is the Y/packed plane; for I420 indices `1`/`2` (U/V) are `1`,
  /// for the semi-planar formats index `1` (interleaved UV) is
  /// [YuvGeometry.nvChromaPixelStride] -- native code addresses that plane as
  /// a packed `(U, V)` pair, so packing it to `1` would split the pair rather
  /// than remove padding.
  // ignore: deprecated_member_use_from_same_package
  static int packedSampleBytes(YuvFileFormat format, int planeIndex) => switch (format) {
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.bgra8888 => 4,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.i420 => 1,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.nv21 => planeIndex == 0 ? 1 : YuvGeometry.nvChromaPixelStride,
  };

  /// The sample columns of the plane at [planeIndex]: [width] for the
  /// luma/packed plane, chroma width (rounded up) for a chroma plane.
  static int planeColumns(int planeIndex, int width) => planeIndex == 0 ? width : YuvGeometry.chromaWidth(width);

  /// The sample rows of the plane at [planeIndex]: [height] for the
  /// luma/packed plane, chroma height (rounded up) for a chroma plane.
  static int planeRows(int planeIndex, int height) => planeIndex == 0 ? height : YuvGeometry.chromaHeight(height);

  /// Whether every one of [planes] is already tightly packed for [format] at
  /// [width] x [height]: zero row padding (`rowStride == columns *
  /// sampleBytes`) and zero per-sample pixel gap (`pixelStride ==
  /// sampleBytes`).
  // ignore: deprecated_member_use_from_same_package
  static bool isTightlyPacked(YuvFileFormat format, int width, int height, List<YuvPlane> planes) {
    for (var i = 0; i < planes.length; i++) {
      final plane = planes[i];
      final sampleBytes = packedSampleBytes(format, i);
      if (plane.pixelStride != sampleBytes) return false;
      if (plane.rowStride != planeColumns(i, width) * sampleBytes) return false;
    }
    return true;
  }

  /// Builds a tightly packed replacement for every plane of [planes], for
  /// [format] at [width] x [height].
  // ignore: deprecated_member_use_from_same_package
  static List<YuvPlane> packAll(YuvFileFormat format, int width, int height, List<YuvPlane> planes) => [
    for (var i = 0; i < planes.length; i++)
      packPlane(planes[i], rows: planeRows(i, height), columns: planeColumns(i, width), sampleBytes: packedSampleBytes(format, i)),
  ];

  /// Copies [rows] * [columns] visible samples of one plane out of [source]
  /// into a new tightly packed [YuvPlane]: row stride `columns *
  /// sampleBytes`, pixel stride `sampleBytes`.
  ///
  /// [sampleBytes] is how many leading bytes of each [YuvPlane.pixelStride]-wide
  /// source slot are copied. When [source]'s pixel stride is wider than
  /// [sampleBytes] this de-interleaves: any byte belonging to a different
  /// channel packed into the same source slot (I420 U/V reported at
  /// `pixelStride == 2` on some Android devices -- PACK-00) is left behind,
  /// not carried into the packed plane.
  static YuvPlane packPlane(YuvPlane source, {required int rows, required int columns, required int sampleBytes}) {
    final tightRowStride = columns * sampleBytes;
    if (source.pixelStride == sampleBytes && source.rowStride == tightRowStride) {
      return source.copy();
    }

    final packed = Uint8List(rows * tightRowStride);
    final sourceBytes = source.bytes;
    for (var row = 0; row < rows; row++) {
      final sourceRowStart = row * source.rowStride;
      final destRowStart = row * tightRowStride;
      if (source.pixelStride == sampleBytes) {
        packed.setRange(destRowStart, destRowStart + tightRowStride, sourceBytes, sourceRowStart);
        continue;
      }
      for (var col = 0; col < columns; col++) {
        final sourceSampleStart = sourceRowStart + col * source.pixelStride;
        final destSampleStart = destRowStart + col * sampleBytes;
        for (var b = 0; b < sampleBytes; b++) {
          packed[destSampleStart + b] = sourceBytes[sourceSampleStart + b];
        }
      }
    }
    return YuvPlane(rows, tightRowStride, sampleBytes, packed);
  }
}
