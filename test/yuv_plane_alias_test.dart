@Tags(['contract'])
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies the public row and pixel stride accessors.
void main() {
  group('plane stride accessors', () {
    test('bytesPerPixel reports pixelStride', () {
      final plane = YuvPlane(4, 32, 4, Uint8List(4 * 32));

      expect(plane.bytesPerPixel, plane.pixelStride);
      expect(plane.bytesPerPixel, 4);
    });

    test('bytesPerRow still reports rowStride', () {
      final plane = YuvPlane(4, 32, 4, Uint8List(4 * 32));

      expect(plane.bytesPerRow, plane.rowStride);
      expect(plane.bytesPerRow, 32);
    });

    test('the aliases follow a padded layout rather than a computed one', () {
      // rowStride here is deliberately wider than width * pixelStride.
      final plane = YuvPlane(2, 48, 4, Uint8List(2 * 48));

      expect(plane.bytesPerRow, 48);
      expect(plane.bytesPerPixel, 4);
    });
  });
}
