import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

YuvImage toNV21(YuvImage image) {
  if (image.format == YuvFileFormat.nv21) {
    return image.copy();
  }

  final def = YUVDefClass(image);
  YuvImage n21 = YuvImage.nv21(image.width, image.height);
  final def21 = YUVDefClass(n21);

  try {
    switch (image.format) {
      case YuvFileFormat.nv21:
        throw UnimplementedError();
      case YuvFileFormat.i420:
        ffiBingings.yuv420_i420_to_nv21(def.pointer, def21.pointer);
        n21.yPlane.assignFromPtr(def21.pointer.ref.y);
        n21.uPlane.assignFromPtr(def21.pointer.ref.u);
        return n21;
      case YuvFileFormat.bgra8888:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  } finally {
    def.dispose();
    def21.dispose();
  }
}
