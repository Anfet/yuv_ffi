// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/web/impl/js_util_compat_web.dart' as js_util;
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_state.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

import 'yuv_abi_v1_dispatch_web.dart';

/// Web backend implementation backed by WASM exports where available.
///
/// Format, geometry, plane, copy and serialization state lives in the shared
/// [YuvImageState] this holds by composition (YUV-28); what remains here is the
/// WASM dispatch itself. Sharing that state does not make Web a feature-complete
/// peer of the native backend -- Web remains a partial WASM backend.
class YuvImageImpl implements YuvImage, YuvRevisionAware {
  // I420 stores U and V as separate single-byte-per-sample planes, so the
  // default pixelStride is 1, unlike NV21's interleaved (U, V) pairs.
  YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.i420, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.nv21, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes})
      : this(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, uvPixelStride: 1, planes: planes);

  YuvImageImpl(YuvFileFormat format, int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes})
      : _state = YuvImageState(format, width, height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride, planes: planes);

  static const int _bytesPerPixel = 4;
  static const int _yuvDefFieldsCount = 9;
  static const int _yuvDefSizeBytes = _yuvDefFieldsCount * 4;

  final YuvImageState _state;

  @override
  int get internalRevision => _state.revision;

  @override
  void bumpInternalRevision() => _state.bumpRevision();

  @override
  YuvFileFormat get format => _state.format;

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
  YuvPlane get y => _state.yPlane;

  @override
  YuvPlane? get u => _state.u;

  @override
  YuvPlane? get v => _state.v;

  @override
  ui.Size get size => _state.size;

  @override
  Uint8List getBytes() => _state.getBytes();

  @override
  YuvImage copy({bool blank = false}) => YuvImageImpl(
        format,
        width,
        height,
        yPixelStride: _state.yPixelStride,
        uvPixelStride: _state.uvPixelStride,
        planes: _state.copiedPlanes(blank: blank),
      );

  @override
  Future<void> save(Sink<List<int>> sink) async {
    sink.add(_state.encode());
  }

  @override
  Future<void> load(Stream<List<int>> stream) => _state.decodeAndReplace(stream);

  @override
  String toString() {
    return '$runtimeType(format: ${format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  @override
  YuvImage blackwhite() {
    _callInPlaceUnary(_symbolForFormat(i420: 'yuv420_blackwhite', nv21: 'nv21_blackwhite', bgra: 'bgra8888_blackwhite'));
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    YuvGeometry.validateBlurRadius(radius);
    _state.requireTightBgraFor('gaussianBlur');
    _callInPlaceBlur(_symbolForFormat(i420: 'yuv420_gaussblur', nv21: 'nv21_gaussian_blur', bgra: 'bgra8888_gaussian_blur'), radius, sigma);
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
    YuvGeometry.validateBlurRadius(radius);
    _state.requireTightBgraFor('boxBlur');
    _callInPlaceBlurWithRect(_symbolForFormat(i420: 'yuv420_box_blur', nv21: 'nv21_box_blur', bgra: 'bgra8888_box_blur'), radius, rect);
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
    YuvGeometry.validateBlurRadius(radius);
    _state.requireTightBgraFor('meanBlur');
    _callInPlaceBlurWithRect(_symbolForFormat(i420: 'yuv420_mean_blur', nv21: 'nv21_mean_blur', bgra: 'bgra8888_mean_blur'), radius, rect);
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage swapNv() {
    // A conversion to NV21 bumps the revision on its own. Snapshot it here so
    // one public swapNv() advances the counter exactly once, whatever path it
    // took to get there.
    final revisionBefore = _state.revision;
    final source = format == YuvFileFormat.nv21 ? this : toYuvNv21();

    final rawModule = _requireModule();
    final srcAlloc = _WasmYuvAlloc.fromImage(rawModule, source as YuvImageImpl);
    // nvXX_to_nvYY takes a single stride for both buffers, so the destination
    // must have exactly the source layout. Allocating a tight destination for a
    // padded source made the call read and write at mismatched offsets.
    final dst = YuvImageImpl.nv21(
      source.width,
      source.height,
      planes: <YuvPlane>[
        source.yPlane.copy(),
        YuvPlane(source.uPlane.height, source.uPlane.rowStride, source.uPlane.pixelStride),
      ],
    );
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      // nvXX_to_nvYY swaps interleaved chroma ordering in UV buffer.
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        'nvXX_to_nvYY',
        'void',
        <String>['number', 'number', 'number', 'number', 'number'],
        <Object?>[srcAlloc.uPtr, dstAlloc.uPtr, source.width, source.height, source.uPlane.rowStride],
      ]);
      // Y plane is unchanged; copy it directly.
      _heapWrite(rawModule, dstAlloc.yPtr, source.yPlane.bytes);
      dstAlloc.copyBack();
      _state.replaceFromRevision(
        format: dst.format,
        width: dst.width,
        height: dst.height,
        planes: dst.planes.map((p) => p.copy()).toList(growable: false),
        revision: revisionBefore,
      );
      return this;
    } finally {
      srcAlloc.dispose();
      dstAlloc.dispose();
    }
  }

  @override
  YuvImage toYuvNv21() {
    if (format == YuvFileFormat.nv21) {
      return this;
    }
    final dst = YuvImageImpl.nv21(width, height);
    final symbol = switch (format) {
      YuvFileFormat.i420 => 'yuv420_i420_to_nv21',
      YuvFileFormat.bgra8888 => 'bgra8888_to_nv21',
      YuvFileFormat.nv21 => throw StateError('unreachable'),
    };
    _callFormatConversion(symbol: symbol, dst: dst);
    _adoptConverted(dst);
    return this;
  }

  @override
  YuvImage toYuvI420() {
    if (format == YuvFileFormat.i420) {
      return this;
    }
    final dst = YuvImageImpl.i420(width, height);
    final symbol = switch (format) {
      YuvFileFormat.nv21 => 'nv21_to_i420',
      YuvFileFormat.bgra8888 => 'bgra8888_to_i420',
      YuvFileFormat.i420 => throw StateError('unreachable'),
    };
    _callFormatConversion(symbol: symbol, dst: dst);
    _adoptConverted(dst);
    return this;
  }

  @override
  YuvImage toYuvBgra8888() {
    if (format == YuvFileFormat.bgra8888) {
      return this;
    }
    final bytes = toBgra8888();
    final dst = YuvImageImpl.bgra(width, height, planes: [YuvPlane(height, width * _bytesPerPixel, _bytesPerPixel, bytes)]);
    _adoptConverted(dst);
    return this;
  }

  /// Replaces this image's state with [converted]'s, deep-copying its planes so
  /// the two images never share buffers, and advances the revision once.
  void _adoptConverted(YuvImageImpl converted) {
    _state.replace(
      format: converted.format,
      width: converted.width,
      height: converted.height,
      planes: converted.planes.map((p) => p.copy()).toList(growable: false),
    );
  }

  @override
  YuvImage crop(ui.Rect rect) {
    final region = _state.clampCrop(rect);
    if (region == null) {
      return this;
    }

    final symbol = _symbolForFormat(i420: 'yuv420_crop_rect', nv21: 'nv21_crop_rect', bgra: 'bgra8888_crop_rect');
    _callSrcDst(
      symbol: symbol,
      dstWidth: region.width,
      dstHeight: region.height,
      extraArgTypes: const <String>['number', 'number', 'number', 'number'],
      extraArgs: <Object?>[region.left, region.top, region.width, region.height],
    );
    return this;
  }

  @override
  YuvImage flipHorizontally() {
    _callInPlaceUnary(_symbolForFormat(i420: 'yuv420_flip_horizontally', nv21: 'nv21_flip_horizontally', bgra: 'bgra8888_flip_horizontally'));
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage flipVertically() {
    _callInPlaceUnary(_symbolForFormat(i420: 'yuv420_flip_vertically', nv21: 'nv21_flip_vertically', bgra: 'bgra8888_flip_vertically'));
    _state.bumpRevision();
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    _state.validateRgba8888Length(bytes.length);
    if (format == YuvFileFormat.bgra8888 && !_state.isTightBgra) {
      // The shared BGRA C implementation writes a tight destination. Stage in
      // that supported layout and copy only logical samples back so Web and IO
      // preserve identical row/pixel padding.
      final tight = YuvImageImpl.bgra(width, height);
      tight.fromRgba8888(bytes);
      _state.copyTightBgraSamplesFrom(tight.yPlane);
      // This branch writes the planes directly and returns early, so it has to
      // bump the revision itself.
      _state.bumpRevision();
      return;
    }

    _callFromRgba(_symbolForFormat(i420: 'yuv420_from_rgba8888', nv21: 'nv21_from_rgba8888', bgra: 'bgra8888_from_rgba8888'), bytes);
    _state.bumpRevision();
  }

  @override
  YuvImage grayscale() {
    _callInPlaceUnary(_symbolForFormat(i420: 'yuv420_grayscale', nv21: 'nv21_grayscale', bgra: 'bgra8888_grayscale'));
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage negate() {
    _callInPlaceUnary(_symbolForFormat(i420: 'yuv420_negate', nv21: 'nv21_negate', bgra: 'bgra8888_negate'));
    _state.bumpRevision();
    return this;
  }

  @override
  YuvImage rotate(YuvImageRotation rotation) {
    final int degrees = YuvImageState.normalizeRotationDegrees(rotation.degrees);
    if (degrees == 0) {
      return this;
    }
    final dstWidth = rotation.swapSize ? height : width;
    final dstHeight = rotation.swapSize ? width : height;
    final symbol = _symbolForFormat(i420: 'yuv420_rotate', nv21: 'nv21_rotate', bgra: 'bgra8888_rotate');
    _callSrcDst(symbol: symbol, dstWidth: dstWidth, dstHeight: dstHeight, extraArgTypes: const <String>['number'], extraArgs: <Object?>[degrees]);
    return this;
  }

  @override
  Uint8List toBgra8888() {
    if (format == YuvFileFormat.bgra8888) {
      // Shared with the native reference through YuvImageState.packedBgraBytes,
      // which is what keeps the two backends byte-identical here -- including
      // the deliberate choice to decide on rowStride alone rather than through
      // YuvGeometry.isTightBgra. See that method's doc.
      return _state.packedBgraBytes();
    }
    return _callToBgra(_symbolForFormat(i420: 'yuv420_to_bgra8888', nv21: 'nv21_to_bgra8888', bgra: 'unused'));
  }

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(toBgra8888(), width, height, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  String _symbolForFormat({required String i420, required String nv21, required String bgra}) {
    return switch (format) {
      YuvFileFormat.i420 => i420,
      YuvFileFormat.nv21 => nv21,
      YuvFileFormat.bgra8888 => bgra,
    };
  }

  void _callInPlaceUnary(String symbol) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    try {
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number'],
        <Object?>[alloc.defPtr],
      ]);
      alloc.copyBack();
    } finally {
      alloc.dispose();
    }
  }

  void _callInPlaceBlur(String symbol, int radius, int sigma) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    try {
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number', 'number', 'number'],
        <Object?>[alloc.defPtr, radius, sigma],
      ]);
      alloc.copyBack();
    } finally {
      alloc.dispose();
    }
  }

  void _callInPlaceBlurWithRect(String symbol, int radius, ui.Rect? rect) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    int rectPtr = 0;
    try {
      if (rect != null) {
        rectPtr = _malloc(rawModule, 16);
        final left = rect.left.toInt();
        final top = rect.top.toInt();
        final right = rect.right.toInt();
        final bottom = rect.bottom.toInt();
        _writeInt32Values(rawModule, rectPtr, <int>[left, top, right, bottom]);
      }
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number', 'number', 'number'],
        <Object?>[alloc.defPtr, radius, rectPtr],
      ]);
      alloc.copyBack();
    } finally {
      if (rectPtr != 0) {
        _free(rawModule, rectPtr);
      }
      alloc.dispose();
    }
  }

  void _callSrcDst({
    required String symbol,
    required int dstWidth,
    required int dstHeight,
    required List<String> extraArgTypes,
    required List<Object?> extraArgs,
  }) {
    final rawModule = _requireModule();
    final srcAlloc = _WasmYuvAlloc.fromImage(rawModule, this);
    final dst = YuvImageImpl(format, dstWidth, dstHeight, yPixelStride: _state.yPixelStride, uvPixelStride: _state.uvPixelStride);
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      final argTypes = <String>['number', 'number', ...extraArgTypes];
      final args = <Object?>[srcAlloc.defPtr, dstAlloc.defPtr, ...extraArgs];
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[symbol, 'void', argTypes, args]);
      dstAlloc.copyBack();
      _state.replace(
        format: format,
        width: dstWidth,
        height: dstHeight,
        planes: dst.planes.map((p) => p.copy()).toList(growable: false),
      );
    } finally {
      srcAlloc.dispose();
      dstAlloc.dispose();
    }
  }

  void _callFormatConversion({required String symbol, required YuvImageImpl dst}) {
    final rawModule = _requireModule();
    final srcAlloc = _WasmYuvAlloc.fromImage(rawModule, this);
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number', 'number'],
        <Object?>[srcAlloc.defPtr, dstAlloc.defPtr],
      ]);
      dstAlloc.copyBack();
    } finally {
      srcAlloc.dispose();
      dstAlloc.dispose();
    }
  }

  void _callFromRgba(String symbol, Uint8List rgba) {
    final rawModule = _requireModule();
    final rgbaPtr = _malloc(rawModule, rgba.length);
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    try {
      _heapWrite(rawModule, rgbaPtr, rgba);
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number', 'number'],
        <Object?>[rgbaPtr, alloc.defPtr],
      ]);
      alloc.copyBack();
    } finally {
      _free(rawModule, rgbaPtr);
      alloc.dispose();
    }
  }

  Uint8List _callToBgra(String symbol) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    final outLength = width * height * _bytesPerPixel;
    final outPtr = _malloc(rawModule, outLength);
    try {
      js_util.callMethod<Object?>(rawModule, 'ccall', <Object?>[
        symbol,
        'void',
        <String>['number', 'number'],
        <Object?>[alloc.defPtr, outPtr],
      ]);
      return _heapRead(rawModule, outPtr, outLength);
    } finally {
      _free(rawModule, outPtr);
      alloc.dispose();
    }
  }

  /// The ABI v1 symbols the currently loaded WASM module does not export.
  ///
  /// Empty when the module carries the whole ABI v1 surface. This is what the
  /// Web backend asks before running an operation through ABI v1, and what makes
  /// a partially exported build a named, diagnosable failure instead of an
  /// opaque error inside a WASM call. The names come from the shared manifest in
  /// `shared/yuv_abi_v1_symbols.dart`, so they cannot drift from the ones the
  /// native runner dispatches.
  ///
  /// Throws [StateError] when no module is loaded at all.
  List<String> debugMissingAbiV1Symbols() => YuvAbiV1WebDispatch.missingFrom(_requireModule());

  Object _requireModule() {
    final module = YuvWasmLoader.moduleIfInitialized;
    if (module == null) {
      throw StateError(
        'YUV WASM module is not initialized. '
        'Call YuvFfi.ensureInitialized() before image operations on Web.',
      );
    }
    return module.rawModule;
  }
}

