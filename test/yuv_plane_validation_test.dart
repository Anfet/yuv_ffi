import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-04: unsafe geometry is rejected with a Dart exception before
/// any FFI/WASM allocation or call, and valid layouts keep working.
void main() {
  /// Builds a plane whose buffer exactly matches its declared geometry.
  YuvPlane plane(int height, int rowStride, [int pixelStride = 1]) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

  group('YuvPlane full-buffer contract', () {
    test('rejects a short buffer instead of zero-padding the tail', () {
      expect(() => YuvPlane(4, 8, 1, Uint8List(8)), throwsArgumentError);
    });

    test('rejects an over-long buffer', () {
      expect(() => YuvPlane(4, 8, 1, Uint8List(64)), throwsArgumentError);
    });

    test('accepts a buffer of exactly height * rowStride', () {
      expect(YuvPlane(4, 8, 1, Uint8List(32)).bytes.length, 32);
    });

    test('rejects negative geometry', () {
      expect(() => YuvPlane(-1, 8), throwsArgumentError);
      expect(() => YuvPlane(4, -8), throwsArgumentError);
      expect(() => YuvPlane(4, 8, -1), throwsArgumentError);
    });

    test('assignFrom requires an exact-length buffer', () {
      final p = plane(4, 8);
      expect(() => p.assignFrom(Uint8List(8)), throwsArgumentError, reason: 'short input would leave a stale tail');
      expect(() => p.assignFrom(Uint8List(64)), throwsArgumentError);
      expect(() => p.assignFrom(Uint8List(32)), returnsNormally);
    });

    test('copy round-trips through the strict constructor', () {
      final p = YuvPlane(3, 5, 1, Uint8List.fromList(List<int>.generate(15, (i) => i)));
      expect(p.copy().bytes, p.bytes);
    });
  });

  group('image dimensions', () {
    test('rejects zero and negative width/height for every format', () {
      // ignore: deprecated_member_use_from_same_package
      for (final format in YuvFileFormat.values) {
        // ignore: deprecated_member_use_from_same_package
        expect(() => YuvImage(format, 0, 8), throwsArgumentError, reason: '${format.name} accepted width 0');
        // ignore: deprecated_member_use_from_same_package
        expect(() => YuvImage(format, 8, 0), throwsArgumentError, reason: '${format.name} accepted height 0');
        // ignore: deprecated_member_use_from_same_package
        expect(() => YuvImage(format, -8, 8), throwsArgumentError, reason: '${format.name} accepted negative width');
        // ignore: deprecated_member_use_from_same_package
        expect(() => YuvImage(format, 8, -8), throwsArgumentError, reason: '${format.name} accepted negative height');
      }
    });
  });

  group('plane count', () {
    test('rejects the wrong number of planes per format', () {
      // The audit case: an I420 image whose planes cannot cover 100x100.
      expect(() => YuvImage.i420(100, 100, planes: [YuvPlane(1, 1)]), throwsArgumentError);

      expect(() => YuvImage.i420(8, 8, planes: [plane(8, 8), plane(4, 4)]), throwsArgumentError, reason: 'I420 needs 3 planes');
      expect(() => YuvImage.nv12(8, 8, planes: [plane(8, 8)]), throwsArgumentError, reason: 'NV needs 2 planes');
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => YuvImage(YuvFileFormat.bgra8888, 8, 8, yPixelStride: 4, planes: [plane(8, 32, 4), plane(4, 8, 2)]),
        throwsArgumentError,
        reason: 'BGRA needs exactly 1 plane',
      );
    });
  });

  group('plane geometry', () {
    test('rejects a luma plane with the wrong height', () {
      expect(() => YuvImage.i420(8, 8, planes: [plane(4, 8), plane(4, 4), plane(4, 4)]), throwsArgumentError);
    });

    test('rejects chroma planes with the wrong height', () {
      expect(() => YuvImage.i420(8, 8, planes: [plane(8, 8), plane(8, 4), plane(4, 4)]), throwsArgumentError);
    });

    test('rejects a row stride too small for the declared width', () {
      expect(
        () => YuvImage.i420(8, 8, planes: [plane(8, 4), plane(4, 4), plane(4, 4)]),
        throwsArgumentError,
        reason: 'a 4-byte row cannot hold 8 luma samples',
      );
    });

    test('rejects a zero pixel stride', () {
      expect(() => YuvImage.i420(8, 8, planes: [YuvPlane(8, 8, 0, Uint8List(64)), plane(4, 4), plane(4, 4)]), throwsArgumentError);
    });

    test('rejects an NV chroma plane that cannot hold the final UV pair', () {
      // Interleaved chroma needs (uvWidth - 1) * pixelStride + 2 bytes per row.
      expect(() => YuvImage.nv12(8, 8, planes: [plane(8, 8), YuvPlane(4, 7, 2, Uint8List(28))]), throwsArgumentError);
    });
  });

  group('valid layouts still work', () {
    test('accepts tight I420, NV21 and BGRA', () {
      expect(YuvImage.i420(8, 8, planes: [plane(8, 8), plane(4, 4), plane(4, 4)]).planes.length, 3);
      expect(YuvImage.nv12(8, 8, planes: [plane(8, 8), plane(4, 8, 2)]).planes.length, 2);
      // ignore: deprecated_member_use_from_same_package
      expect(YuvImage(YuvFileFormat.bgra8888, 8, 8, yPixelStride: 4, planes: [plane(8, 32, 4)]).planes.length, 1);
    });

    test('YuvImage.bgra keeps a valid padded plane instead of repacking it', () {
      // YUV-15 supersedes the earlier YUV-04 behaviour here: the constructor
      // used to repack a padded plane into a tight buffer, which destroyed the
      // caller's layout. Producing a tight buffer is the job of toBgra8888();
      // the constructor deep-copies the plane exactly as declared.
      final image = YuvImage.bgra(8, 8, planes: [plane(8, 32 + 16, 4)]);
      expect(image.yPlane.rowStride, 32 + 16);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.bytes.length, 8 * (32 + 16));
    });

    test('accepts a valid padded BGRA plane without an obscure RangeError', () {
      // Padded rows are a supported layout: 8 px * 4 bytes + 16 bytes padding.
      const width = 8;
      const height = 8;
      const paddedRowStride = width * 4 + 16;
      // ignore: deprecated_member_use_from_same_package
      expect(() => YuvImage(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: [plane(height, paddedRowStride, 4)]), returnsNormally);
    });

    test('accepts padded luma and chroma strides for I420', () {
      expect(() => YuvImage.i420(8, 8, planes: [plane(8, 16), plane(4, 8), plane(4, 8)]), returnsNormally);
    });

    test('accepts odd dimensions using ceil-sized chroma planes', () {
      // 3x5 -> chroma is ceil(3/2) x ceil(5/2) = 2x3.
      expect(() => YuvImage.i420(3, 5, planes: [plane(5, 3), plane(3, 2), plane(3, 2)]), returnsNormally);
      expect(() => YuvImage.nv12(3, 5, planes: [plane(5, 3), plane(3, 4, 2)]), returnsNormally);
      // 1x1 -> chroma is 1x1.
      expect(() => YuvImage.i420(1, 1, planes: [plane(1, 1), plane(1, 1), plane(1, 1)]), returnsNormally);
    });

    test('rejects floor-sized chroma planes for odd dimensions', () {
      // height ~/ 2 == 2 rows is one row short for a 5-row image.
      expect(() => YuvImage.i420(3, 5, planes: [plane(5, 3), plane(2, 2), plane(2, 2)]), throwsArgumentError);
    });

    test('default constructors allocate self-consistent geometry', () {
      // ignore: deprecated_member_use_from_same_package
      for (final format in YuvFileFormat.values) {
        for (final size in const <List<int>>[
          [1, 1],
          [3, 5],
          [8, 8],
          [127, 255],
        ]) {
          // ignore: deprecated_member_use_from_same_package
          final image = YuvImage(format, size[0], size[1]);
          expect(
            // ignore: deprecated_member_use_from_same_package
            () => YuvImage(format, size[0], size[1], planes: image.planes),
            returnsNormally,
            reason: '${format.name} ${size[0]}x${size[1]} failed to re-validate its own planes',
          );
        }
      }
    });
  });

  group('YUV-52 / REL-13: getPixel/setPixel coordinate bounds', () {
    // Regression for the original bug: with the old unchecked `_indexOf`,
    // `(y * rowStride) + (x * pixelStride)` for x=-1, y=1, rowStride=8,
    // pixelStride=1 computed `(1 * 8) + (-1 * 1) = 7`, which is a byte inside
    // row 0's valid range. The negative X silently "borrowed" from the
    // previous row instead of failing, so callers could read/write byte 7 of
    // row 0 while believing they addressed row 1. The fixed code must reject
    // x=-1 before any index arithmetic combines it with y.
    test('x=-1, y=1 throws instead of wrapping into the previous row (regression)', () {
      final plane = YuvPlane(4, 8, 1, Uint8List(32));
      expect(() => plane.getPixel(-1, 1), throwsArgumentError);
      expect(() => plane.setPixel(-1, 1, 42), throwsArgumentError);
    });

    test('negative or out-of-range x/y never touch or corrupt a neighboring row', () {
      const height = 4, rowStride = 8, pixelStride = 1;
      final sentinel = Uint8List.fromList(List<int>.generate(height * rowStride, (i) => (i + 1) % 256));
      final untouched = Uint8List.fromList(sentinel);
      final plane = YuvPlane(height, rowStride, pixelStride, sentinel);

      final invalidCoordinates = <List<int>>[
        [-1, 1], // the regression case: would land on row 0's last byte
        [-1, 0],
        [0, -1],
        [-5, 2],
        [rowStride, 0], // one past the last legal column
        [rowStride, 1],
        [0, height], // one past the last legal row
        [0, height + 5],
      ];

      for (final coordinate in invalidCoordinates) {
        final x = coordinate[0];
        final y = coordinate[1];
        expect(() => plane.getPixel(x, y), throwsArgumentError, reason: 'getPixel($x, $y) should have been rejected');
        expect(() => plane.setPixel(x, y, 99), throwsArgumentError, reason: 'setPixel($x, $y) should have been rejected');
        expect(plane.bytes, untouched, reason: 'a rejected setPixel($x, $y) must not mutate any byte');
      }
    });

    test('a huge x that would overflow x * pixelStride throws RangeError-style ArgumentError, not silently succeeding', () {
      // 1 << 62 chosen so that x * pixelStride (pixelStride = 4) overflows the
      // 64-bit int range: (1 << 62) * 4 == 1 << 64, which wraps to 0 in Dart's
      // 64-bit int arithmetic. A naive `x * pixelStride < rowStride` bounds
      // check would see 0 < rowStride and wrongly accept it. The fixed check
      // never multiplies x by pixelStride to bound it, so it must still
      // reject this value cleanly.
      const hugeX = 1 << 62;
      final plane = YuvPlane(4, 8, 4, Uint8List(32));

      expect(() => plane.getPixel(hugeX, 0), throwsArgumentError);
      expect(() => plane.setPixel(hugeX, 0, 1), throwsArgumentError);

      // Sanity: confirm the naive formula really would have overflowed/wrapped,
      // to document why the direct multiply-and-compare approach is unsafe.
      expect(hugeX * 4, 0, reason: 'the naive x * pixelStride computation wraps to 0 on overflow');
    });

    test('pixelStride == 0 throws cleanly instead of a division/comparison artifact', () {
      final plane = YuvPlane(4, 8, 0, Uint8List(32));
      expect(() => plane.getPixel(0, 0), throwsArgumentError);
      expect(() => plane.setPixel(0, 0, 1), throwsArgumentError);
    });

    test('debug and release semantics are identical (no assert-only guard)', () {
      // This test runs the same in both modes because the guards are plain
      // `if`/`throw` statements, not `assert`, which Flutter strips in
      // release/profile builds. Asserting `throwsArgumentError` here exercises
      // exactly that: the check must fire unconditionally.
      final plane = YuvPlane(4, 8, 1, Uint8List(32));
      expect(() => plane.getPixel(-1, 0), throwsArgumentError);
      expect(() => plane.getPixel(0, -1), throwsArgumentError);
    });

    group('boundary-exact legal coordinates keep working', () {
      test('rowStride=8, pixelStride=1 -> max legal x is 7', () {
        final plane = YuvPlane(2, 8, 1, Uint8List(16));
        expect(() => plane.getPixel(7, 1), returnsNormally);
        expect(() => plane.getPixel(8, 1), throwsArgumentError);
      });

      test('rowStride=10, pixelStride=4 -> max legal x is 2', () {
        // x*pixelStride must stay <= rowStride - 1 == 9, so x=2 (8 <= 9) is
        // legal and x=3 (12 > 9) is not.
        final plane = YuvPlane(2, 10, 4, Uint8List(20));
        expect(() => plane.getPixel(2, 0), returnsNormally);
        expect(() => plane.getPixel(3, 0), throwsArgumentError);
      });

      test('max legal y still works and height is still exclusive', () {
        final plane = YuvPlane(4, 8, 1, Uint8List(32));
        expect(() => plane.getPixel(0, 3), returnsNormally);
        expect(() => plane.getPixel(0, 4), throwsArgumentError);
      });

      test('setPixel/getPixel round-trip at every corner of a tight buffer', () {
        final plane = YuvPlane(4, 8, 1, Uint8List(32));
        plane.setPixel(0, 0, 11);
        plane.setPixel(7, 0, 22);
        plane.setPixel(0, 3, 33);
        plane.setPixel(7, 3, 44);

        expect(plane.getPixel(0, 0), 11);
        expect(plane.getPixel(7, 0), 22);
        expect(plane.getPixel(0, 3), 33);
        expect(plane.getPixel(7, 3), 44);
      });

      test('a padded row stride still allows the full pixel-stride-scaled width', () {
        // width 4 * pixelStride 4 = 16 bytes of pixels, padded to a 24-byte row.
        final plane = YuvPlane(2, 24, 4, Uint8List(48));
        expect(() => plane.getPixel(3, 0), returnsNormally); // 3*4=12 <= 23
        expect(() => plane.getPixel(5, 0), returnsNormally); // 5*4=20 <= 23
        expect(() => plane.getPixel(6, 0), throwsArgumentError); // 6*4=24 > 23
      });
    });
  });
}
