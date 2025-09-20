import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/defs/yuv_def.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage gaussianBlur(YuvImage image, {int radius = 2, int sigma = 2}) {
  final def = YUVDefClass(image);
  try {
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_gaussblur(def.pointer, radius, sigma);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        image.vPlane.assignFromPtr(def.pointer.ref.v);
        break;
      case YuvFileFormat.nv21:
        ffiBingings.nv21_gaussian_blur(def.pointer, radius, sigma.toDouble());
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        break;
      case YuvFileFormat.bgra8888:
        ffiBingings.bgra8888_gaussian_blur(def.pointer, radius, sigma.toDouble());
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;
    }
  } finally {
    def.dispose();
  }

  return image;
}

YuvImage boxBlur(YuvImage image, {int radius = 10, ui.Rect? rect}) {
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
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_box_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;
      case YuvFileFormat.nv21:
        ffiBingings.nv21_box_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        break;
      case YuvFileFormat.bgra8888:
        ffiBingings.bgra8888_box_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;
    }
  } finally {
    def.dispose();
  }
  return image;
}

YuvImage meanBlur(YuvImage image, {int radius = 2, ui.Rect? rect}) {
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
    switch (image.format) {
      case YuvFileFormat.i420:
        ffiBingings.yuv420_mean_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;

      case YuvFileFormat.nv21:
        ffiBingings.nv21_mean_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        image.uPlane.assignFromPtr(def.pointer.ref.u);
        break;
      case YuvFileFormat.bgra8888:
        ffiBingings.bgra8888_mean_blur(def.pointer, radius, rectPtr);
        image.yPlane.assignFromPtr(def.pointer.ref.y);
        break;
    }
  } finally {
    def.dispose();
  }

  return image;
}
