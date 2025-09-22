import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

extension GrayscaleYuvImageExt on YuvImage {
  YuvImage grayscale() {
    final def = YUVDefClass(this);

    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_grayscale(def.pointer);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_grayscale(def.pointer);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_grayscale(def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
    }
    return this;
  }
}
