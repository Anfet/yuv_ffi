import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/images/yuv_i420_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_image.dart';
import 'package:yuv_ffi/src/yuv/yuv_planes.dart';

import '../yuv/yuv_image_rotation.dart';

YuvImage rotate(YuvImage image, YuvImageRotation rotation) {
  int degrees = rotation.degrees;
  if (degrees < 0) {
    degrees = 360 - degrees.abs();
  }
  assert(degrees == 0 || degrees == 90 || degrees == 180 || degrees == 270, 'Can rotate only to 0, 90, 180, 270 degrees');

  if (degrees == 0) {
    return image.copy();
  }

  switch (image.format) {
    case YuvFileFormat.nv21:
      // TODO: Handle this case.
      throw UnimplementedError();
    case YuvFileFormat.i420:
      final (_, ySrc) = image.yPlane.allocatePtr();
      final (_, uSrc) = image.uPlane.allocatePtr();
      final (_, vSrc) = image.vPlane.allocatePtr();

      final dstWidtn = (degrees == 90 || degrees == 270 ? image.height : image.width).toInt();
      final dstHeight = (degrees == 90 || degrees == 270 ? image.width : image.height).toInt();

      final ySrcSize = dstWidtn * dstHeight * image.yPlane.pixelStride;
      final uSrcSize = ((dstWidtn / 2) * (dstHeight / 2) * image.uPlane.pixelStride).toInt();
      final vSrcSize = ((dstWidtn / 2) * (dstHeight / 2) * image.vPlane.pixelStride).toInt();
      final (_, yDst) = YuvPlane.allocate(ySrcSize);
      final (_, uDst) = YuvPlane.allocate(uSrcSize);
      final (_, vDst) = YuvPlane.allocate(vSrcSize);
      try {
        ffiBingings.yuv420_rotate_interleaved(ySrc, uSrc, vSrc, yDst, uDst, vDst, image.width, image.height, degrees, image.yPlane.rowStride,
            image.yPlane.pixelStride, image.uPlane.rowStride, image.uPlane.pixelStride);
        final dstYPlane =
            YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(ySrcSize)), image.yPlane.pixelStride, image.width * image.yPlane.pixelStride);
        final dstuPlane =
            YuvPlane.fromBytes(Uint8List.fromList(uDst.asTypedList(uSrcSize)), image.uPlane.pixelStride, image.width ~/ 2 * image.uPlane.pixelStride);
        final dstvPlane =
            YuvPlane.fromBytes(Uint8List.fromList(vDst.asTypedList(vSrcSize)), image.vPlane.pixelStride, image.width ~/ 2 * image.vPlane.pixelStride);

        // final dstYPlane = YuvPlane.fromBytes(Uint8List.fromList(yDst.asTypedList(ySrcSize)), image.yPlane.pixelStride, dstWidtn);
        // final dstuPlane = YuvPlane.fromBytes(Uint8List.fromList(uDst.asTypedList(uSrcSize)), image.uPlane.pixelStride, dstWidtn);
        // final dstvPlane = YuvPlane.fromBytes(Uint8List.fromList(vDst.asTypedList(vSrcSize)), image.vPlane.pixelStride, dstWidtn);
        return Yuv420Image.fromPlanes(dstWidtn, dstHeight, [dstYPlane, dstuPlane, dstvPlane]);
      } finally {
        calloc.free(ySrc);
        calloc.free(uSrc);
        calloc.free(vSrc);
        calloc.free(yDst);
        calloc.free(uDst);
        calloc.free(vDst);
        // if (rect != null) {
        //   calloc.free(rectPtr);
        // }
      }
  }
}
