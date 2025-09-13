import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

extension YuvImageBgra8888 on YuvImage {
  void fromRgba8888(Uint8List bytes) {
    final rgbaPlaneLength = bytes.length;
    final rgbaPtr = calloc.allocate<Uint8>(rgbaPlaneLength);
    rgbaPtr.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
    final def = YUVDefClass.template(this);
    try {
      switch (format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
          break;
        case YuvFileFormat.nv21:
          ffiBingings.nv21_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          break;
      }
    } finally {
      def.dispose();
      calloc.free(rgbaPtr);
    }
  }
}
