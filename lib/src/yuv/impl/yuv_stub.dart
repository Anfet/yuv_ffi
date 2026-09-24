import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_legacy_dispatch.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Fallback implementation for a target with neither `dart:ffi` nor
/// `dart:js_interop`.
///
/// Format, geometry, plane, copy and serialization state lives in the shared
/// [YuvImageState] this holds by composition (YUV-28); what remains here is the
/// no-backend behavior itself -- every processing operation is a no-op, and the
/// format conversions only restate geometry.
class YuvImageImpl implements YuvImage, YuvRevisionAware, YuvLegacyDispatchAdapter {
  // I420 stores U and V as separate single-byte-per-sample planes, so the
  // default pixelStride is 1, unlike NV21's interleaved (U, V) pairs.
  YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
    // ignore: deprecated_member_use_from_same_package
    : this(YuvFileFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
    // ignore: deprecated_member_use_from_same_package
    : this(YuvFileFormat.nv21, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes})
    // ignore: deprecated_member_use_from_same_package
    : this(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, uvPixelStride: 1, planes: planes);

  /// Truthfully named replacement for [YuvImageImpl.nv21]: same semi-planar
  /// storage, same default interleaved chroma pixel stride of 2.
  ///
  /// Unlike [YuvImageImpl.nv21], an explicit [uvPixelStride] above the packed
  /// pair minimum is honored as a real pixel gap rather than being folded into
  /// the legacy constructor's own validation; see
  /// [YuvGeometry.validateImage]'s `allowLargerNvChromaStride`.
  YuvImageImpl.nv12(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
    : _state = YuvImageState(
        // ignore: deprecated_member_use_from_same_package
        YuvFileFormat.nv21,
        width,
        height,
        yPixelStride: yPixelStride,
        uvPixelStride: uvPixelStride,
        planes: planes,
        allowLargerNvChromaStride: true,
      );

  YuvImageImpl(
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat format,
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
    bool allowLargerNvChromaStride = false,
  }) : _state = YuvImageState(
         format,
         width,
         height,
         yPixelStride: yPixelStride,
         uvPixelStride: uvPixelStride,
         planes: planes,
         allowLargerNvChromaStride: allowLargerNvChromaStride,
       );

  /// Allocates a new tightly packed, zero-filled image for [format].
  factory YuvImageImpl.allocate(YuvPixelFormat format, int width, int height) {
    final legacy = format.legacy;
    return YuvImageImpl(
      legacy,
      width,
      height,
      planes: YuvImageState.allocatePlanes(format: legacy, width: width, height: height),
    );
  }

