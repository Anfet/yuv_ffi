import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage flipHorizontally(YuvImage image) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (uSrcsize, uSrc) = image.uPlane.allocatePtr();
      final (vSrcsize, vSrc) = image.vPlane.allocatePtr();

      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final (uDstSize, uDst) = YuvPlane.allocate(uSrcsize);
      final (vDstSize, vDst) = YuvPlane.allocate(vSrcsize);
      try {
        ffiBingings.yuv420_flip_horizontally(ySrc, uSrc, vSrc, yDst, uDst, vDst, image.width, image.height, image.yPlane.rowStride,
            image.yPlane.pixelStride, image.uPlane.rowStride, image.uPlane.pixelStride);
        final dstYPlane =
            YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(yDstSize)), image.yPlane.pixelStride, image.width * image.yPlane.pixelStride);
        final dstuPlane = YuvPlane.fromBytes(
            Uint8List.fromList(uDst.asTypedList(uDstSize)), image.uPlane.pixelStride, (image.width ~/ 2) * image.uPlane.pixelStride);
        final dstvPlane = YuvPlane.fromBytes(
            Uint8List.fromList(vDst.asTypedList(vDstSize)), image.vPlane.pixelStride, (image.width ~/ 2) * image.vPlane.pixelStride);
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

Future<YuvImage> flipVertically(YuvImage image) async {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();
      final (uSrcsize, uSrc) = image.uPlane.allocatePtr();
      final (vSrcsize, vSrc) = image.vPlane.allocatePtr();

      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final (uDstSize, uDst) = YuvPlane.allocate(uSrcsize);
      final (vDstSize, vDst) = YuvPlane.allocate(vSrcsize);
      try {
        ffiBingings.yuv420_flip_vertically(ySrc, uSrc, vSrc, yDst, uDst, vDst, image.width, image.height, image.yPlane.rowStride,
            image.yPlane.pixelStride, image.uPlane.rowStride, image.uPlane.pixelStride, nullptr);
        final dstYPlane =
            YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(yDstSize)), image.yPlane.pixelStride, image.width * image.yPlane.pixelStride);
        final dstuPlane =
            YuvPlane.fromBytes(Uint8List.fromList(uDst.asTypedList(uDstSize)), image.uPlane.pixelStride, image.width ~/ 2 * image.uPlane.pixelStride);
        final dstvPlane =
            YuvPlane.fromBytes(Uint8List.fromList(vDst.asTypedList(vDstSize)), image.vPlane.pixelStride, image.width ~/ 2 * image.vPlane.pixelStride);
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
