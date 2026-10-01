@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('root export exposes the current construction, plane and conversion API', () {
    final image = YuvImage.fromRgbaBytes(Uint8List(16), width: 2, height: 2, format: YuvPixelFormat.bgra8888);
    final plane = image.yPlane;

    expect(plane.bytesPerPixel, 4);
    expect(image.copy().toBgraBytes(), orderedEquals(image.toBgraBytes()));
    expect(YuvImageRotation.rotation90.degrees, 90);
  });
}
