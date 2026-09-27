import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// PACK-01A: reports and removes row padding and per-sample pixel gaps from a
/// [YuvImage]'s planes without changing its format, geometry, visible content
/// or UV order.
///
/// The tightly packed target stride per plane is format-defined, not always
/// `pixelStride == 1`: I420 Y/U/V samples are one byte each, so a packed I420
/// chroma plane has `pixelStride == 1` (PACK-00 found this is the geometry
/// that reaches the native rotate kernel's fast path); NV12's interleaved UV
/// plane stores a `(U, V)` byte pair per chroma sample, so its packed
/// `pixelStride` stays `2` -- native code addresses that pair at `index * 2`
/// ([YuvGeometry.nvChromaPixelStride]), and `1` would split the pair rather
/// than removing padding. BGRA8888 has one packed pixel plane at
/// `pixelStride == 4`.
extension YuvImagePack on YuvImage {
  /// Bytes per sample this image's plane at [planeIndex] is packed to.
  ///
  /// Index `0` is the Y/packed plane; for I420 indices `1`/`2` (U/V) are `1`,
  /// for NV12 index `1` (interleaved UV) is [YuvGeometry.nvChromaPixelStride].
  int _packedSampleBytes(int planeIndex) => switch (format) {
    YuvPixelFormat.bgra8888 => 4,
    YuvPixelFormat.i420 => 1,
    YuvPixelFormat.nv12 => planeIndex == 0 ? 1 : YuvGeometry.nvChromaPixelStride,
  };

  /// The sample columns of the plane at [planeIndex]: image width for the
  /// luma/packed plane, chroma width (rounded up) for a chroma plane.
  int _planeColumns(int planeIndex) => planeIndex == 0 ? width : YuvGeometry.chromaWidth(width);

  /// Whether every plane of this image is already tightly packed: zero row
  /// padding (`rowStride == columns * pixelStride`) and zero per-sample pixel
  /// gap (`pixelStride == ` the format's packed sample width).
  bool get isTightlyPacked {
    final imagePlanes = planes;
    for (var i = 0; i < imagePlanes.length; i++) {
      final plane = imagePlanes[i];
      final sampleBytes = _packedSampleBytes(i);
      if (plane.pixelStride != sampleBytes) return false;
      if (plane.rowStride != _planeColumns(i) * sampleBytes) return false;
    }
    return true;
  }

  /// Repacks this image's planes to remove row padding and pixel gaps, in
  /// place, and returns `this`.
  ///
  /// A no-op when [isTightlyPacked] is already `true`: the revision does not
  /// advance and no plane is reallocated. Otherwise a full set of tightly
  /// packed replacement planes is built and validated before
  /// [YuvImage.applyPlanes] adopts them in one step, so a partially packed
  /// state is never published and the revision advances exactly once.
  ///
  /// Preserves every visible sample, the pixel format, UV order, image size
  /// and orientation. Previously read [YuvImage.planes]/`yPlane`/`uPlane`/
  /// `vPlane` references become stale, exactly as [YuvImage.applyPlanes]
  /// documents. The row padding and pixel gap bytes this discards cannot be
  /// recovered afterward; call `copy()` first to keep an independent padded
  /// image around.
  YuvImage pack() {
    if (isTightlyPacked) return this;

    final imagePlanes = planes;
    final packedPlanes = <YuvPlane>[
      for (var i = 0; i < imagePlanes.length; i++)
        _packPlane(
          imagePlanes[i],
          rows: i == 0 ? height : YuvGeometry.chromaHeight(height),
          columns: _planeColumns(i),
          sampleBytes: _packedSampleBytes(i),
        ),
    ];
    return applyPlanes(packedPlanes);
  }

  /// Copies [rows] * [columns] visible samples of one plane out of [source]
  /// into a new tightly packed [YuvPlane]: row stride `columns * sampleBytes`,
  /// pixel stride `sampleBytes`.
  ///
  /// [sampleBytes] is how many leading bytes of each [YuvPlane.pixelStride]-wide
  /// source slot are copied. When [source]'s pixel stride is wider than
  /// [sampleBytes] this de-interleaves: any byte belonging to a different
  /// channel packed into the same source slot (I420 U/V reported at
  /// `pixelStride == 2` on some Android devices -- PACK-00) is left behind,
  /// not carried into the packed plane.
  static YuvPlane _packPlane(YuvPlane source, {required int rows, required int columns, required int sampleBytes}) {
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
