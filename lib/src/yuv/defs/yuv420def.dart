import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv_ffi_bingings.dart';

/// Dart holder for ffi pointer classes
/// must be disposed to avoid memory leaks
class YUV420DefClass {
  late final Pointer<YUV420Def> pointer;

  YUV420DefClass._(YuvImage image) {
    pointer = calloc.allocate<YUV420Def>(sizeOf<YUV420Def>());
    pointer.ref.width = image.width;
    pointer.ref.height = image.height;
    pointer.ref.yRowStride = image.yPlane.rowStride;
    pointer.ref.yPixelStride = image.yPlane.pixelStride;
    pointer.ref.uvRowStride = image.uPlane.rowStride;
    pointer.ref.uvPixelStride = image.uPlane.pixelStride;

    pointer.ref.y = calloc.allocate<Uint8>(image.yPlane.bytes.length);
    pointer.ref.u = calloc.allocate<Uint8>(image.uPlane.bytes.length);
    pointer.ref.v = calloc.allocate<Uint8>(image.vPlane.bytes.length);
  }

  factory YUV420DefClass.template(YuvImage image) => YUV420DefClass._(image);

  factory YUV420DefClass(YuvImage image) {
    final def = YUV420DefClass._(image);
    def.pointer.ref.y.asTypedList(image.yPlane.bytes.length).setAll(0, image.yPlane.bytes);
    def.pointer.ref.u.asTypedList(image.uPlane.bytes.length).setAll(0, image.uPlane.bytes);
    def.pointer.ref.v.asTypedList(image.vPlane.bytes.length).setAll(0, image.vPlane.bytes);
    return def;
  }

  void dispose() {
    calloc.free(pointer.ref.y);
    calloc.free(pointer.ref.u);
    calloc.free(pointer.ref.v);
    calloc.free(pointer);
  }
}
