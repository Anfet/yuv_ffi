// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/loader/impl/loader_web.dart' as loader;
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/yuv/impl/web/abi/yuv_abi_v1_web_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_image_transport.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_legacy_dispatch.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';
import 'package:yuv_ffi/src/yuv_capabilities.dart';

import 'yuv_abi_v1_dispatch_web.dart';

/// Web backend implementation, dispatching to the `yuv_ffi` WASM module.
///
/// Format, geometry, plane, copy and serialization state lives in the shared
/// [YuvImageState] this holds by composition (YUV-28); what remains here is the
/// WASM dispatch itself.
///
/// Every operation goes through the ABI v1 transport (YUV-51), the same way the
/// IO backend does (YUV-50): the public method validates and decides the
/// destination shape, [YuvAbiV1WebRunner] stages descriptors in WASM linear
/// memory and invokes exactly one `yuv_*_v1` symbol, and the result is published
/// in a single step. A non-zero status throws out of the runner before any byte
/// is read back, so a failed operation leaves this image's bytes, metadata and
/// revision untouched.
///
/// Sharing the ABI and the transport does not make Web a feature-complete peer
/// of the native backend: the operations below are the ones ABI v1 implements
/// for Web, and Web remains a partial WASM backend.
class YuvImageImpl implements YuvImage, YuvRevisionAware, YuvLegacyDispatchAdapter {
  // I420 stores U and V as separate single-byte-per-sample planes, so the
  // default pixelStride is 1, unlike NV21's interleaved (U, V) pairs.
  YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
    : this(YuvFileFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
    : this(YuvFileFormat.nv21, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  /// Truthfully named replacement for [YuvImageImpl.nv21]: same semi-planar
  /// storage, same default interleaved chroma pixel stride of 2.
  ///
  /// Unlike [YuvImageImpl.nv21], an explicit [uvPixelStride] above the packed
  /// pair minimum is honored as a real pixel gap rather than being folded into
  /// the legacy constructor's own validation; see
  /// [YuvGeometry.validateImage]'s `allowLargerNvChromaStride`.
  YuvImageImpl.nv12(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
    : _state = YuvImageState(
        YuvFileFormat.nv21,
        width,
        height,
        yPixelStride: yPixelStride,
        uvPixelStride: uvPixelStride,
        planes: planes,
        allowLargerNvChromaStride: true,
      );

  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes})
    : this(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, uvPixelStride: 1, planes: planes);

  YuvImageImpl(YuvFileFormat format, int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
    : _state = YuvImageState(format, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

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
  factory YuvImageImpl.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) {
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
    planes: _state.copiedPlanes(blank: blank),
  );

  @override
  Future<void> encodeTo(Sink<List<int>> sink) async {
    sink.add(_state.encode());
  }

  @override
  Future<void> legacyLoad(Stream<List<int>> stream) => _state.decodeAndReplace(stream);

  @override
  String toString() {
    return '$runtimeType(format: ${_state.format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  @override
  YuvImage legacyCrop(ui.Rect rect) {
    final region = _state.clampCrop(rect);
    if (region == null) {
      return this;
    }

    final result = YuvAbiV1WebRunner.crop(
      module: _requireModule(),
      source: _sourceFrame(),
      left: region.left,
      top: region.top,
      width: region.width,
      height: region.height,
    );
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

  @override
  YuvImage legacyFlipHorizontal() => _applyInPlace(
    YuvAbiV1WebRunner.flip(module: _requireModule(), source: _sourceFrame(), direction: yuvFlipHorizontal, operation: YuvOperation.flipHorizontal),
  );

  @override
  YuvImage legacyFlipVertical() => _applyInPlace(
    YuvAbiV1WebRunner.flip(module: _requireModule(), source: _sourceFrame(), direction: yuvFlipVertical, operation: YuvOperation.flipVertical),
  );

  @override
  void legacyFromRgba8888(Uint8List bytes) {
    _state.validateRgba8888Length(bytes.length);

    // RGBA is a convert-only source format (section 11), so this is a
    // conversion into this image's own format rather than one of the effect
    // paths. The destination keeps this image's geometry.
    final result = YuvAbiV1WebRunner.convert(
      module: _requireModule(),
      source: YuvAbiV1ImageTransport.rgbaSource(bytes: bytes, width: width, height: height),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: _state.format, width: width, height: height),
    );
    YuvAbiV1ImageTransport.applyTo(result: result, planes: _state.planes, format: _state.format, width: width, height: height);
    _state.bumpRevision();
  }

  @override
  YuvImage legacyRotate(YuvImageRotation rotation) {
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);
    if (degrees == 0) {
      return this;
    }

    final result = YuvAbiV1WebRunner.rotate(module: _requireModule(), source: _sourceFrame(), rotationDegrees: degrees);
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

  @override
  YuvImage legacyBlackWhite() => _applyInPlace(YuvAbiV1WebRunner.blackWhite(module: _requireModule(), source: _sourceFrame()));

  @override
  YuvImage legacyGrayscale() => _applyInPlace(YuvAbiV1WebRunner.grayscale(module: _requireModule(), source: _sourceFrame()));

  @override
  YuvImage legacyNegate() => _applyInPlace(YuvAbiV1WebRunner.negate(module: _requireModule(), source: _sourceFrame()));

  @override
  YuvImage legacyGaussianBlur({required int radius, required double sigma}) {
    YuvGeometry.validateBlurRadius(radius);
    if (radius == 0) {
      return this;
    }
    return _applyInPlace(
      YuvAbiV1WebRunner.blur(module: _requireModule(), kind: YuvAbiV1BlurKind.gaussian, source: _sourceFrame(), radius: radius, sigma: sigma),
    );
  }

  @override
  YuvImage legacyBoxBlur({required int radius, ui.Rect? rect}) => _blur(YuvAbiV1BlurKind.box, radius: radius, rect: rect);

  @override
  YuvImage legacyMeanBlur({required int radius, ui.Rect? rect}) => _blur(YuvAbiV1BlurKind.mean, radius: radius, rect: rect);

  @override
  YuvImage legacyConvertTo(YuvFileFormat target) => _convertTo(target);

  @override
  YuvImage legacySwapNv() {
    // Deprecated compatibility path (section 14, Q1): convert non-NV input to
    // canonical NV12 first, then swap the chroma sample values.
    //
    // Both steps run on local drafts and nothing is published until both have
    // succeeded. Converting through applyFormat() first would publish the
    // converted image before the swap was attempted, so a chroma swap that
    // returned a non-zero status would leave the receiver converted -- a
    // visible partial result, which section 13 forbids. That is also why the
    // revision is not snapshotted and restored here any more: there is only
    // ever one publish, which advances it exactly once.
    final Object module = _requireModule();
    final YuvFileFormat sourceFormat = _state.format;
    final YuvAbiV1FrameInput swapSource;
    if (sourceFormat == YuvFileFormat.nv21) {
      swapSource = _sourceFrame();
    } else {
      final converted = YuvAbiV1WebRunner.convert(
        module: module,
        source: _sourceFrame(),
        destinationLayout: YuvAbiV1ImageTransport.destination(format: YuvFileFormat.nv21, width: width, height: height),
      );
      swapSource = YuvAbiV1ImageTransport.source(
        format: YuvFileFormat.nv21,
        width: width,
        height: height,
        planes: YuvAbiV1ImageTransport.planesOf(result: converted, format: YuvFileFormat.nv21, width: width, height: height),
      );
    }

    final result = YuvAbiV1WebRunner.chromaSwap(module: module, source: swapSource);

    // A receiver that was already NV21 keeps its own chroma layout, padding
    // included; one that had to be converted adopts the tight planes the
    // conversion produced, since its previous layout described a different
    // format.
    final List<YuvPlane> swapped = sourceFormat == YuvFileFormat.nv21
        ? _state.copiedPlanes()
        : YuvAbiV1ImageTransport.planesOf(result: result, format: YuvFileFormat.nv21, width: width, height: height);
    if (sourceFormat == YuvFileFormat.nv21) {
      YuvAbiV1ImageTransport.applyTo(result: result, planes: swapped, format: YuvFileFormat.nv21, width: width, height: height);
    }

    _state.replace(format: YuvFileFormat.nv21, width: width, height: height, planes: swapped);
    return this;
  }

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgraBytes(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  /// The ABI v1 symbols the currently loaded WASM module does not export.
  ///
  /// Empty when the module carries the whole ABI v1 surface. The runner asks
  /// the same question before every operation, so a partially exported build is
  /// a named, diagnosable failure instead of an opaque error inside a WASM call.
  /// The names come from the shared manifest in
  /// `shared/yuv_abi_v1_symbols.dart`, so they cannot drift from the ones the
  /// native runner dispatches.
  ///
  /// Throws [StateError] when no module is loaded at all.
  List<String> debugMissingAbiV1Symbols() => YuvAbiV1WebDispatch.missingFrom(_requireModule());

  /// This image as an ABI v1 source descriptor, read through its own strides.
  YuvAbiV1FrameInput _sourceFrame() => YuvAbiV1ImageTransport.source(format: _state.format, width: width, height: height, planes: _state.planes);

  /// Publishes [result] into this image's existing planes and advances the
  /// revision once.
  ///
  /// For every operation that keeps this image's format and geometry. The
  /// planes keep the layout they were constructed with, so padding survives;
  /// the write happens only after the runner returned successfully, so a
  /// failed WASM call has already thrown with nothing published.
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

    return _applyInPlace(YuvAbiV1WebRunner.blur(module: _requireModule(), kind: kind, source: _sourceFrame(), radius: radius, region: region));
  }

  /// Replaces this image with itself converted to [target].
  ///
  /// A conversion to the format this image already has is a no-op rather than
  /// a deep copy through WASM: the public contract is in-place and the receiver
  /// already holds the requested representation.
  YuvImage _convertTo(YuvFileFormat target) {
    if (_state.format == target) {
      return this;
    }

    final result = YuvAbiV1WebRunner.convert(
      module: _requireModule(),
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

  Object _requireModule() {
    final module = YuvWasmLoader.moduleIfInitialized;
    if (module == null) {
      throw StateError(
        'YUV WASM module is not initialized. '
        'Call YuvFfi.initialize() before image operations on Web.',
      );
    }
    return module.rawModule;
  }

  // -- 0.4.0 `apply*`/`to*` surface ------------------------------------------

  /// The currently loaded backend's capability snapshot.
  ///
  /// `null` before [YuvFfi.initialize] has completed successfully, mirroring
  /// [YuvWasmLoader.moduleIfInitialized]'s own post-initialization cache. A
  /// capability check against a `null` snapshot is unconditionally
  /// unsupported: Web never reports success through a silent no-op (section
  /// 2, contract 7), including before initialization.
  YuvCapabilities? get _capabilities => loader.capabilitiesIfInitialized;

  void _requireCapability(YuvOperation operation, {required YuvPixelFormat sourceFormat, YuvPixelFormat? destinationFormat}) {
    final capabilities = _capabilities;
    if (capabilities == null) {
      throw UnsupportedError('$operation is not supported: the Web backend has not finished YuvFfi.initialize() yet.');
    }
    yuvRequireCapability(capabilities, operation, sourceFormat: sourceFormat, destinationFormat: destinationFormat);
  }

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) {
    _requireCapability(YuvOperation.convert, sourceFormat: _state.format.pixelFormat, destinationFormat: _state.format.pixelFormat);
    _state.validateRgba8888Length(bytes.length);
    legacyFromRgba8888(bytes);
    return this;
  }

  @override
  YuvImage applyGrayscale() {
    _requireCapability(YuvOperation.grayscale, sourceFormat: _state.format.pixelFormat);
    return legacyGrayscale();
  }

  @override
  YuvImage applyBlackWhite() {
    _requireCapability(YuvOperation.blackWhite, sourceFormat: _state.format.pixelFormat);
    return legacyBlackWhite();
  }

  @override
  YuvImage applyNegate() {
    _requireCapability(YuvOperation.negate, sourceFormat: _state.format.pixelFormat);
    return legacyNegate();
  }

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) {
    _requireCapability(YuvOperation.gaussianBlur, sourceFormat: _state.format.pixelFormat);
    return legacyGaussianBlur(radius: radius, sigma: sigma);
  }

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) {
    _requireCapability(YuvOperation.meanBlur, sourceFormat: _state.format.pixelFormat);
    return legacyMeanBlur(radius: radius, rect: region);
  }

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) {
    _requireCapability(YuvOperation.boxBlur, sourceFormat: _state.format.pixelFormat);
    return legacyBoxBlur(radius: radius, rect: region);
  }

  @override
  YuvImage applyCrop(ui.Rect region) {
    _requireCapability(YuvOperation.crop, sourceFormat: _state.format.pixelFormat);
    return legacyCrop(region);
  }

  @override
  YuvImage applyFlipHorizontal() {
    _requireCapability(YuvOperation.flipHorizontal, sourceFormat: _state.format.pixelFormat);
    return legacyFlipHorizontal();
  }

  @override
  YuvImage applyFlipVertical() {
    _requireCapability(YuvOperation.flipVertical, sourceFormat: _state.format.pixelFormat);
    return legacyFlipVertical();
  }

  @override
  YuvImage applyRotation(YuvImageRotation rotation) {
    _requireCapability(YuvOperation.rotate, sourceFormat: _state.format.pixelFormat);
    return legacyRotate(rotation);
  }

  @override
  YuvImage applyFormat(YuvPixelFormat targetFormat) {
    _requireCapability(YuvOperation.convert, sourceFormat: _state.format.pixelFormat, destinationFormat: targetFormat);
    return legacyConvertTo(targetFormat.legacy);
  }

  @override
  YuvImage applyChromaSwap() {
    if (_state.format != YuvFileFormat.nv21) {
      throw UnsupportedError('applyChromaSwap is only supported for NV12 images, not ${_state.format}.');
    }
    _requireCapability(YuvOperation.chromaSwap, sourceFormat: _state.format.pixelFormat);
    return _applyInPlace(YuvAbiV1WebRunner.chromaSwap(module: _requireModule(), source: _sourceFrame()));
  }

  @override
  YuvImage cropped(ui.Rect region) {
    _requireCapability(YuvOperation.crop, sourceFormat: _state.format.pixelFormat);
    final clamped = _state.clampCrop(region);
    if (clamped == null) {
      return copy();
    }
    final result = YuvAbiV1WebRunner.crop(
      module: _requireModule(),
      source: _sourceFrame(),
      left: clamped.left,
      top: clamped.top,
      width: clamped.width,
      height: clamped.height,
    );
    return YuvImageImpl(
      _state.format,
      clamped.width,
      clamped.height,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: clamped.width, height: clamped.height),
    );
  }

