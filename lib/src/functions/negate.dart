import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage negate(YuvImage image) {
  final def = YUVDefClass(image);

  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_negate(def.pointer);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        image.vPlane.assignFromPtr(def.pointer.ref.v);
        break;
      default:
        throw UnimplementedError();
    }
  } finally {
    def.dispose();
  }

  return image;
}
