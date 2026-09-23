import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart' show YuvNativeException;
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart' show YuvOperation;

import 'impl/yuv_stub.dart' if (dart.library.ffi) 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

export 'impl/yuv_stub.dart' if (dart.library.ffi) 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

/// Represents an in-memory image in one of supported YUV/BGRA formats.
///
/// Use factory constructors to create an instance for a specific format:
/// [YuvImage.i420], [YuvImage.nv21], or [YuvImage.bgra].
///
/// Mutation model (`io` and `web` backends):
/// - In-place (returns `this`): [blackwhite], [gaussianBlur], [boxBlur],
///   [meanBlur], [crop], [flipHorizontally], [flipVertically], [grayscale],
///   [negate], [rotate], [swapNv], [toYuvNv21], [toYuvI420],
///   [toYuvBgra8888].
/// - Returns a new image: [copy].
abstract interface class YuvImage {
  /// Pixel format of the current image.
  YuvFileFormat get format;

  /// Image width in pixels.
  int get width;

  /// Image height in pixels.
  int get height;

  /// Raw image planes in format-specific order.
  List<YuvPlane> get planes;

  /// Luma (Y) plane.
  YuvPlane get yPlane;

  /// U plane for planar formats, or interleaved UV/VU plane for semi-planar.
  YuvPlane get uPlane;

  /// V plane for planar formats.
  YuvPlane get vPlane;

  /// Alias for [yPlane].
  YuvPlane get y;

  /// Optional U plane.
  YuvPlane? get u;

  /// Optional V plane.
  YuvPlane? get v;

  /// Convenience size object built from [width] and [height].
  ui.Size get size;

  /// Creates an I420 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.i420(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.i420;

  /// Creates an NV21-labeled image.
  ///
  /// Note: in this project the `nv21` label is intentionally mapped to UV order.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.nv21(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.nv21;

  /// Creates a BGRA8888 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes}) = YuvImageImpl.bgra;

  /// Creates an image by explicit [format].
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage(YuvFileFormat format, int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl;

  /// Creates an NV12 image with the truthfully named semi-planar storage.
  ///
  /// Canonical replacement for [YuvImage.nv21]: same interleaved chroma
  /// storage, without claiming the legacy NV21 byte order.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted; [uvPixelStride] defaults to `2`, matching the
  /// interleaved `(U, V)` pair every sample stores.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.nv12(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.nv12;

  /// Allocates a new tightly packed, zero-filled image for [format] at
  /// [width] x [height].
  ///
  /// Unlike the named factories, this always produces tight planes with no
  /// row or pixel padding: it is the replacement for `copy(blank: true)`.
  ///
  /// Throws [ArgumentError] for a non-positive dimension.
  factory YuvImage.allocate(YuvPixelFormat format, int width, int height) = YuvImageImpl.allocate;

  /// Creates a new image of [format] at [width] x [height], filled by
  /// converting [bytes] from RGBA8888.
  ///
  /// [bytes] must hold exactly `width * height * 4` tightly packed RGBA
  /// bytes; RGBA8888 is an ABI input-only format and never a storable
  /// [YuvPixelFormat] of its own.
  ///
  /// Throws [ArgumentError] when [bytes] does not have the exact expected
  /// length, or for a non-positive dimension.
  factory YuvImage.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) =
      YuvImageImpl.fromRgbaBytes;

  /// Returns all planes concatenated into a single byte buffer.
  Uint8List getBytes();

  /// Creates a copy as a new image instance.
  ///
  /// If [blank] is `true`, returns an image with same geometry but zeroed planes.
  YuvImage copy({bool blank = false});

