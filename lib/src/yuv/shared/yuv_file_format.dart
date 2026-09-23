/// Supported in-memory image formats.
///
/// Superseded by [YuvPixelFormat]'s stable wire IDs and truthful `nv12` name;
/// kept for source compatibility with the legacy `nv21` entry points, which
/// retain their historical UV byte order.
@Deprecated('Use YuvPixelFormat. This legacy label is kept only for the nv21 entry points that still key their state on it.')
enum YuvFileFormat {
  /// Semi-planar YUV format labeled as NV21 in this project.
  nv21,

  /// Planar YUV 4:2:0 format.
  i420,

  /// Packed BGRA8888 format.
  bgra8888,
}
