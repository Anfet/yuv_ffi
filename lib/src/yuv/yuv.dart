import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';

import 'impl/yuv_stub.dart'
    if (dart.library.ffi) 'impl/io/yuv_image.dart'
    if (dart.library.js_interop) 'impl/web/yuv_web.dart';

export 'impl/yuv_stub.dart'
    if (dart.library.ffi) 'impl/io/yuv_image.dart'
    if (dart.library.js_interop) 'impl/web/yuv_web.dart';

/// Represents an in-memory image in one of supported YUV/BGRA formats.
///
/// Use factory constructors to create an instance for a specific format:
/// [YuvImage.i420], [YuvImage.nv21], or [YuvImage.bgra].
///
/// Mutation model (native `io` backend):
/// - In-place (returns `this`): [blackwhite], [gaussianBlur], [boxBlur],
///   [meanBlur], [crop], [flipHorizontally], [flipVertically], [grayscale],
///   [negate], [rotate].
/// - Returns a new image: [copy], [swapNv], and format conversion methods
///   ([toYuvNv21], [toYuvI420], [toYuvBgra8888]) when conversion is needed.
/// - Conversion methods return `this` when source format already matches.
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
  factory YuvImage.i420(int width, int height,
      {int yPixelStride,
      int uvPixelStride,
      Iterable<YuvPlane>? planes}) = YuvImageImpl.i420;

  /// Creates an NV21-labeled image.
  ///
  /// Note: in this project the `nv21` label is intentionally mapped to UV order.
  factory YuvImage.nv21(int width, int height,
      {int yPixelStride,
      int uvPixelStride,
      Iterable<YuvPlane>? planes}) = YuvImageImpl.nv21;

  /// Creates a BGRA8888 image.
  factory YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes}) =
      YuvImageImpl.bgra;

  /// Creates an image by explicit [format].
  factory YuvImage(YuvFileFormat format, int width, int height,
      {int yPixelStride,
      int uvPixelStride,
      Iterable<YuvPlane>? planes}) = YuvImageImpl;

  /// Returns all planes concatenated into a single byte buffer.
  Uint8List getBytes();

  /// Creates a copy as a new image instance.
  ///
  /// If [blank] is `true`, returns an image with same geometry but zeroed planes.
  YuvImage copy({bool blank = false});

  /// Serializes this image into a sink.
  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  /// Loads image data from a stream and replaces current state.
  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

  /// Applies a black/white threshold effect in-place and returns `this`.
  YuvImage blackwhite() => throw UnimplementedError();

  /// Applies Gaussian blur in-place and returns `this`.
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) =>
      throw UnimplementedError();

  /// Applies box blur in-place.
  ///
  /// If [rect] is provided, blur is applied only within that region.
  /// Returns `this`.
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) =>
      throw UnimplementedError();

  /// Applies mean blur in-place.
  ///
  /// If [rect] is provided, blur is applied only within that region.
  /// Returns `this`.
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) =>
      throw UnimplementedError();

  /// Swaps interleaved chroma order for NV formats.
  ///
  /// Returns a new image instance.
  YuvImage swapNv() => throw UnimplementedError();

  /// Converts image to NV21-labeled representation.
  ///
  /// Returns `this` when already NV21-labeled, otherwise returns a new image.
  YuvImage toYuvNv21() => throw UnimplementedError();

  /// Converts image to I420 representation.
  ///
  /// Returns `this` when already I420, otherwise returns a new image.
  YuvImage toYuvI420() => throw UnimplementedError();

  /// Converts image to BGRA8888 representation.
  ///
  /// Returns `this` when already BGRA8888, otherwise returns a new image.
  YuvImage toYuvBgra8888() => throw UnimplementedError();

  /// Crops the image to [rect] in-place and returns `this`.
  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  /// Flips the image horizontally in-place and returns `this`.
  YuvImage flipHorizontally() => throw UnimplementedError();

  /// Flips the image vertically in-place and returns `this`.
  YuvImage flipVertically() => throw UnimplementedError();

  /// Fills this image from RGBA8888 bytes.
  ///
  /// Expected size is `width * height * 4`.
  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  /// Converts image to grayscale in-place and returns `this`.
  YuvImage grayscale() => throw UnimplementedError();

  /// Inverts colors in-place and returns `this`.
  YuvImage negate() => throw UnimplementedError();

  /// Rotates image in-place and returns `this`.
  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  /// Returns BGRA8888 bytes.
  Uint8List toBgra8888() => throw UnimplementedError();

  /// Converts to Flutter [ui.Image].
  Future<ui.Image> toImage() => throw UnimplementedError();
}