  /// Validates [planes] against this image's format and geometry, copies
  /// them in, and atomically replaces the current plane set.
  ///
  /// On success, every previously obtained [planes]/[yPlane]/[uPlane]/[vPlane]
  /// reference (and the legacy [y]/[u]/[v] aliases) becomes stale: it still
  /// points at the storage this image held before the call, not the new one.
  /// Callers must re-fetch plane references afterward. The revision advances
  /// exactly once.
  ///
  /// Throws [ArgumentError] when [planes] does not match this image's format
  /// and geometry. [planes] is copied and validated on that copy before this
  /// image's own plane set is replaced, so a rejected call never touches it:
  /// this image's bytes, metadata and revision are left exactly as they were.
  ///
  /// Returns `this`.
  YuvImage applyPlanes(Iterable<YuvPlane> planes);

  /// Serializes this image into [sink].
  ///
  /// Throws when [sink] rejects writes.
  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  /// Loads image data from [stream] and replaces current state.
  ///
  /// Throws [FormatException] when input payload is malformed.
  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

  /// Applies a black/white threshold effect in-place and returns `this`.
  YuvImage blackwhite() => throw UnimplementedError();

  /// Applies Gaussian blur in-place and returns `this`.
  ///
  /// [radius] controls blur kernel radius, [sigma] controls spread.
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  /// Applies box blur in-place.
  ///
  /// [radius] controls blur neighborhood.
  /// If [rect] is provided, blur is applied only within that region.
  /// Returns `this`.
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  /// Applies mean blur in-place.
  ///
  /// [radius] controls blur neighborhood.
  /// If [rect] is provided, blur is applied only within that region.
  /// Returns `this`.
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  /// Swaps interleaved chroma order for NV formats.
  ///
  /// Operates in-place and returns `this`.
  YuvImage swapNv() => throw UnimplementedError();

  /// Converts image to NV21-labeled representation.
  ///
  /// Operates in-place and returns `this`.
  YuvImage toYuvNv21() => throw UnimplementedError();

  /// Converts image to I420 representation.
  ///
  /// Operates in-place and returns `this`.
  YuvImage toYuvI420() => throw UnimplementedError();

  /// Converts image to BGRA8888 representation.
  ///
  /// Operates in-place and returns `this`.
  YuvImage toYuvBgra8888() => throw UnimplementedError();

  /// Crops the image to [rect] in-place and returns `this`.
  ///
  /// If the effective crop area is empty, image data is left unchanged.
  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  /// Flips the image horizontally in-place and returns `this`.
  YuvImage flipHorizontally() => throw UnimplementedError();

  /// Flips the image vertically in-place and returns `this`.
  YuvImage flipVertically() => throw UnimplementedError();

  /// Fills this image from RGBA8888 bytes.
  ///
  /// Expected size is `width * height * 4`.
  /// Throws [ArgumentError] when [bytes] length does not match that size.
  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  /// Converts image to grayscale in-place and returns `this`.
  YuvImage grayscale() => throw UnimplementedError();

  /// Inverts colors in-place and returns `this`.
  YuvImage negate() => throw UnimplementedError();

  /// Rotates image in-place and returns `this`.
  ///
  /// `rotation0` is a no-op.
  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  /// Returns BGRA8888 bytes with tightly packed rows.
  ///
  /// Returned length is always `width * height * 4`.
  Uint8List toBgra8888() => throw UnimplementedError();

  /// Converts to Flutter [ui.Image].
  ///
  /// Throws if pixel decode fails in the underlying engine.
  Future<ui.Image> toImage() => throw UnimplementedError();

  // -- 0.4.0 `apply*`/`to*` surface (doc/api-abi-0.4-design.md sections 2-4,
  // 13) --------------------------------------------------------------------
  //
  // Every `apply*` below calls `yuvRequireCapability` first, before any
  // allocation, native/WASM invocation, or state change (todo.md REL-04's
  // post-REL-09 addendum). On success it mutates in place, advances the
  // revision exactly once, and returns `identical(this)`. On failure --
  // capability, argument, or a non-zero native status -- bytes, format,
  // geometry and revision are left exactly as they were. A defined no-op
  // (radius 0, an empty normalized crop/ROI, rotation 0, same-format
  // `applyFormat`) short-circuits before dispatch and does not advance the
  // revision. These live alongside the 0.3.0 instance methods above rather
  // than replacing them: retiring those into the deprecated compatibility
  // extension is REL-06's separate task.

