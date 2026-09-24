import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-12: packing a BGRA plane whose `pixelStride` exceeds 4 must
/// exclude the per-pixel gap byte(s) as well as row padding beyond
/// `width * pixelStride`, and must never modify the source plane.
void main() {
  group('BGRA pixel gap packing', () {
    test('width=2, pixelStride=5 excludes the one-byte-per-pixel gap', () {
      const width = 2;
      const height = 1;
      const pixelStride = 5; // 4 real bytes + 1 gap byte per pixel.
      const rowStride = width * pixelStride; // 10, no extra row padding here.

      // Pixel 0: B0 G0 R0 A0 <gap>; pixel 1: B1 G1 R1 A1 <gap>.
      final source = Uint8List.fromList([10, 11, 12, 13, 0xEE, 20, 21, 22, 23, 0xEE]);
      final plane = YuvPlane(height, rowStride, pixelStride, source);
      final image = YuvImage.bgra(width, height, planes: [plane]);

      final packed = image.toBgra8888();

      expect(packed, [10, 11, 12, 13, 20, 21, 22, 23], reason: 'the gap byte between pixels must not leak into the tight result');
    });

    test('gap and row padding are distinguishable when both are present', () {
      const width = 2;
      const height = 2;
      const pixelStride = 5; // 1-byte gap per pixel.
      const rowPadding = 3; // extra bytes after the last pixel of each row.
      const rowStride = width * pixelStride + rowPadding;

      final source = Uint8List(rowStride * height);
      // Row 0.
      source.setRange(0, 4, [1, 2, 3, 4]); // pixel (0,0)
      source[4] = 0xEE; // pixel gap
      source.setRange(5, 9, [5, 6, 7, 8]); // pixel (1,0)
      source[9] = 0xEE; // pixel gap
      source.setRange(10, 13, [0xCC, 0xCC, 0xCC]); // row padding
      // Row 1.
      final row1 = rowStride;
      source.setRange(row1 + 0, row1 + 4, [9, 10, 11, 12]); // pixel (0,1)
      source[row1 + 4] = 0xEE;
      source.setRange(row1 + 5, row1 + 9, [13, 14, 15, 16]); // pixel (1,1)
      source[row1 + 9] = 0xEE;
      source.setRange(row1 + 10, row1 + 13, [0xCC, 0xCC, 0xCC]);

      final plane = YuvPlane(height, rowStride, pixelStride, source);
      final image = YuvImage.bgra(width, height, planes: [plane]);

      final packed = image.toBgra8888();

      expect(packed, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], reason: 'neither the per-pixel gap nor the row padding may appear');
    });

    test('the source plane is left unmodified', () {
      const width = 2;
      const height = 1;
      const pixelStride = 5;
      const rowStride = width * pixelStride;

      final source = Uint8List.fromList([10, 11, 12, 13, 0xEE, 20, 21, 22, 23, 0xEE]);
      final originalCopy = Uint8List.fromList(source);
      final plane = YuvPlane(height, rowStride, pixelStride, source);
      final image = YuvImage.bgra(width, height, planes: [plane]);

      image.toBgra8888();

      expect(image.yPlane.bytes, originalCopy, reason: 'packing into a tight buffer must not mutate the source plane');
    });

    test('a tight pixelStride-4 plane is unaffected by the fix', () {
      final image = YuvImage.bgra(2, 2);
      image.yPlane.assignFrom(Uint8List.fromList(List<int>.generate(16, (i) => i)));

      expect(image.toBgra8888(), List<int>.generate(16, (i) => i));
    });
  });
}
