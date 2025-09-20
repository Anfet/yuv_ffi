import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage grayscale(YuvImage image) {
  final def = YUVDefClass(image);

  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_grayscale(def.pointer);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        image.vPlane.assignFromPtr(def.pointer.ref.v);
        break;
      case YuvFileFormat.nv21:
        ffiBingings.nv21_grayscale(def.pointer);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        break;
      case YuvFileFormat.bgra8888:
        ffiBingings.bgra8888_grayscale(def.pointer);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;
    }
  } finally {
    def.dispose();
  }
  return image;
}
