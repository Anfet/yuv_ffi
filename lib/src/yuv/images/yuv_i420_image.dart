import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/src/loader/loader.dart';

import '../yuv_image.dart';
import '../yuv_planes.dart';

@immutable
class Yuv420Image extends YuvImage {
  @override
  final YuvFileFormat format = YuvFileFormat.i420;

  @override
  final int width;

  @override
  final int height;

  @override
  late final List<YuvPlane> planes;

  @override
  YuvPlane get yPlane => planes[0];

  @override
  YuvPlane get uPlane => planes[1];

  @override
  YuvPlane get vPlane => planes[2];

  Yuv420Image._(this.width, this.height, this.planes);

  Yuv420Image(this.width, this.height) {
    final yplane = YuvPlane.empty(width, height, 1);
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final uplane = YuvPlane.empty(uvWidth, uvHeight, 2);
    final vplane = YuvPlane.empty(uvWidth, uvHeight, 2);
    planes = List.unmodifiable([yplane, uplane, vplane]);
  }

  Yuv420Image.fromPlanes(this.width, this.height, this.planes);

  @override
  Yuv420Image create(int width, int height) => Yuv420Image(width, height);

  @override
  Uint8List bgra8888() {
    final (_, yPlane) = this.yPlane.allocatePtr();
    final (_, uPlane) = this.uPlane.allocatePtr();
    final (_, vPlane) = this.vPlane.allocatePtr();
    final bgraPlaneLength = width * height * 4;
    final bgraPlane = calloc.allocate<Uint8>(bgraPlaneLength);
    try {
      final uvRowStride = this.uPlane.rowStride;
      final uvPixelStride = this.vPlane.pixelStride;
      ffiBingings.yuv420_to_bgra8888(yPlane, uPlane, vPlane, this.yPlane.rowStride, uvRowStride, uvPixelStride, width, height, bgraPlane);
      final result = Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
      return result;
    } finally {
      calloc.free(yPlane);
      calloc.free(uPlane);
      calloc.free(vPlane);
      calloc.free(bgraPlane);
    }
  }

  @override
  YuvImage copy() {
    var planes = this.planes.map((p) => p.copy());
    return Yuv420Image.fromPlanes(width, height, List.of(planes));
  }
}
