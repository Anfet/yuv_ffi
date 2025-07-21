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
  final int width;

  @override
  final int height;

  @override
  late final List<YuvPlane> planes;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  @override
  YuvPlane get yPlane => throw UnimplementedError();

  YuvNV21Image.fromPlanes(this.width, this.height, this.planes);

  YuvNV21Image(this.width, this.height) {
    final yplane = YuvPlane(width, height, 1);
    final uvWidth = (width / 2).round();
    final uvHeight = (height / 2).round();
    final uvplane = YuvPlane(uvWidth, uvHeight, 2);
    planes = List.unmodifiable([yplane, uvplane]);
  }

  YuvNV21Image._(this.width, this.height, this.planes);

  @override
  YuvNV21Image create(int width, int height) => YuvNV21Image(width, height);

  @override
  YuvImage copy() {
    var planes = this.planes.map((p) => p.copy());
    return YuvNV21Image.fromPlanes(width, height, List.of(planes));
  }
}
