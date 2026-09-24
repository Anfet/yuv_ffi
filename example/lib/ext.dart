import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    // Only the first plane spans the full image height; chroma planes of
    // planar/semi-planar formats hold ceil(height / 2) rows. Camera buffers
    // may omit the unused padding after their last row, while YuvPlane stores
    // a complete `rows * bytesPerRow` layout.
    final isPacked = format.group == ImageFormatGroup.bgra8888;
    final chromaRows = (height + 1) ~/ 2;
    final chromaColumns = (width + 1) ~/ 2;

    final planes = <YuvPlane>[];
    for (int i = 0; i < this.planes.length; i++) {
      final p = this.planes[i];
      final rows = (isPacked || i == 0) ? height : chromaRows;
      final columns = (isPacked || i == 0) ? width : chromaColumns;
      // iOS camera frames are packed BGRA8888. `CameraPlane.bytesPerPixel`
      // is not reliable there, while the native ABI requires the actual
      // four-byte packed-pixel stride.
      final pixelStride = isPacked ? 4 : p.bytesPerPixel ?? 1;
      final sampleBytes = isPacked
          ? pixelStride
          : format.group == ImageFormatGroup.nv21 && i > 0
          ? pixelStride
          : 1;
      final expectedLength = rows * p.bytesPerRow;
      final minimumLength = (rows - 1) * p.bytesPerRow + (columns - 1) * pixelStride + sampleBytes;
      if (p.bytes.length < minimumLength) {
        throw FormatException('Camera plane $i is truncated: expected at least $minimumLength bytes, got ${p.bytes.length}');
      }

      final bytes = Uint8List(expectedLength);
      final copyLength = p.bytes.length < expectedLength ? p.bytes.length : expectedLength;
      bytes.setRange(0, copyLength, p.bytes);
      planes.add(YuvPlane(rows, p.bytesPerRow, pixelStride, bytes));
    }

    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return YuvImage.i420(width, height, planes: planes);

      case ImageFormatGroup.nv21:
        // Deliberately not YuvImage.nv12(): camera frames in this group carry
        // NV21's UV byte order, which only the nv21 label preserves.
        // ignore: deprecated_member_use
        return YuvImage.nv21(width, height, planes: planes);
      case ImageFormatGroup.bgra8888:
        return YuvImage.bgra(width, height, planes: planes);
      case ImageFormatGroup.unknown:
      case ImageFormatGroup.jpeg:
        throw FormatException('Unsupported format for CameraImage to YuvImage; ${format.group}');
    }
  }
}

extension YuvImageToCameraExt on YuvImage {
  InputImage toInputImage() {
    InputImageFormat format;
    switch (this.format) {
      case YuvPixelFormat.i420:
        format = InputImageFormat.yuv420;
        break;
      case YuvPixelFormat.nv12:
        format = InputImageFormat.nv21;
        break;
      case YuvPixelFormat.bgra8888:
        format = InputImageFormat.bgra8888;
        break;
    }

    final meta = InputImageMetadata(size: size, rotation: InputImageRotation.rotation0deg, format: format, bytesPerRow: planes.first.bytesPerRow);

    return InputImage.fromBytes(bytes: toBytes(), metadata: meta);
  }
}
