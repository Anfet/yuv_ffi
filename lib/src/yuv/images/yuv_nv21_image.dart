import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';

import '../yuv_image.dart';
import '../yuv_planes.dart';

@immutable
class YuvNV21Image extends YuvImage {
  @override
  final YuvFileFormat format = YuvFileFormat.nv21;

  @override
  int get width => _width;

  int _width;

  @override
  int get height => _height;

  int _height;

  @override
  List<YuvPlane> get planes => List.unmodifiable(_planes);

  late List<YuvPlane> _planes;

  @override
  YuvPlane get uPlane => planes[1];

  @override
  YuvPlane get vPlane => planes[1];

  @override
  YuvPlane get yPlane => planes[0];

  YuvNV21Image.fromPlanes(this._width, this._height, this._planes);

  YuvNV21Image(this._width, this._height, [int yPixelStride = 1, int uvPixelStride = 2]) {
    final yplane = YuvPlane(height, width, 1);
    final uvWidth = (width / 2).round();
    final uvHeight = (height / 2).round();
    final uvplane = YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride);
    _planes = [yplane, uvplane];
  }

  YuvNV21Image._(this._width, this._height, this._planes);

  @override
  YuvNV21Image create(int width, int height) => YuvNV21Image(width, height);

  @override
  YuvImage copy() {
    var planes = this.planes.map((p) => p.copy());
    return YuvNV21Image.fromPlanes(width, height, List.of(planes));
  }
}
