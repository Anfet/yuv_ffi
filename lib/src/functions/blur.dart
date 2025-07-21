import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage gaussianBlur(YuvImage image, {int radius = 2, int sigma = 2}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (uSrcSize, uSrc) = image.uPlane.allocatePtr();
      final (vSrcSize, vSrc) = image.vPlane.allocatePtr();

      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final (uDstSize, uDst) = YuvPlane.allocate(uSrcSize);
      final (vDstSize, vDst) = YuvPlane.allocate(vSrcSize);

      final yRowStride = image.yPlane.rowStride;
      final yPixelStride = image.yPlane.pixelStride;
      final uvRowStride = image.uPlane.rowStride;
      final uvPixelStride = image.uPlane.pixelStride;
      try {
        ffiBingings.yuv420_gaussblur(
          ySrc,
          uSrc,
          vSrc,
          yRowStride,
          yPixelStride,
          uvRowStride,
          uvPixelStride,
          image.width,
          image.height,
          yDst,
          uDst,
          vDst,
          radius,
          sigma,
        );
        final dstYPlane = YuvPlane(image.height, yRowStride, yPixelStride, yDst.asTypedList(yDstSize));
        final dstuPlane = YuvPlane(image.height, uvRowStride, uvPixelStride, uDst.asTypedList(uDstSize));
        final dstvPlane = YuvPlane(image.height, uvRowStride, uvPixelStride, vDst.asTypedList(uDstSize));
        return Yuv420Image.fromPlanes(image.width, image.height, [dstYPlane, dstuPlane, dstvPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(uSrc);
        calloc.free(vSrc);
        calloc.free(yDst);
        calloc.free(uDst);
        calloc.free(vDst);
      }
  }
}

YuvImage boxBlur(YuvImage image, {int radius = 10, ui.Rect? rect}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final rectPtr = rect == null ? nullptr : calloc.allocate<Uint32>(4 * 32);
      if (rect != null) {
        rectPtr.asTypedList(32)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }

      final yRowStride = image.yPlane.rowStride;
      final yPixelStride = image.yPlane.pixelStride;
      try {
        ffiBingings.yuv420_box_blur(ySrc, yDst, image.width, image.height, yRowStride, yPixelStride, radius, rectPtr);
        final dstYPlane = YuvPlane(image.height, yRowStride, yPixelStride, yDst.asTypedList(yDstSize));
        return Yuv420Image.fromPlanes(image.width, image.height, [dstYPlane, image.uPlane, image.vPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(yDst);
        if (rect != null) {
          calloc.free(rectPtr);
        }
      }
  }
}

YuvImage meanBlur(YuvImage image, {int radius = 2, ui.Rect? rect}) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final rectPtr = rect == null ? nullptr : calloc.allocate<Uint8>(4);
      if (rect != null) {
        rectPtr.asTypedList(4)
          ..[0] = rect.left.toInt()
          ..[1] = rect.top.toInt()
          ..[2] = rect.right.toInt()
          ..[3] = rect.bottom.toInt();
      }

      final yRowStride = image.yPlane.rowStride;
      final yPixelStride = image.yPlane.pixelStride;
      try {
        ffiBingings.yuv420_mean_blur(ySrc, yDst, image.width, image.height, radius, yRowStride, yPixelStride, rectPtr);
        final dstYPlane = YuvPlane(image.height, yRowStride, yPixelStride, yDst.asTypedList(yDstSize));
        return Yuv420Image.fromPlanes(image.width, image.height, [dstYPlane, image.uPlane, image.vPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(yDst);
        if (rect != null) {
          calloc.free(rectPtr);
        }
      }
  }
}
