import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_layout.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart' show YuvNativeException;
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart' show YuvOperation;

import 'impl/yuv_stub.dart' if (dart.library.ffi) 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

/// Represents an in-memory image in one of supported YUV/BGRA formats.
///
/// Use factory constructors to create an instance for a specific format:
/// [YuvImage.i420], [YuvImage.nv12], or [YuvImage.bgra].
///
/// Both backends provide the same mutation model:
/// - In-place (returns `this`): [applyGrayscale], [applyBlackWhite],
///   [applyNegate], [applyGaussianBlur], [applyMeanBlur], [applyBoxBlur],
///   [applyCrop], [applyFlipHorizontal], [applyFlipVertical],
///   [applyRotation], [applyFormat], [applyChromaSwap], [applyRgbaBytes],
///   [applyPlanes].
/// - Returns a new, independent image: [copy], [cropped], [rotated],
///   [toI420], [toNv12], [toBgra], and the static [YuvImage.decode].
abstract interface class YuvImage {
  /// Pixel format of the current image.
  YuvPixelFormat get format;

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

  /// Convenience size object built from [width] and [height].
  ui.Size get size;

  /// Creates an I420 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied according to [layout].
  /// [YuvPlaneLayout.packed] is the default and copies only
  /// the visible samples into a tightly packed layout, discarding row padding
  /// and any per-sample pixel gap; [YuvPlaneLayout.preserve] keeps the given
  /// `rowStride`/`pixelStride` byte-for-byte. [layout] is ignored when
  /// [planes] is omitted because allocated images are already tightly packed.
  factory YuvImage.i420(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes, YuvPlaneLayout layout}) =
      YuvImageImpl.i420;

  /// Creates a BGRA8888 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// If [planes] is provided, plane data is copied from it, according to
  /// [layout]; see [YuvImage.i420].
  factory YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes, YuvPlaneLayout layout}) = YuvImageImpl.bgra;

  /// Creates an image for [format].
  ///
  /// Prefer a named factory when the format is known statically.
  factory YuvImage(
    YuvPixelFormat format,
    int width,
    int height, {
    int yPixelStride,
    int uvPixelStride,
    Iterable<YuvPlane>? planes,
    YuvPlaneLayout layout,
  }) = YuvImageImpl;

  /// Creates an NV12 image with the truthfully named semi-planar storage.
  ///
  /// Uses interleaved UV chroma storage.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted; [uvPixelStride] defaults to `2`, matching the
  /// interleaved `(U, V)` pair every sample stores.
  /// If [planes] is provided, plane data is copied from it, according to
  /// [layout]; see [YuvImage.i420]. NV12's packed chroma stays `pixelStride ==
  /// 2` under [YuvPlaneLayout.packed] -- native code addresses the
  /// interleaved plane as a packed `(U, V)` pair, so only row padding is
  /// removed, never the pair itself.
  factory YuvImage.nv12(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes, YuvPlaneLayout layout}) =
      YuvImageImpl.nv12;

  /// Allocates a new tightly packed, zero-filled image for [format] at
  /// [width] x [height].
  ///
  /// Unlike the named factories, this always produces tight planes with no
  /// row or pixel padding.
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

  /// Creates a copy as a new image instance.
  YuvImage copy();

  /// Validates [planes] against this image's format and geometry, copies
  /// them in, and atomically replaces the current plane set.
  ///
  /// On success, every previously obtained [planes]/[yPlane]/[uPlane]/[vPlane]
  /// reference becomes stale: it still points at the storage this image held
  /// before the call, not the new one. Callers must re-fetch plane references
  /// afterward. The revision advances exactly once.
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
  /// Does not mutate this image. Throws when [sink] rejects writes.
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

  /// Decodes [stream] into a new, independent image.
  ///
  /// Never mutates an existing instance -- there is no receiver, only a fresh
  /// image built from the decoded payload.
  ///
  /// Throws [FormatException] when [stream] holds a malformed or unsupported
  /// payload.
  static Future<YuvImage> decode(Stream<List<int>> stream) async {
    final draft = await YuvCodec.decodeStream(stream);
    return YuvImageImpl(
      draft.format,
      draft.width,
      draft.height,
      planes: draft.planes,
      allowLargerNvChromaStride: draft.format == YuvPixelFormat.nv12 && draft.planes[1].pixelStride > 2,
      layout: YuvPlaneLayout.preserve,
    );
  }

  /// Converts to Flutter [ui.Image].
  ///
  /// Throws if pixel decode fails in the underlying engine.
  Future<ui.Image> toImage() => throw UnimplementedError();

  /// The `apply*` methods validate backend capability before changing this
  /// image. Successful calls mutate it in place, advance [revision] once, and
  /// return `this`. Rejected calls leave its bytes, format, geometry, and
  /// revision unchanged. A no-op does not advance [revision].

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
  /// [region] uses image-pixel coordinates, rounded outward to whole pixels
  /// and clamped to the image bounds; `null` blurs the whole frame. [radius]
  /// `0` is a no-op.
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Applies a normalized box blur in place and returns `this`.
  ///
  /// [region] uses image-pixel coordinates, rounded outward to whole pixels
  /// and clamped to the image bounds; `null` blurs the whole frame. [radius]
  /// `0` is a no-op.
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Crops this image to [region] in place and returns `this`.
  ///
  /// [region] uses image-pixel coordinates. Its near edges are rounded down,
  /// far edges are rounded up, and the result is clamped to the image bounds.
  /// An empty effective region is a no-op.
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
  /// Throws [UnsupportedError] for I420 and BGRA8888 without mutating.
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
