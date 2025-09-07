import 'dart:ffi';
import 'dart:ui';

import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../loader/loader.dart' show ffiBingings;

YuvImage crop(YuvImage image, Rect rect) {
  final YuvImage dst = image.copy(blank: true);
  final srcDef = YUVDefClass(image);
  final dstDef = YUVDefClass(dst);
  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.toInt(), rect.top.toInt(), rect.width.toInt(), rect.height.toInt());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
        dst.vPlane.assignFromPtr(dstDef.pointer.ref.v);

        break;
      case YuvFileFormat.nv21:
        ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.toInt(), rect.top.toInt(), rect.width.toInt(), rect.height.toInt());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        break;
      default:
        throw UnimplementedError();
    }
  } finally {
    srcDef.dispose();
    dstDef.dispose();
  }

  return dst;
}
