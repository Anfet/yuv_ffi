import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui';
import 'package:ffi/ffi.dart';

import 'package:yuv_ffi/yuv_ffi.dart';

import '../loader/loader.dart' show ffiBingings;

YuvImage crop(YuvImage image, Rect rect) {
  switch (image.format) {
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (uSrcsize, uSrc) = image.uPlane.allocatePtr();
      final (vSrcsize, vSrc) = image.vPlane.allocatePtr();


      final (yDstSize, yDst) = YuvPlane.allocate(rect.width.toInt() * rect.height.toInt() * image.yPlane.pixelStride);
      final (uDstSize, uDst) = YuvPlane.allocate(rect.width ~/ 2 * rect.height ~/ 2 * image.uPlane.pixelStride);
      final (vDstSize, vDst) = YuvPlane.allocate(rect.width ~/ 2 * rect.height ~/ 2 * image.vPlane.pixelStride);

      try {
        ffiBingings.yuv420_crop_rect(
          ySrc,
          uSrc,
          vSrc,
          yDst,
          uDst,
          vDst,
          image.width,
          image.height,
          rect.left.toInt(),
          rect.top.toInt(),
          rect.width.toInt(),
          rect.height.toInt(),
          image.yPlane.rowStride,
          image.uPlane.rowStride,
          image.vPlane.rowStride,
          image.yPlane.pixelStride,
          image.uPlane.pixelStride,
          image.vPlane.pixelStride,
        );
        final dstYPlane = YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(yDstSize)), image.yPlane.pixelStride, rect.width.toInt() * image.yPlane.pixelStride);
        final dstuPlane = YuvPlane.fromBytes(Uint8List.fromList(uDst.asTypedList(uDstSize)), image.uPlane.pixelStride, rect.width ~/ 2 * image.uPlane.pixelStride);
        final dstvPlane = YuvPlane.fromBytes(Uint8List.fromList(vDst.asTypedList(vDstSize)), image.vPlane.pixelStride, rect.width ~/ 2 * image.vPlane.pixelStride);
        return Yuv420Image.fromPlanes(rect.width.toInt(), rect.height.toInt(), [dstYPlane, dstuPlane, dstvPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(uSrc);
        calloc.free(vSrc);
        calloc.free(yDst);
        calloc.free(uDst);
        calloc.free(vDst);
      }
    default:
      throw UnimplementedError();
  }
}
