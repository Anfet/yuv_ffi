import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-27: the misspelled `bytesPerPixes` getter keeps working while
/// the correctly spelled `bytesPerPixel` becomes the one to use.
///
/// Both must report `pixelStride`, so a patch update cannot change what an
/// existing caller reads.
void main() {
  group('plane stride aliases', () {
    test('bytesPerPixel reports pixelStride', () {
      final plane = YuvPlane(4, 32, 4, Uint8List(4 * 32));

      expect(plane.bytesPerPixel, plane.pixelStride);
      expect(plane.bytesPerPixel, 4);
    });

    test('the misspelled alias still compiles and agrees with the new one', () {
      final plane = YuvPlane(4, 32, 4, Uint8List(4 * 32));

      // ignore: deprecated_member_use_from_same_package
      expect(plane.bytesPerPixes, plane.bytesPerPixel);
      // ignore: deprecated_member_use_from_same_package
      expect(plane.bytesPerPixes, plane.pixelStride);
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
