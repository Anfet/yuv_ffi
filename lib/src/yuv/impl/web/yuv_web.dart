// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:yuv_ffi/src/loader/wasm_loader.dart';
import 'package:yuv_ffi/src/loader/data_io.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Web backend implementation backed by WASM exports where available.
class YuvImageImpl implements YuvImage {
  YuvImageImpl.i420(
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 2,
    Iterable<YuvPlane>? planes,
  }) : this(
          YuvFileFormat.i420,
          width,
          height,
          yPixelStride: yPixelStride,
          uvPixelStride: uvPixelStride,
          planes: planes,
        );

  YuvImageImpl.nv21(
    int width,
    int height, {
    int yPixelStride = 1,
    int uvPixelStride = 2,
    Iterable<YuvPlane>? planes,
  }) : this(
          YuvFileFormat.nv21,
          width,
          height,
          yPixelStride: yPixelStride,
          uvPixelStride: uvPixelStride,
          planes: planes,
        );

  YuvImageImpl.bgra(
    int width,
    int height, {
    Iterable<YuvPlane>? planes,
  }) : this(
          YuvFileFormat.bgra8888,
          width,
          height,
          yPixelStride: 4,
          uvPixelStride: 1,
          planes: planes,
        );

  YuvImageImpl(
    this._format,
    this._width,
    this._height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
  }) {
    if (planes != null) {
      _planes = List<YuvPlane>.from(planes.map((p) => p.copy()));
      return;
    }

    final yPlane = YuvPlane(
      _height,
      _format == YuvFileFormat.bgra8888 ? _width * 4 : _width * yPixelStride,
      _format == YuvFileFormat.bgra8888 ? 4 : yPixelStride,
    );
    final uvWidth = (_width / 2.0).ceil();
    final uvHeight = (_height / 2.0).ceil();

    switch (_format) {
      case YuvFileFormat.nv21:
        _planes = [
          yPlane,
          YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride),
        ];
        break;
      case YuvFileFormat.i420:
        _planes = [
          yPlane,
          YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride),
          YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride),
        ];
        break;
      case YuvFileFormat.bgra8888:
        _planes = [yPlane];
        break;
    }
  }

  static const int _bytesPerPixel = 4;
  static const int _yuvDefFieldsCount = 9;
  static const int _yuvDefSizeBytes = _yuvDefFieldsCount * 4;
  static final YuvPlane _emptyPlane = YuvPlane(0, 0);

  YuvFileFormat _format;
  int _width;
  int _height;
  List<YuvPlane> _planes = const [];

  @override
  YuvFileFormat get format => _format;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  List<YuvPlane> get planes => List<YuvPlane>.unmodifiable(_planes);

  @override
  YuvPlane get yPlane => _planes.isNotEmpty ? _planes[0] : _emptyPlane;

  @override
  YuvPlane get uPlane => _planes.length > 1 ? _planes[1] : _emptyPlane;

  @override
  YuvPlane get vPlane => _planes.length > 2 ? _planes[2] : _emptyPlane;

  @override
  YuvPlane get y => yPlane;

  @override
  YuvPlane? get u => _planes.length > 1 ? _planes[1] : null;

  @override
  YuvPlane? get v => _planes.length > 2 ? _planes[2] : null;

  @override
  ui.Size get size => ui.Size(_width.toDouble(), _height.toDouble());

  @override
  Uint8List getBytes() {
    final all = WriteBuffer();
    for (final plane in _planes) {
      all.putUint8List(plane.bytes);
    }
    return all.done().buffer.asUint8List();
  }

  @override
  YuvImage copy({bool blank = false}) => YuvImageImpl(
        _format,
        _width,
        _height,
        yPixelStride: y.pixelStride,
        uvPixelStride: u?.pixelStride ?? 1,
        planes: blank ? null : _planes,
      );

  @override
  Future<void> save(Sink<List<int>> sink) async {
    final json = {
      'version': 1,
      'format': format.name,
      'width': width,
      'height': height,
    };

    final writer = DataWriter(sink);
    writer.writeString(jsonEncode(json));
    writer.writeUint8(planes.length);
    for (final plane in planes) {
      writer.writeUint32(plane.height);
      writer.writeUint32(plane.rowStride);
      writer.writeUint32(plane.pixelStride);
      writer.writeBytes(plane.bytes);
    }
    writer.write();
  }

  @override
  Future<void> load(Stream<List<int>> stream) async {
    final reader = DataReader(stream);
    await reader.done();

    final header = jsonDecode(reader.readString()) as Map<String, dynamic>;
    _width = header['width'] as int;
    _height = header['height'] as int;
    _format = YuvFileFormat.values.byName(header['format'] as String);

    final planesCount = reader.readUint8();
    _planes = <YuvPlane>[];
    for (int i = 0; i < planesCount; i++) {
      final planeHeight = reader.readUint32();
      final rowStride = reader.readUint32();
      final pixelStride = reader.readUint32();
      final planeBytes = reader.readBytes();
      _planes.add(YuvPlane(planeHeight, rowStride, pixelStride, planeBytes));
    }
  }

  @override
  String toString() {
    return '$runtimeType(format: ${format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  @override
  YuvImage blackwhite() {
    _callInPlaceUnary(_symbolForFormat(
      i420: 'yuv420_blackwhite',
      nv21: 'nv21_blackwhite',
      bgra: 'bgra8888_blackwhite',
    ));
    return this;
  }

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    _callInPlaceBlur(
      _symbolForFormat(
        i420: 'yuv420_gaussblur',
        nv21: 'nv21_gaussian_blur',
        bgra: 'bgra8888_gaussian_blur',
      ),
      radius,
      sigma,
    );
    return this;
  }

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
    _callInPlaceBlurWithRect(
      _symbolForFormat(
        i420: 'yuv420_box_blur',
        nv21: 'nv21_box_blur',
        bgra: 'bgra8888_box_blur',
      ),
      radius,
      rect,
    );
    return this;
  }

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
    _callInPlaceBlurWithRect(
      _symbolForFormat(
        i420: 'yuv420_mean_blur',
        nv21: 'nv21_mean_blur',
        bgra: 'bgra8888_mean_blur',
      ),
      radius,
      rect,
    );
    return this;
  }

  @override
  YuvImage swapNv() {
    final source = _format == YuvFileFormat.nv21 ? this : toYuvNv21();

    final rawModule = _requireModule();
    final srcAlloc = _WasmYuvAlloc.fromImage(rawModule, source as YuvImageImpl);
    final dst = YuvImageImpl.nv21(
      source.width,
      source.height,
      yPixelStride: source.y.pixelStride,
      uvPixelStride: source.u?.pixelStride ?? 1,
    );
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      // nvXX_to_nvYY swaps interleaved chroma ordering in UV buffer.
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          'nvXX_to_nvYY',
          'void',
          <String>['number', 'number', 'number', 'number', 'number'],
          <Object?>[
            srcAlloc.uPtr,
            dstAlloc.uPtr,
            source.width,
            source.height,
            source.uPlane.rowStride,
          ],
        ],
      );
      // Y plane is unchanged; copy it directly.
      _heapWrite(rawModule, dstAlloc.yPtr, source.yPlane.bytes);
      dstAlloc.copyBack();
      return dst;
    } finally {
      srcAlloc.dispose();
      dstAlloc.dispose();
    }
  }

  @override
  YuvImage toYuvNv21() {
    if (_format == YuvFileFormat.nv21) {
      return this;
    }
    final dst = YuvImageImpl.nv21(_width, _height);
    final symbol = switch (_format) {
      YuvFileFormat.i420 => 'yuv420_i420_to_nv21',
      YuvFileFormat.bgra8888 => 'bgra8888_to_nv21',
      YuvFileFormat.nv21 => throw StateError('unreachable'),
    };
    _callFormatConversion(symbol: symbol, dst: dst);
    return dst;
  }

  @override
  YuvImage toYuvI420() {
    if (_format == YuvFileFormat.i420) {
      return this;
    }
    final dst = YuvImageImpl.i420(_width, _height);
    final symbol = switch (_format) {
      YuvFileFormat.nv21 => 'nv21_to_i420',
      YuvFileFormat.bgra8888 => 'bgra8888_to_i420',
      YuvFileFormat.i420 => throw StateError('unreachable'),
    };
    _callFormatConversion(symbol: symbol, dst: dst);
    return dst;
  }

  @override
  YuvImage toYuvBgra8888() {
    if (_format == YuvFileFormat.bgra8888) {
      return this;
    }
    final bytes = toBgra8888();
    return YuvImageImpl.bgra(
      _width,
      _height,
      planes: [YuvPlane(_height, _width * _bytesPerPixel, _bytesPerPixel, bytes)],
    );
  }

  @override
  YuvImage crop(ui.Rect rect) {
    final left = rect.left.floor().clamp(0, _width).toInt();
    final top = rect.top.floor().clamp(0, _height).toInt();
    final right = rect.right.ceil().clamp(left, _width).toInt();
    final bottom = rect.bottom.ceil().clamp(top, _height).toInt();
    final cropWidth = right - left;
    final cropHeight = bottom - top;
    if (cropWidth <= 0 || cropHeight <= 0) {
      return this;
    }

    final symbol = _symbolForFormat(
      i420: 'yuv420_crop_rect',
      nv21: 'nv21_crop_rect',
      bgra: 'bgra8888_crop_rect',
    );
    _callSrcDst(
      symbol: symbol,
      dstWidth: cropWidth,
      dstHeight: cropHeight,
      extraArgTypes: const <String>['number', 'number', 'number', 'number'],
      extraArgs: <Object?>[left, top, cropWidth, cropHeight],
    );
    return this;
  }

  @override
  YuvImage flipHorizontally() {
    _callInPlaceUnary(_symbolForFormat(
      i420: 'yuv420_flip_horizontally',
      nv21: 'nv21_flip_horizontally',
      bgra: 'bgra8888_flip_horizontally',
    ));
    return this;
  }

  @override
  YuvImage flipVertically() {
    _callInPlaceUnary(_symbolForFormat(
      i420: 'yuv420_flip_vertically',
      nv21: 'nv21_flip_vertically',
      bgra: 'bgra8888_flip_vertically',
    ));
    return this;
  }

  @override
  void fromRgba8888(Uint8List bytes) {
    final expectedLength = _width * _height * _bytesPerPixel;
    if (bytes.length != expectedLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Expected $expectedLength bytes for RGBA8888 frame ${_width}x$_height',
      );
    }

    _callFromRgba(
      _symbolForFormat(
        i420: 'yuv420_from_rgba8888',
        nv21: 'nv21_from_rgba8888',
        bgra: 'bgra8888_from_rgba8888',
      ),
      bytes,
    );
  }

  @override
  YuvImage grayscale() {
    _callInPlaceUnary(_symbolForFormat(
      i420: 'yuv420_grayscale',
      nv21: 'nv21_grayscale',
      bgra: 'bgra8888_grayscale',
    ));
    return this;
  }

  @override
  YuvImage negate() {
    _callInPlaceUnary(_symbolForFormat(
      i420: 'yuv420_negate',
      nv21: 'nv21_negate',
      bgra: 'bgra8888_negate',
    ));
    return this;
  }

  @override
  YuvImage rotate(YuvImageRotation rotation) {
    final int degrees = (rotation.degrees < 0 ? 360 - rotation.degrees.abs() : rotation.degrees) % 360;
    if (degrees == 0) {
      return this;
    }
    final dstWidth = rotation.swapSize ? _height : _width;
    final dstHeight = rotation.swapSize ? _width : _height;
    final symbol = _symbolForFormat(
      i420: 'yuv420_rotate',
      nv21: 'nv21_rotate',
      bgra: 'bgra8888_rotate',
    );
    _callSrcDst(
      symbol: symbol,
      dstWidth: dstWidth,
      dstHeight: dstHeight,
      extraArgTypes: const <String>['number'],
      extraArgs: <Object?>[degrees],
    );
    return this;
  }

  @override
  Uint8List toBgra8888() {
    if (_format == YuvFileFormat.bgra8888) {
      return Uint8List.fromList(yPlane.bytes);
    }
    return _callToBgra(
      _symbolForFormat(
        i420: 'yuv420_to_bgra8888',
        nv21: 'nv21_to_bgra8888',
        bgra: 'unused',
      ),
    );
  }

  @override
  Future<ui.Image> toImage() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      toBgra8888(),
      _width,
      _height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  String _symbolForFormat({
    required String i420,
    required String nv21,
    required String bgra,
  }) {
    return switch (_format) {
      YuvFileFormat.i420 => i420,
      YuvFileFormat.nv21 => nv21,
      YuvFileFormat.bgra8888 => bgra,
    };
  }

  void _callInPlaceUnary(String symbol) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    try {
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number'],
          <Object?>[alloc.defPtr],
        ],
      );
      alloc.copyBack();
    } finally {
      alloc.dispose();
    }
  }

  void _callInPlaceBlur(String symbol, int radius, int sigma) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    try {
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number', 'number', 'number'],
          <Object?>[alloc.defPtr, radius, sigma],
        ],
      );
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
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number', 'number', 'number'],
          <Object?>[alloc.defPtr, radius, rectPtr],
        ],
      );
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
    final dst = YuvImageImpl(
      _format,
      dstWidth,
      dstHeight,
      yPixelStride: y.pixelStride,
      uvPixelStride: u?.pixelStride ?? 1,
    );
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      final argTypes = <String>['number', 'number', ...extraArgTypes];
      final args = <Object?>[srcAlloc.defPtr, dstAlloc.defPtr, ...extraArgs];
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[symbol, 'void', argTypes, args],
      );
      dstAlloc.copyBack();
      _width = dstWidth;
      _height = dstHeight;
      _planes = dst.planes.map((p) => p.copy()).toList(growable: false);
    } finally {
      srcAlloc.dispose();
      dstAlloc.dispose();
    }
  }

  void _callFormatConversion({
    required String symbol,
    required YuvImageImpl dst,
  }) {
    final rawModule = _requireModule();
    final srcAlloc = _WasmYuvAlloc.fromImage(rawModule, this);
    final dstAlloc = _WasmYuvAlloc.fromImage(rawModule, dst);
    try {
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number', 'number'],
          <Object?>[srcAlloc.defPtr, dstAlloc.defPtr],
        ],
      );
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
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number', 'number'],
          <Object?>[rgbaPtr, alloc.defPtr],
        ],
      );
      alloc.copyBack();
    } finally {
      _free(rawModule, rgbaPtr);
      alloc.dispose();
    }
  }

  Uint8List _callToBgra(String symbol) {
    final rawModule = _requireModule();
    final alloc = _WasmYuvAlloc.fromImage(rawModule, this);
    final outLength = _width * _height * _bytesPerPixel;
    final outPtr = _malloc(rawModule, outLength);
    try {
      js_util.callMethod<Object?>(
        rawModule,
        'ccall',
        <Object?>[
          symbol,
          'void',
          <String>['number', 'number'],
          <Object?>[alloc.defPtr, outPtr],
        ],
      );
      return _heapRead(rawModule, outPtr, outLength);
    } finally {
      _free(rawModule, outPtr);
      alloc.dispose();
    }
  }

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
  _WasmYuvAlloc._({
    required this.module,
    required this.image,
    required this.defPtr,
    required this.yPtr,
    required this.uPtr,
    required this.vPtr,
  });

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

    return _WasmYuvAlloc._(
      module: module,
      image: image,
      defPtr: defPtr,
      yPtr: yPtr,
      uPtr: uPtr,
      vPtr: vPtr,
    );
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
