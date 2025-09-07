import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

import '../yuv/yuv_image_rotation.dart';

YuvImage rotate(YuvImage image, YuvImageRotation rotation) {
  assert(rotation.degrees % 90 == 0, 'Can rotate only to 0, 90, 180, 270 degrees');
  final int degrees = (rotation.degrees < 0 ? 360 - rotation.degrees.abs() : rotation.degrees) % 360;

  if (degrees == 0) {
    return image;
  }

  final srcDef = YUVDefClass(image);
  final dstWidtn = (rotation.swapSize ? image.height : image.width).toInt();
  final dstHeight = (rotation.swapSize ? image.width : image.height).toInt();
  final dstImage = YuvImage(image.format, dstWidtn, dstHeight, yPixelStride: image.yPlane.pixelStride, uvPixelStride: image.uPlane.pixelStride);
  final dstDef = YUVDefClass(dstImage);
  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_rotate(srcDef.pointer, dstDef.pointer, degrees);
        dstImage.yPlane.assignFromPtr(dstDef.pointer.ref.y);
        dstImage.uPlane.assignFromPtr(dstDef.pointer.ref.u);
        dstImage.vPlane.assignFromPtr(dstDef.pointer.ref.v);
        break;
      default:
        throw UnimplementedError();
    }
  } finally {
    srcDef.dispose();
    dstDef.dispose();
  }

  return dstImage;
}