final class _WasmYuvAlloc {
  _WasmYuvAlloc._({required this.module, required this.image, required this.defPtr, required this.yPtr, required this.uPtr, required this.vPtr});

  final Object module;
  final YuvImageImpl image;
  final int defPtr;
  final int yPtr;
  final int uPtr;
  final int vPtr;

  static _WasmYuvAlloc fromImage(Object module, YuvImageImpl image) {
    final yPtr = _malloc(module, image.yPlane.bytes.length);
    _heapWrite(module, yPtr, image.yPlane.bytes);

    int uPtr = 0;
    if (image.u != null) {
      uPtr = _malloc(module, image.u!.bytes.length);
      _heapWrite(module, uPtr, image.u!.bytes);
    }

    int vPtr = 0;
    if (image.v != null) {
      vPtr = _malloc(module, image.v!.bytes.length);
      _heapWrite(module, vPtr, image.v!.bytes);
    }

    final defPtr = _malloc(module, YuvImageImpl._yuvDefSizeBytes);
    _writeYuvDef(
      module: module,
      defPtr: defPtr,
      yPtr: yPtr,
      uPtr: uPtr,
      vPtr: vPtr,
      width: image.width,
      height: image.height,
      yRowStride: image.yPlane.rowStride,
      yPixelStride: image.yPlane.pixelStride,
      uvRowStride: image.u?.rowStride ?? 0,
      uvPixelStride: image.u?.pixelStride ?? 0,
    );

    return _WasmYuvAlloc._(module: module, image: image, defPtr: defPtr, yPtr: yPtr, uPtr: uPtr, vPtr: vPtr);
  }

