import 'dart:ffi';

import 'package:yuv_ffi/src/functions/to_bgra8888.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

extension ConvertExt on YuvImage {

  YuvImage swapNv() {
    var nvXX = format == YuvFileFormat.nv21 ? this : toYuvNv21();

    final def = YUVDefClass(nvXX);
    YuvImage nvYY = YuvImage.nv21(width, height);
    final defYY = YUVDefClass(nvYY);
    try {
      ffiBingings.nvXX_to_nvYY(def.pointer.ref.u, defYY.pointer.ref.u, nvXX.width, nvYY.width, nvXX.uPlane.rowStride);

      nvYY.yPlane.assignFromPtr(defYY.pointer.ref.y);
      nvYY.uPlane.assignFromPtr(defYY.pointer.ref.u);
    } finally {
      def.dispose();
      defYY.dispose();
    }

    return nvYY;
  }

  YuvImage toYuvNv21() {
    if (format == YuvFileFormat.nv21) {
      return copy();
    }

    final def = YUVDefClass(this);
    YuvImage n21 = YuvImage.nv21(width, height);
    final def21 = YUVDefClass(n21);
    try {
      switch (this.format) {
        case YuvFileFormat.i420:
          ffiBingings.yuv420_i420_to_nv21(def.pointer, def21.pointer);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_to_nv21(def.pointer, def21.pointer);
          break;
        default:
          throw UnimplementedError();
      }

      n21.yPlane.assignFromPtr(def21.pointer.ref.y);
      n21.uPlane.assignFromPtr(def21.pointer.ref.u);
    } finally {
      def.dispose();
      def21.dispose();
    }

    return n21;
  }

  YuvImage toYuvI420() {
    if (format == YuvFileFormat.i420) {
      return copy();
    }

    final def = YUVDefClass(this);
    YuvImage i420 = YuvImage.i420(width, height);
    final def420 = YUVDefClass(i420);
    try {
      switch (this.format) {
        case YuvFileFormat.nv21:
          ffiBingings.nv21_to_i420(def.pointer, def420.pointer);
          break;
        case YuvFileFormat.bgra8888:
          ffiBingings.bgra8888_to_i420(def.pointer, def420.pointer);
          break;
        default:
          throw UnimplementedError();
      }

      i420.yPlane.assignFromPtr(def420.pointer.ref.y);
      i420.uPlane.assignFromPtr(def420.pointer.ref.u);
      i420.vPlane.assignFromPtr(def420.pointer.ref.v);
    } finally {
      def.dispose();
      def420.dispose();
    }
    return i420;
  }

  YuvImage toYuvBgra8888() {
    if (format == YuvFileFormat.bgra8888) {
      return copy();
    }

    var bytes = toBgra8888();
    var image = YuvImage(YuvFileFormat.bgra8888, width, height, planes: [YuvPlane(height, width * 4, 4, bytes)], yPixelStride: 4);
    return image;
  }
}
