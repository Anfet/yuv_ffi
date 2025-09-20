import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    final planes = List.of(this.planes.map((p) => YuvPlane(height, p.bytesPerRow, p.bytesPerPixel ?? 1, p.bytes)));
    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return YuvImage.i420(width, height, planes: planes);

      case ImageFormatGroup.nv21:
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
      case YuvFileFormat.i420:
        format = InputImageFormat.yuv420;
        break;
      case YuvFileFormat.nv21:
        format = InputImageFormat.nv21;
        break;
      case YuvFileFormat.bgra8888:
        format = InputImageFormat.bgra8888;
        break;
    }

    final meta = InputImageMetadata(size: size, rotation: InputImageRotation.rotation0deg, format: format, bytesPerRow: planes.first.bytesPerRow);

    return InputImage.fromBytes(bytes: getBytes(), metadata: meta);
  }
}
