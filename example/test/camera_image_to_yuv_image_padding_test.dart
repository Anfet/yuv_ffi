import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// VIEW-01A: `camera_desktop`'s BGRA8888 frames report `bytesPerRow` from the
/// native capture backend, which can exceed `width * 4` (row padding for
/// alignment). This test does not depend on `camera_desktop` or a physical
/// camera: it builds the same [CameraImageData] shape the platform interface
/// hands to [CameraImage.fromPlatformInterface] and exercises the
/// `isPacked` branch of [CameraImageExt.toYuvImage] with a padded stride,
/// forcing [kYuvCameraPreviewPackPlanes] off (PACK-01C made dense import the
/// default) to specifically cover the padded-preserving path this test is
/// named for.
void main() {
  setUp(() => kYuvCameraPreviewPackPlanes = false);
  tearDown(() => kYuvCameraPreviewPackPlanes = true);

  test('toYuvImage keeps a padded BGRA row stride without shifting pixels', () {
    const width = 3;
    const height = 2;
    const tightRowBytes = width * 4; // 12
    const paddedBytesPerRow = tightRowBytes + 8; // 20, e.g. 4-byte alignment slack

    // Row 0: B G R A pixels 0..2, then 8 padding bytes the plugin may not zero.
    // Row 1: same shape, distinct values so a row-stride bug is visible.
    final bytes = Uint8List(paddedBytesPerRow * height);
    void setPixel(int row, int col, int b, int g, int r, int a) {
      final offset = row * paddedBytesPerRow + col * 4;
      bytes[offset] = b;
      bytes[offset + 1] = g;
      bytes[offset + 2] = r;
      bytes[offset + 3] = a;
    }

    setPixel(0, 0, 10, 20, 30, 255);
    setPixel(0, 1, 11, 21, 31, 255);
    setPixel(0, 2, 12, 22, 32, 255);
    setPixel(1, 0, 40, 50, 60, 255);
    setPixel(1, 1, 41, 51, 61, 255);
    setPixel(1, 2, 42, 52, 62, 255);
    // Fill the padding bytes with a sentinel so a bug that reads past the
    // declared row would surface as unexpected pixel values, not zeros.
    for (var row = 0; row < height; row++) {
      for (var col = tightRowBytes; col < paddedBytesPerRow; col++) {
        bytes[row * paddedBytesPerRow + col] = 0xEE;
      }
    }

    final data = CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
      width: width,
      height: height,
      planes: [CameraImagePlane(bytes: bytes, bytesPerRow: paddedBytesPerRow, bytesPerPixel: 4, width: width, height: height)],
    );
    final image = CameraImage.fromPlatformInterface(data);

    final yuv = image.toYuvImage();

    expect(yuv.format, YuvPixelFormat.bgra8888);
    expect(yuv.size, const Size(3, 2));
    expect(yuv.planes, hasLength(1));
    // YuvPlane preserves the source's bytesPerRow rather than tightening it:
    // the native BGRA→whatever conversion path relies on this stride, and
    // tightening here would silently reinterpret the padded plugin buffer.
    expect(yuv.planes.first.bytesPerRow, paddedBytesPerRow);

    final packed = yuv.toBgraBytes();
    expect(packed, hasLength(width * height * 4));
    // Row 0, pixel-by-pixel: padding must not have shifted columns.
    expect(packed.sublist(0, 4), [10, 20, 30, 255]);
    expect(packed.sublist(4, 8), [11, 21, 31, 255]);
    expect(packed.sublist(8, 12), [12, 22, 32, 255]);
    // Row 1: proves the row stride, not just the first row, is honoured.
    expect(packed.sublist(12, 16), [40, 50, 60, 255]);
    expect(packed.sublist(16, 20), [41, 51, 61, 255]);
    expect(packed.sublist(20, 24), [42, 52, 62, 255]);
  });
}
