import 'package:yuv_ffi/src/functions/yuv420_to_nv21.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_nv21_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';

extension YuvImageToNV21 on YuvImage {
  YuvNV21Image toNv21() {
    if (this is YuvNV21Image) {
      return this as YuvNV21Image;
    }

    return (this as Yuv420Image).toNv21();
  }
}