  void copyBack() {
    image.yPlane.assignFrom(_heapRead(module, yPtr, image.yPlane.bytes.length));
    if (uPtr != 0 && image.u != null) {
      image.u!.assignFrom(_heapRead(module, uPtr, image.u!.bytes.length));
    }
    if (vPtr != 0 && image.v != null) {
      image.v!.assignFrom(_heapRead(module, vPtr, image.v!.bytes.length));
    }
  }

  void dispose() {
    _free(module, defPtr);
    _free(module, yPtr);
    if (uPtr != 0) {
      _free(module, uPtr);
    }
    if (vPtr != 0) {
      _free(module, vPtr);
    }
  }
}

int _malloc(Object module, int size) {
  final ptr = js_util.callMethod<num>(module, '_malloc', <Object>[size]).toInt();
  if (ptr == 0) {
    throw StateError('WASM allocation failed for $size bytes.');
  }
  return ptr;
}

void _free(Object module, int ptr) {
  js_util.callMethod<void>(module, '_free', <Object>[ptr]);
}

void _heapWrite(Object module, int ptr, Uint8List bytes) {
  final heap = _heapU8View(module);
  heap.setRange(ptr, ptr + bytes.length, bytes);
}

void _writeInt32Values(Object module, int ptr, List<int> values) {
  final heap32 = _heap32View(module);
  final base = ptr >> 2;
  for (int i = 0; i < values.length; i++) {
    heap32[base + i] = values[i];
  }
}

