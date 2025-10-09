import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

abstract class YuvPlaneImpl implements YuvPlane{
  Uint8List get bytes;

  int get rowStride;

  int get bytesPerRow;

  int get pixelStride;

  int get bytesPerPixes;

  int getPixel(int x, int y);

  void setPixel(int x, int y, int value);

  Map<String, dynamic> toJson({bool bytesAsBinary = true, bool bytesAsList = false});

  YuvPlane copy();

  factory YuvPlaneImpl(int height, int rowStride, [int pixelStride = 1, Uint8List? bytes]) => throw UnimplementedError();
}

abstract class YuvImageImpl implements YuvImage {
  YuvFileFormat get format;

  int get width;

  int get height;

  List<YuvPlane> get planes;

  YuvPlane get yPlane;

  YuvPlane get uPlane;

  YuvPlane get vPlane;

  YuvPlane get y;

  YuvPlane? get u;

  YuvPlane? get v;

  ui.Size get size;

  factory YuvImageImpl.i420(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes}) =>
      throw UnimplementedError();

  factory YuvImageImpl.nv21(int width, int height, {int yPixelStride = 1, int uvPixelStride = 2, Iterable<YuvPlane>? planes}) =>
      throw UnimplementedError();

  factory YuvImageImpl.bgra(int width, int height, {Iterable<YuvPlane>? planes}) => throw UnimplementedError();

  factory YuvImageImpl(YuvFileFormat format, int width, int height, {int yPixelStride = 1, int uvPixelStride = 1, Iterable<YuvPlane>? planes}) =>
      throw UnimplementedError();

  Uint8List getBytes();

  YuvImage copy({bool blank = false});

  String toJson({bool bytesAsBinary = true, bool bytesAsList = false});

  factory YuvImageImpl.fromJson(Map<String, dynamic> json, {bool bytesAsBinary = true, bool bytesAsList = false}) => throw UnimplementedError();

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
