/// Supported in-memory image formats.
enum YuvFileFormat {
  /// Semi-planar YUV format labeled as NV21 in this project.
  nv21,

  /// Planar YUV 4:2:0 format.
  i420,

  /// Packed BGRA8888 format.
  bgra8888
}
