/// Storage format of a `YuvImage`.
///
/// Each value carries a stable [wireId] that never changes and is never
/// derived from [Enum.index]: the index reflects declaration order and would
/// silently renumber if a value were inserted, while [wireId] is the number
/// written to and read from the codec.
///
/// RGBA8888 is a conversion source, not a storable image format.
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
