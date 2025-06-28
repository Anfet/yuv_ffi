import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    final planes = List.of(this.planes.map((p) => p.toYuvPlane()));
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

extension on Plane {
  YuvPlane toYuvPlane() {
    return YuvPlane.fromBytes(bytes, bytesPerPixel!, bytesPerRow);
  }
}
