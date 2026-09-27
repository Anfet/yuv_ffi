/// How a `YuvImage` factory that accepts caller-supplied `planes` stores them.
///
/// PACK-01A found that dense packing (`YuvImagePack.pack()`) can matter a lot
/// for performance -- on a real Pixel 3, packing I420 chroma from
/// `pixelStride == 2` down to `1` cut `applyRotation` from 15.0 ms to 4.5 ms.
/// PACK-01B lets every `planes`-accepting factory apply that packing at
/// construction time instead of requiring a separate `pack()` call
/// afterwards.
///
/// Only affects factory construction, not a permanent property of the image:
/// [YuvImage.applyPlanes] still accepts and keeps whatever strides the caller
/// passes it, regardless of which [YuvPlaneLayout] the image was built with.
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
