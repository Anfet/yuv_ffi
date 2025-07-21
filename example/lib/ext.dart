import 'package:camera/camera.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    final planes = List.of(this.planes.map((p) => YuvPlane(height, p.bytesPerRow, p.bytesPerPixel ?? 1, p.bytes)));
    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return Yuv420Image.fromPlanes(width, height, planes);

      case ImageFormatGroup.nv21:
      case ImageFormatGroup.unknown:
      case ImageFormatGroup.bgra8888:
      case ImageFormatGroup.jpeg:
        throw FormatException('Not supported format');
    }
  }
}
