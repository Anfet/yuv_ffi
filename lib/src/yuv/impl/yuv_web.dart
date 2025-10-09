import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

class YuvPlaneImpl implements YuvPlane {
  Uint8List get bytes => throw UnimplementedError();

  int get rowStride => throw UnimplementedError();

  int get bytesPerRow => throw UnimplementedError();

  int get pixelStride => throw UnimplementedError();

  int get bytesPerPixes => throw UnimplementedError();

  int getPixel(int x, int y) => throw UnimplementedError();

  void setPixel(int x, int y, int value) => throw UnimplementedError();

  Map<String, dynamic> toJson({bool bytesAsBinary = true, bool bytesAsList = false}) => throw UnimplementedError();

  YuvPlane copy() => throw UnimplementedError();

  YuvPlaneImpl(int height, int rowStride, [int pixelStride = 1, Uint8List? bytes]);

  @override
  void assignFrom(covariant Object other) => throw UnimplementedError();
}

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

  factory YuvImageImpl.fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false}) => throw UnimplementedError();

  Uint8List getBytes() => throw UnimplementedError();

  YuvImage copy({bool blank = false}) => throw UnimplementedError();

  String toJson({bool bytesAsBinary = true, bool bytesAsList = false}) => throw UnimplementedError();

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
