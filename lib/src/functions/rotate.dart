import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

import '../yuv/yuv_image_rotation.dart';

extension RotateYuvImageExt on YuvImage {
  YuvImage rotate(YuvImageRotation rotation) {
    assert(rotation.degrees % 90 == 0, 'Can rotate only to 0, 90, 180, 270 degrees');
    final int degrees = (rotation.degrees < 0 ? 360 - rotation.degrees.abs() : rotation.degrees) % 360;

    if (degrees == 0) {
      return this;
    }

    final srcDef = YUVDefClass(this);
    final dstWidtn = (rotation.swapSize ? height : width).toInt();
    final dstHeight = (rotation.swapSize ? width : height).toInt();
    final dstImage = YuvImage(format, dstWidtn, dstHeight, yPixelStride: yPlane.pixelStride, uvPixelStride: u?.pixelStride ?? 1);
    final dstDef = YUVDefClass(dstImage);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          dstImage.vPlane.assignFromPtr(dstDef.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          dstImage.uPlane.assignFromPtr(dstDef.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_rotate(srcDef.pointer, dstDef.pointer, degrees);
          dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
          break;
      }
    } finally {
      srcDef.dispose();
      dstDef.dispose();
    }

    return dstImage;
  }
}
