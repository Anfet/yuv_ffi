import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';

import 'impl/yuv_stub.dart' if (dart.library.ffi) 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

export 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

abstract interface class YuvImage {
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

  factory YuvImage.i420(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.i420;

  factory YuvImage.nv21(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.nv21;

  factory YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes}) = YuvImageImpl.bgra;

  factory YuvImage(YuvFileFormat format, int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl;


  Uint8List getBytes();

  YuvImage copy({bool blank = false});

  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

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
