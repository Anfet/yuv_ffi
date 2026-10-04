/// Controls how factories store caller-supplied `YuvPlane` instances.
///
/// Factories default to [packed]. `YuvImage.copy()`, `YuvImage.decode()`, and
/// `YuvImage.applyPlanes()` preserve their plane layout.
enum YuvPlaneLayout {
  /// Keep the caller's plane layout exactly as given: row stride, pixel
  /// stride and every padding byte, unchanged.
  preserve,

  /// Copy only the visible samples into a tightly packed layout: no row
  /// padding, and (per format) no per-sample pixel gap. Equivalent to calling
  /// [preserve] followed by `YuvImagePack.pack()`, but without allocating the
  /// intermediate padded copy.
  packed,
}
