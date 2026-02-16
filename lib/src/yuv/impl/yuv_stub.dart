import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List, WriteBuffer;
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

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
    sink.add(getBytes());
  }

  @override
  Future<void> load(Stream<List<int>> stream) async {
    await stream.drain<List<int>>();
  }

  @override
  String toString() {
    return '$runtimeType(format: ${format.name}, width: $width, '
        'height: $height, planes: ${planes.length})';
  }

  @override
  YuvImage blackwhite() => this;

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => this;

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => this;

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => this;

  @override
  YuvImage swapNv() => this;

  @override
  YuvImage toYuvNv21() => YuvImageImpl.nv21(_width, _height, yPixelStride: y.pixelStride);

  @override
  YuvImage toYuvI420() => YuvImageImpl.i420(_width, _height, yPixelStride: y.pixelStride);

  @override
  YuvImage toYuvBgra8888() => YuvImageImpl.bgra(_width, _height);

  @override
  YuvImage crop(ui.Rect rect) {
    final croppedWidth = rect.width.floor().clamp(0, _width);
    final croppedHeight = rect.height.floor().clamp(0, _height);
    _width = croppedWidth;
    _height = croppedHeight;

    switch (_format) {
      case YuvFileFormat.bgra8888:
        _planes = [YuvPlane(_height, _width * 4, 4)];
        break;
      case YuvFileFormat.nv21:
        _planes = YuvImageImpl.nv21(_width, _height).planes;
        break;
      case YuvFileFormat.i420:
        _planes = YuvImageImpl.i420(_width, _height).planes;
        break;
    }

    return this;
  }

  @override
  YuvImage flipHorizontally() => this;

  @override
  YuvImage flipVertically() => this;

  @override
  void fromRgba8888(Uint8List bytes) {
    if (bytes.length != _width * _height * 4) {
      return;
    }

    if (_format == YuvFileFormat.bgra8888) {
      final bgra = Uint8List(bytes.length);
      for (int i = 0; i < bytes.length; i += 4) {
        bgra[i] = bytes[i + 2];
        bgra[i + 1] = bytes[i + 1];
        bgra[i + 2] = bytes[i];
        bgra[i + 3] = bytes[i + 3];
      }
      _planes[0].assignFrom(bgra);
    }
  }

  @override
  YuvImage grayscale() => this;

  @override
  YuvImage negate() => this;

  @override
  YuvImage rotate(YuvImageRotation rotation) => this;

  @override
  Uint8List toBgra8888() {
    if (_format == YuvFileFormat.bgra8888) {
      return Uint8List.fromList(yPlane.bytes);
    }
    return Uint8List(_width * _height * 4);
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
}
