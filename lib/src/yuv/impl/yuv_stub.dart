// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_layout.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Fallback implementation for a target with neither `dart:ffi` nor
/// `dart:js_interop`.
///
/// Format, geometry, plane, copy and serialization state lives in the shared
/// [YuvImageState] this holds by composition; what remains here is the
/// no-backend behavior itself -- every processing operation is a no-op, and the
/// format conversions only restate geometry.
class YuvImageImpl implements YuvImage, YuvRevisionAware {
  // I420 stores U and V as separate single-byte-per-sample planes, so the
  // default pixelStride is 1, unlike NV12's interleaved (U, V) pairs.
  YuvImageImpl.i420(
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
    YuvPlaneLayout layout = YuvPlaneLayout.packed,
  })
    : this(YuvPixelFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes, layout: layout);

  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes, YuvPlaneLayout layout = YuvPlaneLayout.packed})
    : this(YuvPixelFormat.bgra8888, width, height, yPixelStride: 4, uvPixelStride: 1, planes: planes, layout: layout);

  /// Creates semi-planar NV12 storage with interleaved chroma pixel stride 2.
  ///
  /// An explicit [uvPixelStride] above the packed pair minimum is honored as a
  /// real pixel gap; [YuvGeometry.validateImage] validates that declared
  /// layout and operations preserve it.
  YuvImageImpl.nv12(
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 2,
    Iterable<YuvPlane>? planes,
    YuvPlaneLayout layout = YuvPlaneLayout.packed,
  }) : _state = YuvImageState(
         YuvPixelFormat.nv12,
         width,
         height,
         yPixelStride: yPixelStride,
         uvPixelStride: uvPixelStride,
         planes: planes,
         allowLargerNvChromaStride: true,
         layout: layout,
       );

  YuvImageImpl(
    YuvPixelFormat format,
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
    bool allowLargerNvChromaStride = false,
    YuvPlaneLayout layout = YuvPlaneLayout.packed,
  }) : _state = YuvImageState(
         format,
         width,
         height,
         yPixelStride: yPixelStride,
         uvPixelStride: uvPixelStride,
         planes: planes,
         allowLargerNvChromaStride: allowLargerNvChromaStride,
         layout: layout,
       );

  /// Allocates a new tightly packed, zero-filled image for [format].
  factory YuvImageImpl.allocate(YuvPixelFormat format, int width, int height) {
    return YuvImageImpl(
      format,
      width,
      height,
      planes: YuvImageState.allocatePlanes(format: format, width: width, height: height),
      layout: YuvPlaneLayout.preserve,
    );
  }

  /// Creates a new [format] image at [width] x [height], filled by converting
  /// [bytes] from RGBA8888.
  ///
  /// There is no backend to convert samples with here, so only the exact
  /// length is validated and, for BGRA, the bytes are reordered directly
  /// (matching [applyRgbaBytes]); a non-BGRA target has no conversion and stays
  /// zero-filled, consistent with this stub's no-op processing contract.
  factory YuvImageImpl.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) {
    final expectedLength = width * height * 4;
    if (bytes.length != expectedLength) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected $expectedLength bytes for RGBA8888 frame ${width}x$height');
    }
    final image = YuvImageImpl.allocate(format, width, height);
    image._setRgbaBytes(bytes);
    return image;
  }

  final YuvImageState _state;

  @override
  int get internalRevision => _state.revision;

  @override
  void bumpInternalRevision() => _state.bumpRevision();

  @override
  YuvPixelFormat get format => _state.format;

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
  YuvImage copy() => YuvImageImpl(
    _state.format,
    width,
    height,
    yPixelStride: _state.yPixelStride,
    uvPixelStride: _state.uvPixelStride,
    allowLargerNvChromaStride: _state.allowsLargerNvChromaStride,
    planes: _state.copiedPlanes(),
    layout: YuvPlaneLayout.preserve,
  );

  @override
  Future<void> encodeTo(Sink<List<int>> sink) async {
    sink.add(_getBytes());
  }

  @override
  String toString() {
    return '$runtimeType(format: ${_state.format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  void _setRgbaBytes(Uint8List bytes) {
    if (bytes.length != width * height * 4) {
      return;
    }

    if (_state.format == YuvPixelFormat.bgra8888) {
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
    if (_state.format == YuvPixelFormat.bgra8888) {
      return Uint8List.fromList(yPlane.bytes);
    }
    return Uint8List(width * height * 4);
  }
}
