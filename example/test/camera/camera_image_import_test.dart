import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/camera/camera_image_import.dart';
import 'package:yuv_ffi_example/ext.dart';

void main() {
  test('pixel-stride-2 import matches the previous deinterleaving path', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 16), _plane(4, 2, 2, 8), _plane(4, 2, 2, 8)]);
    final imported = importCameraImage(image);
    final previous = image.toYuvImage();
    for (int plane = 0; plane < previous.planes.length; plane++) {
      final width = plane == 0 ? 4 : 2;
      final height = plane == 0 ? 4 : 2;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(imported.planes[plane].getPixel(x, y), previous.planes[plane].getPixel(x, y));
        }
      }
    }
  });

  test('preserves yuv420 pixel stride, padding, and zero-fills a short final row', () {
    final image = _cameraImage(ImageFormatGroup.yuv420, 4, 4, [_plane(4, 4, 1, 14), _plane(4, 2, 2, 7), _plane(4, 2, 2, 8)]);
    final imported = importCameraImage(image);
    expect(imported.format, YuvPixelFormat.i420);
    expect(imported.uPlane.pixelStride, 2);
    expect(imported.planes.map((plane) => plane.rowStride), [4, 4, 4]);
    expect(imported.yPlane.bytes.length, 16);
    expect(imported.yPlane.bytes.sublist(14), [0, 0]);
  });

  test('imports padded BGRA without repacking', () {
    final image = _cameraImage(ImageFormatGroup.bgra8888, 2, 2, [_plane(12, 2, 4, 24)]);
    final imported = importCameraImage(image);
    expect(imported.format, YuvPixelFormat.bgra8888);
    expect(imported.yPlane.rowStride, 12);
    expect(imported.yPlane.pixelStride, 4);
  });

  test('rejects formats the source never requests', () {
    for (final group in <ImageFormatGroup>[ImageFormatGroup.nv21, ImageFormatGroup.jpeg, ImageFormatGroup.unknown]) {
      expect(() => importCameraImage(_cameraImage(group, 2, 2, [_plane(2, 2, 1, 4)])), throwsFormatException);
    }
  });
}

CameraImage _cameraImage(ImageFormatGroup group, int width, int height, List<CameraImagePlane> planes) => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: CameraImageFormat(group, raw: group.name),
    width: width,
    height: height,
    planes: planes,
  ),
);

CameraImagePlane _plane(int rowStride, int height, int pixelStride, int length) => CameraImagePlane(
  bytes: Uint8List.fromList(List<int>.generate(length, (index) => index + 1)),
  bytesPerRow: rowStride,
  bytesPerPixel: pixelStride,
  width: rowStride ~/ pixelStride,
  height: height,
);
