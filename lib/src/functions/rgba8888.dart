import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv420def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

extension YuvImageBgra8888 on YuvImage {
  void fromRgba8888(Uint8List bytes) {
    switch (format) {
      case YuvFileFormat.nv21:
        // TODO: Handle this case.
        throw UnimplementedError();
      case YuvFileFormat.i420:
        final rgbaPlaneLength = bytes.length;
        final rgbaPtr = calloc.allocate<Uint8>(rgbaPlaneLength);
        rgbaPtr.asTypedList(bytes.length).setRange(0, bytes.length, bytes);

        final def = YUV420DefClass.template(this);
        try {
          ffiBingings.yuv420_from_rgba8888(rgbaPtr, def.pointer);
          yPlane.assignFromPtr(def.pointer.ref.y);
          uPlane.assignFromPtr(def.pointer.ref.u);
          vPlane.assignFromPtr(def.pointer.ref.v);
        } finally {
          def.dispose();
          calloc.free(rgbaPtr);
        }
    }
  }
}
