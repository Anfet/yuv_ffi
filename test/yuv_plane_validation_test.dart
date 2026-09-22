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
      for (final format in YuvFileFormat.values) {
        expect(() => YuvImage(format, 0, 8), throwsArgumentError, reason: '${format.name} accepted width 0');
        expect(() => YuvImage(format, 8, 0), throwsArgumentError, reason: '${format.name} accepted height 0');
        expect(() => YuvImage(format, -8, 8), throwsArgumentError, reason: '${format.name} accepted negative width');
        expect(() => YuvImage(format, 8, -8), throwsArgumentError, reason: '${format.name} accepted negative height');
      }
    });
  });

  group('plane count', () {
    test('rejects the wrong number of planes per format', () {
      // The audit case: an I420 image whose planes cannot cover 100x100.
      expect(() => YuvImage.i420(100, 100, planes: [YuvPlane(1, 1)]), throwsArgumentError);

      expect(() => YuvImage.i420(8, 8, planes: [plane(8, 8), plane(4, 4)]), throwsArgumentError, reason: 'I420 needs 3 planes');
      expect(() => YuvImage.nv21(8, 8, planes: [plane(8, 8)]), throwsArgumentError, reason: 'NV needs 2 planes');
      expect(
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
      expect(() => YuvImage.nv21(8, 8, planes: [plane(8, 8), YuvPlane(4, 7, 2, Uint8List(28))]), throwsArgumentError);
    });
  });

  group('valid layouts still work', () {
    test('accepts tight I420, NV21 and BGRA', () {
      expect(YuvImage.i420(8, 8, planes: [plane(8, 8), plane(4, 4), plane(4, 4)]).planes.length, 3);
      expect(YuvImage.nv21(8, 8, planes: [plane(8, 8), plane(4, 8, 2)]).planes.length, 2);
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
      expect(() => YuvImage(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: [plane(height, paddedRowStride, 4)]), returnsNormally);
    });

    test('accepts padded luma and chroma strides for I420', () {
      expect(() => YuvImage.i420(8, 8, planes: [plane(8, 16), plane(4, 8), plane(4, 8)]), returnsNormally);
    });

    test('accepts odd dimensions using ceil-sized chroma planes', () {
      // 3x5 -> chroma is ceil(3/2) x ceil(5/2) = 2x3.
      expect(() => YuvImage.i420(3, 5, planes: [plane(5, 3), plane(3, 2), plane(3, 2)]), returnsNormally);
      expect(() => YuvImage.nv21(3, 5, planes: [plane(5, 3), plane(3, 4, 2)]), returnsNormally);
      // 1x1 -> chroma is 1x1.
      expect(() => YuvImage.i420(1, 1, planes: [plane(1, 1), plane(1, 1), plane(1, 1)]), returnsNormally);
    });

    test('rejects floor-sized chroma planes for odd dimensions', () {
      // height ~/ 2 == 2 rows is one row short for a 5-row image.
      expect(() => YuvImage.i420(3, 5, planes: [plane(5, 3), plane(2, 2), plane(2, 2)]), throwsArgumentError);
    });

    test('default constructors allocate self-consistent geometry', () {
      for (final format in YuvFileFormat.values) {
        for (final size in const <List<int>>[
          [1, 1],
          [3, 5],
          [8, 8],
          [127, 255],
        ]) {
          final image = YuvImage(format, size[0], size[1]);
          expect(
            () => YuvImage(format, size[0], size[1], planes: image.planes),
            returnsNormally,
            reason: '${format.name} ${size[0]}x${size[1]} failed to re-validate its own planes',
          );
        }
      }
    });
  });
}