Uint8List _heapRead(Object module, int ptr, int length) {
  final heap = _heapU8View(module);
  final out = Uint8List(length);
  out.setRange(0, length, heap, ptr);
  return out;
}

void _writeYuvDef({
  required Object module,
  required int defPtr,
  required int yPtr,
  required int uPtr,
  required int vPtr,
  required int width,
  required int height,
  required int yRowStride,
  required int yPixelStride,
  required int uvRowStride,
  required int uvPixelStride,
}) {
  final heap32 = _heap32View(module);
  final base = defPtr >> 2;
  heap32[base + 0] = yPtr;
  heap32[base + 1] = uPtr;
  heap32[base + 2] = vPtr;
  heap32[base + 3] = width;
  heap32[base + 4] = height;
  heap32[base + 5] = yRowStride;
  heap32[base + 6] = yPixelStride;
  heap32[base + 7] = uvRowStride;
  heap32[base + 8] = uvPixelStride;
}

Uint8List _heapU8View(Object module) {
  final heap = js_util.getProperty<Object>(module, 'HEAPU8');
  final buffer = js_util.getProperty<ByteBuffer>(heap, 'buffer');
  final length = js_util.getProperty<num>(heap, 'length').toInt();
  return Uint8List.view(buffer, 0, length);
}

Int32List _heap32View(Object module) {
  final heap = js_util.getProperty<Object>(module, 'HEAP32');
  final buffer = js_util.getProperty<ByteBuffer>(heap, 'buffer');
  final length = js_util.getProperty<num>(heap, 'length').toInt();
  return Int32List.view(buffer, 0, length);
}
