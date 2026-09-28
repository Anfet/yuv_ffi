/// Supported in-memory image formats.
///
/// Deprecated in favor of [YuvPixelFormat]. The `nv21` member represents
/// interleaved UV storage for compatibility.
@Deprecated('Use YuvPixelFormat. This legacy label is kept only for the nv21 entry points that still key their state on it.')
enum YuvFileFormat {
  /// Semi-planar YUV format labeled as NV21 in this project.
  nv21,

  /// Planar YUV 4:2:0 format.
  i420,

  /// Packed BGRA8888 format.
  bgra8888,
}
