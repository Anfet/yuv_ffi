import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv420def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';

extension YuvImageBgra8888 on YuvImage {
  Uint8List toBgra8888() {
    switch (format) {
      case YuvFileFormat.nv21:
        // TODO: Handle this case.
        throw UnimplementedError();
      case YuvFileFormat.i420:
        final def = YUV420DefClass(this);
        final bgraPlaneLength = width * height * 4;
        final bgraPlane = calloc.allocate<Uint8>(bgraPlaneLength);
        assert(bgraPlane != nullptr);

        try {
          ffiBingings.yuv420_to_bgra8888(def.pointer, bgraPlane);
          return Uint8List.fromList(bgraPlane.asTypedList(bgraPlaneLength));
        } finally {
          calloc.free(bgraPlane);
          def.dispose();
        }
    }
  }
}
