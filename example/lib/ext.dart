import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    final planes = List.of(this.planes.map((p) => YuvPlane(height, p.bytesPerRow, p.bytesPerPixel ?? 1, p.bytes)));
    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return Yuv420Image.fromPlanes(width, height, planes);

      case ImageFormatGroup.nv21:
        return YuvNV21Image.fromPlanes(width, height, planes);
      case ImageFormatGroup.unknown:
      case ImageFormatGroup.bgra8888:
      case ImageFormatGroup.jpeg:
        throw FormatException('Not supported format');
    }
  }
}

extension YuvImageToCameraExt on YuvImage {
  InputImage toInputImage() {
    InputImageFormat format;
    switch (this.runtimeType) {
      case Yuv420Image:
        format = InputImageFormat.yuv420;
        break;
      case YuvNV21Image:
        format = InputImageFormat.nv21;
      default:
        throw FormatException('Not supported format');
    }

    final meta = InputImageMetadata(
      size: size,
      rotation: InputImageRotation.rotation0deg,
      format: format,
      bytesPerRow: planes.first.bytesPerRow,
    );

    final WriteBuffer buf = WriteBuffer();
    for (final p in planes) {
      buf.putUint8List(p.bytes);
    }
    final bytes = buf.done().buffer.asUint8List();

    return InputImage.fromBytes(bytes: bytes, metadata: meta);
  }
}
