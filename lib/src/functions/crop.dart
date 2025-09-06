import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

import 'package:yuv_ffi/yuv_ffi.dart';

import '../loader/loader.dart' show ffiBingings;

YuvImage crop(YuvImage image, Rect rect) {
  late final YuvImage dst;
  switch (image.format) {
    case YuvFileFormat.i420:
      final srcDef = YUVDefClass(image);
      dst = Yuv420Image(rect.width.toInt(), rect.height.toInt(), image.yPlane.pixelStride, image.uPlane.pixelStride);
      final dstDef = YUVDefClass(dst);

      try {
        ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.toInt(), rect.top.toInt(), rect.width.toInt(), rect.height.toInt());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
        dst.vPlane.assignFromPtr(dstDef.pointer.ref.v);
      } finally {
        srcDef.dispose();
        dstDef.dispose();
      }
      break;
    case YuvFileFormat.nv21:
      final srcDef = YUVDefClass(image);
      dst = Yuv420Image(rect.width.toInt(), rect.height.toInt(), image.yPlane.pixelStride, image.uPlane.pixelStride);
      final dstDef = YUVDefClass(dst);

      try {
        ffiBingings.yuv420_crop_rect(srcDef.pointer, dstDef.pointer, rect.left.toInt(), rect.top.toInt(), rect.width.toInt(), rect.height.toInt());
        dst.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dst.uPlane.assignFromPtr(dstDef.pointer.ref.u);
      } finally {
        srcDef.dispose();
        dstDef.dispose();
      }
      break;
  }

  return dst;
}
