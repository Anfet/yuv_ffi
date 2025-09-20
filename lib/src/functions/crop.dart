import 'dart:ffi';
import 'dart:ui';

import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../loader/loader.dart' show ffiBingings;

YuvImage crop(YuvImage image, Rect rect) {
  final YuvImage dst = YuvImage(
    image.format,
    rect.width.floor(),
    rect.height.floor(),
    yPixelStride: image.y.pixelStride,
    uvPixelStride: image.u?.pixelStride ?? 1,
  );
  final srcDef = YUVDefClass(image);
  final dstDef = YUVDefClass(dst);
  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
        dst.vPlane.assignFromPtr(dstDef.pointer.ref.v);

        break;
      case YuvFileFormat.nv21:
        ffiBingings.nv21_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
        break;
      case YuvFileFormat.bgra8888:
        ffiBingings.bgra8888_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.floor(), rect.top.floor(), rect.width.floor(), rect.height.floor());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        break;
    }
  } finally {
    srcDef.dispose();
    dstDef.dispose();
  }

  return dst;
}
