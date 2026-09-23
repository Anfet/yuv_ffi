/// Supported in-memory image formats.
///
/// Superseded by [YuvPixelFormat]'s stable wire IDs and truthful `nv12` name;
/// kept for source compatibility with the legacy `nv21` entry points, which
/// retain their historical UV byte order. Formal `@Deprecated` annotation is
/// applied together with the rest of the legacy compatibility surface
/// (REL-06), once every internal use of this type has a migrated call site.
enum YuvFileFormat {
  /// Semi-planar YUV format labeled as NV21 in this project.
  nv21,

  /// Planar YUV 4:2:0 format.
  i420,

  /// Packed BGRA8888 format.
  bgra8888,
}