  /// Creates a new [format] image at [width] x [height], filled by converting
  /// [bytes] from RGBA8888.
  ///
  /// There is no backend to convert samples with here, so only the exact
  /// length is validated and, for BGRA, the bytes are reordered directly
  // ignore: deprecated_member_use_from_same_package
  /// (matching [fromRgba8888]); a non-BGRA target has no conversion and stays
  /// zero-filled, consistent with this stub's no-op processing contract.
  factory YuvImageImpl.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) {
    final expectedLength = width * height * 4;
    if (bytes.length != expectedLength) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected $expectedLength bytes for RGBA8888 frame ${width}x$height');
    }
    final image = YuvImageImpl.allocate(format, width, height);
    image.legacyFromRgba8888(bytes);
    return image;
  }

  final YuvImageState _state;

  @override
  int get internalRevision => _state.revision;

  @override
  void bumpInternalRevision() => _state.bumpRevision();

  @override
  YuvPixelFormat get format => _state.format.pixelFormat;

  @override
  int get width => _state.width;

  @override
  int get height => _state.height;

  @override
  List<YuvPlane> get planes => _state.planes;

  @override
  YuvPlane get yPlane => _state.yPlane;

  @override
  YuvPlane get uPlane => _state.uPlane;

  @override
  YuvPlane get vPlane => _state.vPlane;

  @override
  ui.Size get size => _state.size;

  Uint8List _getBytes() => _state.getBytes();

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) {
    _state.applyPlanes(planes);
    return this;
  }

  @override
  YuvImage copy({bool blank = false}) => YuvImageImpl(
    _state.format,
    width,
    height,
    yPixelStride: _state.yPixelStride,
    uvPixelStride: _state.uvPixelStride,
    allowLargerNvChromaStride: _state.allowsLargerNvChromaStride,
    planes: _state.copiedPlanes(blank: blank),
  );

  @override
  Future<void> encodeTo(Sink<List<int>> sink) async {
    sink.add(_getBytes());
  }

  @override
  Future<void> legacyLoad(Stream<List<int>> stream) => _state.decodeAndReplace(stream);

  @override
  String toString() {
    return '$runtimeType(format: ${_state.format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  @override
  void legacyFromRgba8888(Uint8List bytes) {
    if (bytes.length != width * height * 4) {
      return;
    }

    // ignore: deprecated_member_use_from_same_package
    if (_state.format == YuvFileFormat.bgra8888) {
      final bgra = Uint8List(bytes.length);
      for (int i = 0; i < bytes.length; i += 4) {
        bgra[i] = bytes[i + 2];
        bgra[i + 1] = bytes[i + 1];
        bgra[i + 2] = bytes[i];
        bgra[i + 3] = bytes[i + 3];
      }
      yPlane.assignFrom(bgra);
      _state.bumpRevision();
    }
  }

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgraBytes(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  // No native/WASM backend exists here, so every legacy effect/blur is a
  // no-op, exactly as `0.3.0`'s stub behavior was: there is nothing to
  // dispatch, so validation and processing are the same thing this stub
  // always did -- nothing, beyond the geometry work crop/format-reinterpret
  // still do below.

  @override
  YuvImage legacyBlackWhite() => this;

  @override
  YuvImage legacyGrayscale() => this;

  @override
  YuvImage legacyNegate() => this;

  @override
  YuvImage legacyGaussianBlur({required int radius, required double sigma}) => this;

  @override
  YuvImage legacyBoxBlur({required int radius, ui.Rect? rect}) => this;

  @override
  YuvImage legacyMeanBlur({required int radius, ui.Rect? rect}) => this;

  @override
  YuvImage legacyFlipHorizontal() => this;

  @override
  YuvImage legacyFlipVertical() => this;

  @override
  YuvImage legacyRotate(YuvImageRotation rotation) => this;

  @override
  YuvImage legacyCrop(ui.Rect rect) {
    // Clamped through the shared helper, so an empty rect is the same no-op it
    // is on the native and Web backends. The previous stub-only clamp allowed a
    // zero width or height through, which then either built a degenerate plane
    // or made the plane allocation throw after the geometry had already been
    // overwritten -- leaving the image inconsistent.
    final region = _state.clampCrop(rect);
    if (region == null) {
      return this;
    }
    _state.replace(
      format: _state.format,
      width: region.width,
      height: region.height,
      planes: YuvImageState.allocatePlanes(format: _state.format, width: region.width, height: region.height, yPixelStride: _state.yPixelStride),
    );
    return this;
  }

  @override
  // ignore: deprecated_member_use_from_same_package
  YuvImage legacyConvertTo(YuvFileFormat target) {
    // Replaces the planes with a freshly allocated, zeroed set for [target] at
    // the current geometry. There is no backend to convert samples with, so a
    // conversion here only restates the layout: the pixel data is lost, which
    // is the whole point of this being a stub. The luma pixel stride is
    // carried over so a BGRA source does not silently become a
    // one-byte-per-sample plane.
    if (_state.format == target) {
      return this;
    }
    _state.replace(
      format: target,
      width: width,
      height: height,
      planes: YuvImageState.allocatePlanes(format: target, width: width, height: height, yPixelStride: _state.yPixelStride),
    );
    return this;
  }

  /// No-op: this stub has no backend to stage a real convert-then-swap with,
  /// consistent with `0.3.0`'s `swapNv()` returning `this` unconditionally here.
  @override
  YuvImage legacySwapNv() => this;

  // This stub has no backend at all -- neither `dart:ffi` nor
  // `dart:js_interop` -- so it has no capability snapshot to check and every
  // `apply*`/`to*` below is unconditionally unsupported, per the same
  // no-backend contract every other member on this class already follows.

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyGrayscale() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyBlackWhite() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyNegate() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) =>
      throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyCrop(ui.Rect region) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyFlipHorizontal() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyFlipVertical() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyFormat(YuvPixelFormat format) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage applyChromaSwap() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage cropped(ui.Rect region) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage rotated(YuvImageRotation rotation) => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage toI420() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage toNv12() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  YuvImage toBgra() => throw UnsupportedError('No yuv_ffi backend is available on this target.');

  @override
  Uint8List toBytes() => _getBytes();

  @override
  Uint8List toBgraBytes() {
    // ignore: deprecated_member_use_from_same_package
    if (_state.format == YuvFileFormat.bgra8888) {
      return Uint8List.fromList(yPlane.bytes);
    }
    return Uint8List(width * height * 4);
  }
}
