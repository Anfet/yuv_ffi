// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader;
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_image_transport.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_layout.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';

/// Native backend implementation, dispatching to the `yuv_ffi` C library.
///
/// Format, geometry, plane, copy, and serialization state lives in the shared
/// [YuvImageState]; this class handles FFI dispatch.
///
/// Each operation validates its arguments and decides the destination shape.
/// [YuvAbiV1Runner] stages descriptors and invokes one `yuv_*_v1` symbol. The
/// result is published in one step. A non-zero native status throws before
/// the runner reads any destination byte, so a failed operation leaves this
/// image's bytes, metadata and revision untouched.
class YuvImageImpl implements YuvImage, YuvRevisionAware {
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

  /// Creates semi-planar NV12 storage with interleaved chroma pixel stride 2.
  ///
  /// An explicit [uvPixelStride] above the packed pair minimum is honored as a
  /// real pixel gap; operations preserve and validate that declared layout.
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

  /// Creates a BGRA image, optionally adopting a caller-supplied plane.
  ///
  /// [layout] defaults to [YuvPlaneLayout.packed], which repacks a padded
  /// caller-supplied plane to `rowStride == width * 4` during construction.
  /// Pass [YuvPlaneLayout.preserve] to keep the caller's `rowStride` and
  /// `pixelStride`. This factory and the generic
  /// `YuvImage(YuvPixelFormat.bgra8888, ...)` constructor share the same
  /// validation and copy contract.
  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes, YuvPlaneLayout layout = YuvPlaneLayout.packed})
    : this(YuvPixelFormat.bgra8888, width, height, yPixelStride: 4, planes: planes, layout: layout);

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
  ///
  /// Always produces tight planes: no caller-supplied layout to preserve, so
  /// this never takes a `planes` argument the way the named format factories
  /// do.
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
  factory YuvImageImpl.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) {
    final image = YuvImageImpl.allocate(format, width, height);
    image._setRgbaBytes(bytes);
    return image;
  }

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
    planes: _state.copiedPlanes(),
    yPixelStride: _state.yPixelStride,
    uvPixelStride: _state.uvPixelStride,
    allowLargerNvChromaStride: _state.allowsLargerNvChromaStride,
    layout: YuvPlaneLayout.preserve,
  );

  @override
  Future<void> encodeTo(Sink<List<int>> sink) async {
    sink.add(_state.encode());
  }

  @override
  String toString() {
    return '${_state.format.name}, $width:$height / ${planes.length}';
  }

  YuvImage _applyCrop(ui.Rect rect) {
    final region = _state.clampCrop(rect);
    if (region == null) {
      return this;
    }

    final result = YuvAbiV1Runner.crop(source: _sourceFrame(), left: region.left, top: region.top, width: region.width, height: region.height);
    // Crop changes geometry, so the receiver adopts a whole new plane set
    // rather than writing into the planes it had: there is no prior padding
    // that could still describe this image.
    _state.replace(
      format: _state.format,
      width: region.width,
      height: region.height,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: region.width, height: region.height),
    );
    return this;
  }

  YuvImage _applyFlipHorizontal() =>
      _applyInPlace(YuvAbiV1Runner.flip(source: _sourceFrame(), direction: yuvFlipHorizontal, operation: YuvOperation.flipHorizontal));

  YuvImage _applyFlipVertical() =>
      _applyInPlace(YuvAbiV1Runner.flip(source: _sourceFrame(), direction: yuvFlipVertical, operation: YuvOperation.flipVertical));

  void _setRgbaBytes(Uint8List bytes) {
    _state.validateRgba8888Length(bytes.length);

    // Converts the RGBA8888 source to this image's format while preserving its
    // geometry.
    final result = YuvAbiV1Runner.convert(
      source: YuvAbiV1ImageTransport.rgbaSource(bytes: bytes, width: width, height: height),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: _state.format, width: width, height: height),
    );
    YuvAbiV1ImageTransport.applyTo(result: result, planes: _state.planes, format: _state.format, width: width, height: height);
    _state.bumpRevision();
  }

  YuvImage _applyRotation(YuvImageRotation rotation) {
    // No multiple-of-90 assert: YuvImageRotation is an enum whose only values
    // are 0, 90, 180 and 270, so the check could never fail. Web never had it.
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);

    if (degrees == 0) {
      return this;
    }

    final result = YuvAbiV1Runner.rotate(source: _sourceFrame(), rotationDegrees: degrees);
    final int rotatedWidth = rotation.swapSize ? height : width;
    final int rotatedHeight = rotation.swapSize ? width : height;
    _state.replace(
      format: _state.format,
      width: rotatedWidth,
      height: rotatedHeight,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: rotatedWidth, height: rotatedHeight),
    );
    return this;
  }

  YuvImage _applyBlackWhite() => _applyInPlace(YuvAbiV1Runner.blackWhite(source: _sourceFrame()));

  YuvImage _applyGrayscale() => _applyInPlace(YuvAbiV1Runner.grayscale(source: _sourceFrame()));

  YuvImage _applyNegate() => _applyInPlace(YuvAbiV1Runner.negate(source: _sourceFrame()));

  YuvImage _applyGaussianBlur({required int radius, required double sigma}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }
    return _applyInPlace(YuvAbiV1Runner.blur(kind: YuvAbiV1BlurKind.gaussian, source: _sourceFrame(), radius: radius, sigma: sigma));
  }

  YuvImage _applyBoxBlur({required int radius, ui.Rect? rect}) => _blur(YuvAbiV1BlurKind.box, radius: radius, rect: rect);

  YuvImage _applyMeanBlur({required int radius, ui.Rect? rect}) => _blur(YuvAbiV1BlurKind.mean, radius: radius, rect: rect);

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgraBytes(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  /// This image as an ABI v1 source descriptor, read through its own strides.
  YuvAbiV1FrameInput _sourceFrame() => YuvAbiV1ImageTransport.source(format: _state.format, width: width, height: height, planes: _state.planes);

  /// Publishes [result] into this image's existing planes and advances the
  /// revision once.
  ///
  /// For every operation that keeps this image's format and geometry. The
  /// planes keep the layout they were constructed with, so padding survives;
  /// the write happens only after the runner returned successfully, so a
  /// native failure has already thrown with nothing published.
  YuvImage _applyInPlace(YuvAbiV1FrameResult result) {
    YuvAbiV1ImageTransport.applyTo(result: result, planes: _state.planes, format: _state.format, width: width, height: height);
    _state.bumpRevision();
    return this;
  }

  /// Shared body of [boxBlur] and [meanBlur], which differ only in kernel.
  ///
  /// [gaussianBlur] is deliberately not routed through here: it takes `sigma`
  /// instead of a `rect`, so it shares no parameter handling with these two.
  YuvImage _blur(YuvAbiV1BlurKind kind, {required int radius, required ui.Rect? rect}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }

    final YuvAbiV1Region? region;
    if (rect == null) {
      region = null;
    } else {
      final clamped = _state.clampCrop(rect);
      if (clamped == null) {
        // An empty or fully outside rect selects no pixel. A disabled region
        // would mean "whole frame" to the ABI, so this returns instead of
        // blurring everything.
        return this;
      }
      region = YuvAbiV1Region(left: clamped.left, top: clamped.top, right: clamped.left + clamped.width, bottom: clamped.top + clamped.height);
    }

    return _applyInPlace(YuvAbiV1Runner.blur(kind: kind, source: _sourceFrame(), radius: radius, region: region));
  }

  /// Replaces this image with itself converted to [target].
  ///
  /// A conversion to the format this image already has is a no-op rather than
  /// a deep copy through native: the public contract is in-place and the
  /// receiver already holds the requested representation.
  YuvImage _convertTo(YuvPixelFormat target) {
    if (_state.format == target) {
      return this;
    }

    final result = YuvAbiV1Runner.convert(
      source: _sourceFrame(),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: target, width: width, height: height),
    );
    _state.replace(
      format: target,
      width: width,
      height: height,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: target, width: width, height: height),
    );
    return this;
  }

  // -- `apply*`/`to*` processing surface -------------------------------------

  /// The currently loaded backend's capability snapshot.
  ///
  /// `null` before [YuvFfi.initialize] has completed successfully, mirroring
  /// [loader.library]/[loader.ffiBingings]'s own post-initialization cache
  /// (`lib/src/loader/impl/loader_io.dart`). A capability check against a
  /// `null` snapshot is unconditionally unsupported: an image created and used
  /// before initialization must fail closed, not assume every operation is
  /// available.
  YuvCapabilities? get _capabilities => loader.capabilitiesIfInitialized;

  void _requireCapability(YuvOperation operation, {required YuvPixelFormat sourceFormat, YuvPixelFormat? destinationFormat}) {
    final capabilities = _capabilities;
    if (capabilities == null) {
      throw UnsupportedError('YuvFfi.initialize() must complete before $operation can run; backend capability has not been determined yet.');
    }
    yuvRequireCapability(capabilities, operation, sourceFormat: sourceFormat, destinationFormat: destinationFormat);
  }

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) {
    _requireCapability(YuvOperation.convert, sourceFormat: _state.format, destinationFormat: _state.format);
    _state.validateRgba8888Length(bytes.length);
    _setRgbaBytes(bytes);
    return this;
  }

  @override
  YuvImage applyGrayscale() {
    _requireCapability(YuvOperation.grayscale, sourceFormat: _state.format);
    return _applyGrayscale();
  }

  @override
  YuvImage applyBlackWhite() {
    _requireCapability(YuvOperation.blackWhite, sourceFormat: _state.format);
    return _applyBlackWhite();
  }

  @override
  YuvImage applyNegate() {
    _requireCapability(YuvOperation.negate, sourceFormat: _state.format);
    return _applyNegate();
  }

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) {
    _requireCapability(YuvOperation.gaussianBlur, sourceFormat: _state.format);
    return _applyGaussianBlur(radius: radius, sigma: sigma);
  }

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) {
    _requireCapability(YuvOperation.meanBlur, sourceFormat: _state.format);
    return _applyMeanBlur(radius: radius, rect: region);
  }

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) {
    _requireCapability(YuvOperation.boxBlur, sourceFormat: _state.format);
    return _applyBoxBlur(radius: radius, rect: region);
  }

  @override
  YuvImage applyCrop(ui.Rect region) {
    _requireCapability(YuvOperation.crop, sourceFormat: _state.format);
    return _applyCrop(region);
  }

  @override
  YuvImage applyFlipHorizontal() {
    _requireCapability(YuvOperation.flipHorizontal, sourceFormat: _state.format);
    return _applyFlipHorizontal();
  }

  @override
  YuvImage applyFlipVertical() {
    _requireCapability(YuvOperation.flipVertical, sourceFormat: _state.format);
    return _applyFlipVertical();
  }

  @override
  YuvImage applyRotation(YuvImageRotation rotation) {
    _requireCapability(YuvOperation.rotate, sourceFormat: _state.format);
    return _applyRotation(rotation);
  }

  @override
  YuvImage applyFormat(YuvPixelFormat targetFormat) {
    _requireCapability(YuvOperation.convert, sourceFormat: _state.format, destinationFormat: targetFormat);
    return _convertTo(targetFormat);
  }

  @override
  YuvImage applyChromaSwap() {
    if (_state.format != YuvPixelFormat.nv12) {
      // Reject non-NV12 input before capability lookup, allocation, or dispatch.
      throw UnsupportedError('applyChromaSwap is only supported for NV12 images, not ${_state.format}.');
    }
    _requireCapability(YuvOperation.chromaSwap, sourceFormat: _state.format);
    return _applyInPlace(YuvAbiV1Runner.chromaSwap(source: _sourceFrame()));
  }

  @override
  YuvImage cropped(ui.Rect region) {
    _requireCapability(YuvOperation.crop, sourceFormat: _state.format);
    final clamped = _state.clampCrop(region);
    if (clamped == null) {
      // Return an independent copy even when the crop selects no pixels.
      return copy();
    }
    final result = YuvAbiV1Runner.crop(source: _sourceFrame(), left: clamped.left, top: clamped.top, width: clamped.width, height: clamped.height);
    return YuvImageImpl(
      _state.format,
      clamped.width,
      clamped.height,
      allowLargerNvChromaStride: _state.allowsLargerNvChromaStride,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: clamped.width, height: clamped.height),
      layout: YuvPlaneLayout.preserve,
    );
  }

  @override
  YuvImage rotated(YuvImageRotation rotation) {
    _requireCapability(YuvOperation.rotate, sourceFormat: _state.format);
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);
    if (degrees == 0) {
      // Same reasoning as cropped(): rotation0 is still a semantic no-op that
      // must not alias the source.
      return copy();
    }
    final result = YuvAbiV1Runner.rotate(source: _sourceFrame(), rotationDegrees: degrees);
    final int rotatedWidth = rotation.swapSize ? height : width;
    final int rotatedHeight = rotation.swapSize ? width : height;
    return YuvImageImpl(
      _state.format,
      rotatedWidth,
      rotatedHeight,
      allowLargerNvChromaStride: _state.allowsLargerNvChromaStride,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: rotatedWidth, height: rotatedHeight),
      layout: YuvPlaneLayout.preserve,
    );
  }

  @override
  YuvImage toI420() => _toIndependent(YuvPixelFormat.i420, YuvOperation.convert);

  @override
  YuvImage toNv12() => _toIndependent(YuvPixelFormat.nv12, YuvOperation.convert);

  @override
  YuvImage toBgra() => _toIndependent(YuvPixelFormat.bgra8888, YuvOperation.convert);

  /// Shared body of [toI420]/[toNv12]/[toBgra]: independent conversion that
  /// never mutates or aliases the receiver, even for a same-format request.
  YuvImage _toIndependent(YuvPixelFormat target, YuvOperation operation) {
    _requireCapability(operation, sourceFormat: _state.format, destinationFormat: target);
    if (_state.format == target) {
      // Return an independent copy without changing the source revision.
      return copy();
    }
    final result = YuvAbiV1Runner.convert(
      source: _sourceFrame(),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: target, width: width, height: height),
    );
    return YuvImageImpl(
      target,
      width,
      height,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: target, width: width, height: height),
      layout: YuvPlaneLayout.preserve,
    );
  }

  @override
  Uint8List toBytes() => _getBytes();

  @override
  Uint8List toBgraBytes() {
    if (_state.format == YuvPixelFormat.bgra8888) {
      return _state.packedBgraBytes();
    }

    final result = YuvAbiV1Runner.convert(
      source: _sourceFrame(),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: YuvPixelFormat.bgra8888, width: width, height: height),
    );
    // The BGRA destination layout is tight by construction, so its single
    // plane already is the documented `width * height * 4` buffer.
    return result.planes[0];
  }
}
