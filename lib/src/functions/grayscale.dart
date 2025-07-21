import 'dart:ffi';

import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv420def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage grayscale(YuvImage image) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final def = YUV420DefClass(image);

      try {
        ffiBingings.yuv420_grayscale(def.pointer);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        image.vPlane.assignFromPtr(def.pointer.ref.v);
      } finally {
        def.dispose();
      }
  }

  return image;
}