  /// Replaces the current pixel content from tight RGBA8888 [bytes], in this
  /// image's own format and geometry, and returns `this`.
  ///
  /// [bytes] must hold exactly `width * height * 4` bytes.
  ///
  /// Throws [ArgumentError] for a wrong [bytes] length, [UnsupportedError]
  /// when this backend/format pair cannot dispatch [YuvOperation.convert], and
  /// [YuvNativeException] for a native overflow/allocation/internal failure.
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnimplementedError();

  /// Converts this image to grayscale in place and returns `this`.
  YuvImage applyGrayscale() => throw UnimplementedError();

  /// Applies a black/white threshold effect in place and returns `this`.
  YuvImage applyBlackWhite() => throw UnimplementedError();

  /// Inverts visible colors in place and returns `this`.
  YuvImage applyNegate() => throw UnimplementedError();

  /// Applies a Gaussian-weighted blur in place and returns `this`.
  ///
  /// [radius] `0` is a no-op. [sigma] must be finite and positive for a
  /// non-zero [radius].
  YuvImage applyGaussianBlur({required int radius, required double sigma}) => throw UnimplementedError();

  /// Applies a uniform mean blur in place and returns `this`.
  ///
  /// [radius] `0` is a no-op. [region] restricts the blurred area to that
  /// normalized rectangle; `null` blurs the whole frame.
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Applies a normalized box blur in place and returns `this`.
  ///
  /// [radius] `0` is a no-op. [region] restricts the blurred area to that
  /// normalized rectangle; `null` blurs the whole frame.
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Crops this image to [region] in place and returns `this`.
  ///
  /// An empty effective (clamped, normalized) region is a no-op.
  YuvImage applyCrop(ui.Rect region) => throw UnimplementedError();

  /// Flips this image horizontally in place and returns `this`.
  YuvImage applyFlipHorizontal() => throw UnimplementedError();

  /// Flips this image vertically in place and returns `this`.
  YuvImage applyFlipVertical() => throw UnimplementedError();

  /// Rotates this image in place and returns `this`.
  ///
  /// [YuvImageRotation.rotation0] is a no-op.
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnimplementedError();

  /// Converts this image to [format] in place and returns `this`.
  ///
  /// Converting to the format this image already has is a no-op.
  YuvImage applyFormat(YuvPixelFormat format) => throw UnimplementedError();

  /// Swaps every interleaved U/V sample value of this NV12 image in place,
  /// keeping the frame labeled NV12, and returns `this`.
  ///
  /// This is a visible channel-value effect, not a format conversion (section
  /// 14, Q1). Throws [UnsupportedError] for I420/BGRA8888 without converting
  /// or mutating.
  YuvImage applyChromaSwap() => throw UnimplementedError();

  /// Returns a new, independent image cropped to [region].
  ///
  /// This image (bytes and revision) is left unchanged. An empty effective
  /// region still returns a new, independently owned image rather than
  /// aliasing this one.
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  /// Returns a new, independent image rotated by [rotation].
  ///
  /// This image (bytes and revision) is left unchanged, even for
  /// [YuvImageRotation.rotation0].
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  /// Returns a new, independent image converted to I420.
  YuvImage toI420() => throw UnimplementedError();

  /// Returns a new, independent image converted to NV12.
  YuvImage toNv12() => throw UnimplementedError();

  /// Returns a new, independent image converted to BGRA8888.
  YuvImage toBgra() => throw UnimplementedError();

  /// Returns every plane's full `height * rowStride` storage concatenated in
  /// format order, including declared row/pixel padding.
  Uint8List toBytes() => throw UnimplementedError();

  /// Returns exactly `width * height * 4` tightly packed visible BGRA8888
  /// pixels.
  Uint8List toBgraBytes() => throw UnimplementedError();
}
