import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

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
        final dstYPlane = YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(yDstSize)), image.yPlane.pixelStride, image.width);
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
