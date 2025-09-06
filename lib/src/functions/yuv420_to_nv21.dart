import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_nv21_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

extension Yuv420ToNv21Ext on Yuv420Image {
  YuvNV21Image toNv21() {
    final def420 = YUVDefClass(this);
    YuvNV21Image n21 = YuvNV21Image(width, height);
    final def21 = YUVDefClass(n21);

    try {
      ffiBingings.yuv420_i420_to_nv21(def420.pointer, def21.pointer);
      n21.yPlane.assignFromPtr(def21.pointer.ref.y);
      n21.uPlane.assignFromPtr(def21.pointer.ref.u);
      return n21;
    } finally {
      def420.dispose();
      def21.dispose();
    }
  }
}
