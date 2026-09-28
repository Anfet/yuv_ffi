import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';

/// Storage format of a `YuvImage`.
///
/// Each value carries a stable [wireId] that never changes and is never
/// derived from [Enum.index]: the index reflects declaration order and would
/// silently renumber if a value were inserted, while [wireId] is the number
/// written to and read from the codec.
///
/// This is the truthfully named replacement for the legacy `nv21` label:
/// [nv12] describes the same canonical semi-planar chroma storage, without
/// claiming an NV21 byte order. RGBA8888 is a conversion source, not a
/// storable image format.
enum YuvPixelFormat {
  /// Planar YUV 4:2:0: separate Y, U and V planes.
  i420(1),

  /// Semi-planar YUV 4:2:0: a Y plane plus one interleaved UV chroma plane.
  nv12(2),

  /// Packed BGRA8888.
  bgra8888(3);

  const YuvPixelFormat(this.wireId);

  /// Stable numeric identity used by the codec and the native ABI.
  ///
  /// Never equal to [Enum.index] by contract: adding or reordering values
  /// must not change what a payload already on disk means.
  final int wireId;
}

/// Internal bridge between the new [YuvPixelFormat] and the legacy
// ignore: deprecated_member_use_from_same_package
/// [YuvFileFormat] the current backends still key their state on.
///
/// Not exported: callers on the public surface only ever see one format type
/// per member. It lets the implementation use the legacy storage identity.
extension YuvPixelFormatLegacyBridge on YuvPixelFormat {
  /// The legacy format this value stores as.
  ///
  // ignore: deprecated_member_use_from_same_package
  /// [YuvPixelFormat.nv12] maps to [YuvFileFormat.nv21]: today that is the
  /// only legacy value backed by semi-planar storage, and the truthful NV12
  /// label carries no different byte order of its own.
  // ignore: deprecated_member_use_from_same_package
  YuvFileFormat get legacy => switch (this) {
    // ignore: deprecated_member_use_from_same_package
    YuvPixelFormat.i420 => YuvFileFormat.i420,
    // ignore: deprecated_member_use_from_same_package
    YuvPixelFormat.nv12 => YuvFileFormat.nv21,
    // ignore: deprecated_member_use_from_same_package
    YuvPixelFormat.bgra8888 => YuvFileFormat.bgra8888,
  };
}

/// Internal helper the other direction, from legacy storage to the new
/// exported format identity.
// ignore: deprecated_member_use_from_same_package
extension YuvFileFormatPixelFormatBridge on YuvFileFormat {
  /// The [YuvPixelFormat] that names this legacy value's storage truthfully.
  YuvPixelFormat get pixelFormat => switch (this) {
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.i420 => YuvPixelFormat.i420,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.nv21 => YuvPixelFormat.nv12,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.bgra8888 => YuvPixelFormat.bgra8888,
  };
}
