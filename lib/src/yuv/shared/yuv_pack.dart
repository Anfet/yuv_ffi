import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_packing.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Provides packed-layout operations for a [YuvImage].
///
/// The tightly packed target stride per plane is format-defined, not always
/// `pixelStride == 1`: I420 Y/U/V samples are one byte each, so a packed I420
/// chroma plane has `pixelStride == 1`; NV12's interleaved UV
/// plane stores a `(U, V)` byte pair per chroma sample, so its packed
/// `pixelStride` stays `2` -- native code addresses that pair at `index * 2`
/// (`YuvGeometry.nvChromaPixelStride`), and `1` would split the pair rather
/// than removing padding. BGRA8888 has one packed pixel plane at
/// `pixelStride == 4`.
///
/// [YuvPlaneLayout.packed] applies the same conversion during factory
/// construction.
extension YuvImagePack on YuvImage {
  // ignore: deprecated_member_use_from_same_package
  YuvFileFormat get _legacyFormat => format.legacy;

  /// Whether every plane of this image is already tightly packed: zero row
  /// padding (`rowStride == columns * pixelStride`) and zero per-sample pixel
  /// gap (`pixelStride == ` the format's packed sample width).
  bool get isTightlyPacked => YuvPlanePacking.isTightlyPacked(_legacyFormat, width, height, planes);

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
  /// and orientation. Existing [YuvImage.planes]/`yPlane`/`uPlane`/`vPlane`
  /// references become stale, as [YuvImage.applyPlanes]
  /// documents. The row padding and pixel gap bytes this discards cannot be
  /// recovered afterward; call `copy()` first to keep an independent padded
  /// image around.
  YuvImage pack() {
    if (isTightlyPacked) return this;
    return applyPlanes(YuvPlanePacking.packAll(_legacyFormat, width, height, planes));
  }
}
