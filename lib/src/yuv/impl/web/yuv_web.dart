import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

class YuvImageImpl implements YuvImage {
  YuvFileFormat get format => throw UnimplementedError();

  int get width => throw UnimplementedError();

  int get height => throw UnimplementedError();

  List<YuvPlane> get planes => throw UnimplementedError();

  YuvPlane get yPlane => throw UnimplementedError();

  YuvPlane get uPlane => throw UnimplementedError();

  YuvPlane get vPlane => throw UnimplementedError();

  YuvPlane get y => throw UnimplementedError();

  YuvPlane? get u => throw UnimplementedError();

  YuvPlane? get v => throw UnimplementedError();

  Size get size => throw UnimplementedError();

  factory YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes}) =>
      throw UnimplementedError();

  factory YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes}) =>
      throw UnimplementedError();

  factory YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes}) => throw UnimplementedError();

  YuvImageImpl(YuvFileFormat format, int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes});

  Uint8List getBytes() => throw UnimplementedError();

  YuvImage copy({bool blank = false}) => throw UnimplementedError();

  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

  @override
  String toString();

  YuvImage blackwhite() => throw UnimplementedError();

  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  YuvImage swapNv() => throw UnimplementedError();

  YuvImage toYuvNv21() => throw UnimplementedError();

  YuvImage toYuvI420() => throw UnimplementedError();

  YuvImage toYuvBgra8888() => throw UnimplementedError();

  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  YuvImage flipHorizontally() => throw UnimplementedError();

  YuvImage flipVertically() => throw UnimplementedError();

  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  YuvImage grayscale() => throw UnimplementedError();

  YuvImage negate() => throw UnimplementedError();

  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  Uint8List toBgra8888() => throw UnimplementedError();

  Future<ui.Image> toImage() => throw UnimplementedError();
}
