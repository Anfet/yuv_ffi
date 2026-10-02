import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Imports a camera frame into tight planes suitable for the YUV backend.
YuvImage importCameraImage(CameraImage image) {
  final isPacked = image.format.group == ImageFormatGroup.bgra8888;
  final chromaRows = (image.height + 1) ~/ 2;
  final chromaColumns = (image.width + 1) ~/ 2;
  final planes = <YuvPlane>[];
  for (var index = 0; index < image.planes.length; index++) {
    final plane = image.planes[index];
    final rows = isPacked || index == 0 ? image.height : chromaRows;
    final columns = isPacked || index == 0 ? image.width : chromaColumns;
    final pixelStride = isPacked ? 4 : plane.bytesPerPixel ?? 1;
    final sampleBytes = isPacked ? pixelStride : 1;
    final minimumLength = (rows - 1) * plane.bytesPerRow + (columns - 1) * pixelStride + sampleBytes;
    if (plane.bytes.length < minimumLength) {
      throw FormatException('Camera plane $index is truncated: expected at least $minimumLength bytes, got ${plane.bytes.length}');
    }
    planes.add(_packPlane(plane.bytes, rows, columns, plane.bytesPerRow, pixelStride, sampleBytes));
  }
  return switch (image.format.group) {
    ImageFormatGroup.yuv420 => YuvImage.i420(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve),
    ImageFormatGroup.bgra8888 => YuvImage.bgra(image.width, image.height, planes: planes, layout: YuvPlaneLayout.preserve),
    _ => throw FormatException('Unsupported format for CameraImage import: ${image.format.group}'),
  };
}

YuvPlane _packPlane(Uint8List source, int rows, int columns, int sourceRowStride, int sourcePixelStride, int sampleBytes) {
  final tightRowStride = columns * sampleBytes;
  final packed = Uint8List(rows * tightRowStride);
  for (var row = 0; row < rows; row++) {
    final sourceStart = row * sourceRowStride;
    final targetStart = row * tightRowStride;
    if (sourcePixelStride == sampleBytes) {
      packed.setRange(targetStart, targetStart + tightRowStride, source, sourceStart);
      continue;
    }
    for (var column = 0; column < columns; column++) {
      final sourceSample = sourceStart + column * sourcePixelStride;
      final targetSample = targetStart + column * sampleBytes;
      packed.setRange(targetSample, targetSample + sampleBytes, source, sourceSample);
    }
  }
  return YuvPlane(rows, tightRowStride, sampleBytes, packed);
}
