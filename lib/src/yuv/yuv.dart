import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';

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

  /// Returns all planes concatenated into a single byte buffer.
  Uint8List getBytes();

  /// Creates a copy as a new image instance.
  ///
  /// If [blank] is `true`, returns an image with same geometry but zeroed planes.
  YuvImage copy({bool blank = false});

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
}
