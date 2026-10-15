import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  setUpAll(() async {
    await YuvFfi.initialize();
  });

  test('Gaussian blur preserves a constant BGRA pixel for finite positive sigma extremes', () {
    for (final sigma in <double>[1e-200, double.minPositive, 1.5, double.maxFinite]) {
      final plane = YuvPlane(1, 4, 4, Uint8List.fromList(<int>[120, 90, 60, 255]));
      final image = YuvImage.bgra(1, 1, planes: <YuvPlane>[plane]);

      image.applyGaussianBlur(radius: 1, sigma: sigma);

      expect(image.toBgraBytes(), orderedEquals(<int>[120, 90, 60, 255]), reason: 'sigma=$sigma');
    }
  });
}
