import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

YuvImage blackwhite(YuvImage image) {
  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (ySrcSize, ySrc) = image.yPlane.allocatePtr();

      final uSrcSize = image.uPlane.width * image.uPlane.height * image.uPlane.pixelStride;
      final (yDstSize, yDst) = YuvPlane.allocate(ySrcSize);
      final (uDstSize, uDst) = YuvPlane.allocate(uSrcSize);
      final (vDstSize, vDst) = YuvPlane.allocate(uSrcSize);

      final yRowStride = image.yPlane.rowStride;
      final yPixelStride = image.yPlane.pixelStride;
      final uvRowStride = image.uPlane.rowStride;
      final uvPixelStride = image.uPlane.pixelStride;
      try {
        ffiBingings.yuv420_blackwhite(ySrc, yRowStride, yPixelStride, uvRowStride, uvPixelStride, image.width, image.height, yDst, uDst, vDst);
        final dstYPlane = YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(yDstSize)), image.yPlane.pixelStride, image.width);
        final dstuPlane = YuvPlane.fromBytes(Uint8List.fromList(uDst.asTypedList(uDstSize)), image.uPlane.pixelStride, image.width);
        final dstvPlane = YuvPlane.fromBytes(Uint8List.fromList(vDst.asTypedList(vDstSize)), image.vPlane.pixelStride, image.width);
        return Yuv420Image.fromPlanes(image.width, image.height, [dstYPlane, dstuPlane, dstvPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(yDst);
        calloc.free(uDst);
        calloc.free(vDst);
      }
  }
}