  @override
  YuvImage rotated(YuvImageRotation rotation) {
    _requireCapability(YuvOperation.rotate, sourceFormat: _state.format.pixelFormat);
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);
    if (degrees == 0) {
      return copy();
    }
    final result = YuvAbiV1WebRunner.rotate(module: _requireModule(), source: _sourceFrame(), rotationDegrees: degrees);
    final int rotatedWidth = rotation.swapSize ? height : width;
    final int rotatedHeight = rotation.swapSize ? width : height;
    return YuvImageImpl(
      _state.format,
      rotatedWidth,
      rotatedHeight,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: _state.format, width: rotatedWidth, height: rotatedHeight),
    );
  }

  @override
  YuvImage toI420() => _toIndependent(YuvFileFormat.i420, YuvOperation.convert);

  @override
  YuvImage toNv12() => _toIndependent(YuvFileFormat.nv21, YuvOperation.convert);

  @override
  YuvImage toBgra() => _toIndependent(YuvFileFormat.bgra8888, YuvOperation.convert);

  /// Shared body of [toI420]/[toNv12]/[toBgra]: independent conversion that
  /// never mutates or aliases the receiver, even for a same-format request.
  YuvImage _toIndependent(YuvFileFormat target, YuvOperation operation) {
    _requireCapability(operation, sourceFormat: _state.format.pixelFormat, destinationFormat: target.pixelFormat);
    if (_state.format == target) {
      return copy();
    }
    final result = YuvAbiV1WebRunner.convert(
      module: _requireModule(),
      source: _sourceFrame(),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: target, width: width, height: height),
    );
    return YuvImageImpl(
      target,
      width,
      height,
      planes: YuvAbiV1ImageTransport.planesOf(result: result, format: target, width: width, height: height),
    );
  }

  @override
  Uint8List toBytes() => _getBytes();

  @override
  Uint8List toBgraBytes() {
    if (_state.format == YuvFileFormat.bgra8888) {
      // Shared with the native reference through YuvImageState.packedBgraBytes,
      // which is what keeps the two backends byte-identical here: it walks the
      // plane through its own rowStride and pixelStride, so both row padding
      // and a per-pixel gap (pixelStride > 4, REL-12) are excluded the same way
      // on both backends. See that method's doc.
      return _state.packedBgraBytes();
    }

    final result = YuvAbiV1WebRunner.convert(
      module: _requireModule(),
      source: _sourceFrame(),
      destinationLayout: YuvAbiV1ImageTransport.destination(format: YuvFileFormat.bgra8888, width: width, height: height),
    );
    // The BGRA destination layout is tight by construction, so its single
    // plane already is the documented `width * height * 4` buffer.
    return result.planes[0];
  }
}
