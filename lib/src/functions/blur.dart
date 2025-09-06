import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage gaussianBlur(YuvImage image, {int radius = 2, int sigma = 2}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final def = YUVDefClass(image);
      try {
        ffiBingings.yuv420_gaussblur(def.pointer, radius, sigma);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        image.vPlane.assignFromPtr(def.pointer.ref.v);
      } finally {
        def.dispose();
      }
  }

  return image;
}

YuvImage boxBlur(YuvImage image, {int radius = 10, ui.Rect? rect}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final def = YUVDefClass(image);
      final rectPtr = rect == null ? nullptr : calloc.allocate<Uint32>(4 * 32);
      if (rect != null) {
        rectPtr.asTypedList(32)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }

      try {
        ffiBingings.yuv420_box_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
      } finally {
        def.dispose();
      }
      break;
  }
  return image;
}

YuvImage meanBlur(YuvImage image, {int radius = 2, ui.Rect? rect}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final def = YUVDefClass(image);
      final rectPtr = rect == null ? nullptr : calloc.allocate<Uint32>(4 * 32);
      if (rect != null) {
        rectPtr.asTypedList(32)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }

      try {
        ffiBingings.yuv420_mean_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
      } finally {
        def.dispose();
      }
      break;
  }

  return image;
}
