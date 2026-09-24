import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-03: the new `YuvImage.nv12`, `.allocate` and `.fromRgbaBytes`
/// factories follow the geometry rules of design doc section 4 -- tight,
/// padded and gapped layouts, even/odd dimensions, and invalid-argument
/// rejection -- and are reachable from the root export.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  group('root export compile check', () {
    test('YuvImage.nv12 and YuvImage.allocate are reachable from package:yuv_ffi/yuv_ffi.dart', () {
      expect(YuvImage.nv12(2, 2), isA<YuvImage>());
      expect(YuvImage.allocate(YuvPixelFormat.i420, 2, 2), isA<YuvImage>());
    });

    test(
      'YuvImage.fromRgbaBytes is reachable from package:yuv_ffi/yuv_ffi.dart',
      () {
        expect(YuvImage.fromRgbaBytes(Uint8List(2 * 2 * 4), width: 2, height: 2, format: YuvPixelFormat.bgra8888), isA<YuvImage>());
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('YuvImage.nv12', () {
    test('defaults to interleaved chroma pixel stride 2', () {
      final image = YuvImage.nv12(4, 4);
      expect(image.uPlane.pixelStride, 2);
      expect(image.planes.length, 2);
    });

    test('an explicit stride above the default is honored, not clamped back down', () {
      // Unlike the legacy nv21 factory, nv12 does not fold a larger explicit
      // stride into the default: it is a real pixel gap the ABI's
      // stride-aware kernels already support (design doc section 11).
      final image = YuvImage.nv12(4, 4, uvPixelStride: 3);
      expect(image.uPlane.pixelStride, 3);
      expect(image.uPlane.rowStride, 2 * 3);
    });

    test('an explicit stride below the packed-pair minimum throws instead of being silently clamped', () {
      // The architect decision for REL-03: unlike the legacy nv21 factory
      // (which clamps up to 2), nv12 rejects an invalid stride outright.
      expect(() => YuvImage.nv12(4, 4, uvPixelStride: 1), throwsArgumentError);
      expect(() => YuvImage.nv12(4, 4, uvPixelStride: 0), throwsArgumentError);
      expect(() => YuvImage.nv12(4, 4, uvPixelStride: -1), throwsArgumentError);
    });

    test('even dimensions produce exact half-size chroma', () {
      final image = YuvImage.nv12(8, 6);
      expect(image.uPlane.height, 3);
      expect(image.uPlane.rowStride, 4 * 2);
    });

    test('odd dimensions keep the trailing half chroma row/column', () {
      final image = YuvImage.nv12(3, 5);
      expect(image.uPlane.height, 3);
      expect(image.uPlane.rowStride, 2 * 2);
    });

    test('tight, row-padded and pixel-gapped layouts are all accepted through an explicit plane list', () {
      YuvPlane filled(int height, int rowStride, int pixelStride) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

      // Tight.
      expect(() => YuvImage.nv12(4, 4, planes: [filled(4, 4, 1), filled(2, 4, 2)]), returnsNormally);
      // Row-padded (rowStride wider than uvWidth * pixelStride, pixelStride still 2).
      expect(() => YuvImage.nv12(4, 4, planes: [filled(4, 8, 1), filled(2, 10, 2)]), returnsNormally);
      // Pixel-gapped (pixelStride 3: one gap byte after every packed UV pair).
      expect(() => YuvImage.nv12(4, 4, planes: [filled(4, 4, 1), filled(2, 6, 3)]), returnsNormally);
      // Still rejected below the packed-pair minimum, even through an explicit plane.
      expect(() => YuvImage.nv12(4, 4, planes: [filled(4, 4, 1), filled(2, 2, 1)]), throwsArgumentError);
    });

    test('invalid arguments are rejected', () {
      expect(() => YuvImage.nv12(0, 4), throwsArgumentError);
      expect(() => YuvImage.nv12(4, -1), throwsArgumentError);
      expect(() => YuvImage.nv12(4, 4, planes: [YuvPlane(4, 4, 1)]), throwsArgumentError, reason: 'NV12 requires exactly two planes');
    });

    test('does not affect the legacy nv21 factory: an explicit stride above 2 is still rejected there', () {
      YuvPlane filled(int height, int rowStride, int pixelStride) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));
      expect(
        () => YuvImage.nv21(4, 4, planes: [filled(4, 4, 1), filled(2, 6, 3)]),
        throwsArgumentError,
        reason: 'the relaxed nv12 check must not leak into the legacy nv21 entry point',
      );
    });

    test(
      'a real IO ABI v1 operation on a gapped NV12 plane leaves the gap byte untouched',
      () {
        // uvPixelStride 3 on a 4x4 image: uvWidth=2, so each chroma row is
        // [U0 V0 gap][U1 V1 gap] = 6 bytes, rowStride 6.
        const gapMarker = 0xEE;
        final chroma = Uint8List(2 * 6);
        for (int row = 0; row < 2; row++) {
          final base = row * 6;
          chroma[base + 0] = 10; // U0
          chroma[base + 1] = 20; // V0
          chroma[base + 2] = gapMarker; // gap
          chroma[base + 3] = 30; // U1
          chroma[base + 4] = 40; // V1
          chroma[base + 5] = gapMarker; // gap
        }
        final image = YuvImage.nv12(4, 4, planes: [YuvPlane(4, 4), YuvPlane(2, 6, 3, chroma)]);

        // grayscale() is a pure effect: same format/geometry in and out, so any
        // corruption of the gap bytes could only come from the operation
        // treating the plane as tightly packed instead of walking it through
        // its declared strides.
        image.grayscale();

        for (int row = 0; row < 2; row++) {
          final base = row * 6;
          expect(image.uPlane.bytes[base + 2], gapMarker, reason: 'row $row pixel 0 gap byte was touched');
          expect(image.uPlane.bytes[base + 5], gapMarker, reason: 'row $row pixel 1 gap byte was touched');
        }
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('YuvImage.i420 honors explicit strides', () {
    test('an explicit yPixelStride is honored, not defaulted to 1', () {
      final image = YuvImage.i420(4, 4, yPixelStride: 2);
      expect(image.yPlane.pixelStride, 2);
      expect(image.yPlane.rowStride, 4 * 2);
    });

    test('an explicit uvPixelStride is honored, not defaulted to 1', () {
      final image = YuvImage.i420(4, 4, uvPixelStride: 3);
      expect(image.uPlane.pixelStride, 3);
      expect(image.vPlane.pixelStride, 3);
      expect(image.uPlane.rowStride, 2 * 3);
      expect(image.vPlane.rowStride, 2 * 3);
    });

    test('both explicit strides are honored together', () {
      final image = YuvImage.i420(6, 4, yPixelStride: 2, uvPixelStride: 4);
      expect(image.yPlane.pixelStride, 2);
      expect(image.yPlane.rowStride, 6 * 2);
      expect(image.uPlane.pixelStride, 4);
      expect(image.uPlane.rowStride, 3 * 4);
    });
  });

  group('YuvImage.allocate', () {
    test('produces a tight, zero-filled image for every format', () {
      for (final format in YuvPixelFormat.values) {
        final image = YuvImage.allocate(format, 4, 4);
        expect(image.planes.every((p) => p.bytes.every((b) => b == 0)), isTrue, reason: '${format.name} was not zero-filled');
      }
    });

    test('i420 allocation is tight: chroma pixel stride 1, row strides equal width', () {
      final image = YuvImage.allocate(YuvPixelFormat.i420, 6, 4);
      expect(image.yPlane.rowStride, 6);
      expect(image.yPlane.pixelStride, 1);
      expect(image.uPlane.pixelStride, 1);
      expect(image.uPlane.rowStride, 3);
    });

    test('nv12 allocation is tight: interleaved chroma pixel stride 2', () {
      final image = YuvImage.allocate(YuvPixelFormat.nv12, 6, 4);
      expect(image.uPlane.pixelStride, 2);
      expect(image.uPlane.rowStride, 3 * 2);
    });

    test('bgra allocation packs four bytes per pixel with no row padding', () {
      final image = YuvImage.allocate(YuvPixelFormat.bgra8888, 3, 2);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.rowStride, 3 * 4);
      expect(image.planes.length, 1);
    });

    test('odd dimensions still allocate consistent chroma for i420/nv12', () {
      final i420 = YuvImage.allocate(YuvPixelFormat.i420, 3, 5);
      expect(i420.uPlane.height, 3);
      expect(i420.uPlane.rowStride, 2);

      final nv12 = YuvImage.allocate(YuvPixelFormat.nv12, 3, 5);
      expect(nv12.uPlane.height, 3);
      expect(nv12.uPlane.rowStride, 2 * 2);
    });

    test('invalid dimensions are rejected before any allocation', () {
      expect(() => YuvImage.allocate(YuvPixelFormat.i420, 0, 4), throwsArgumentError);
      expect(() => YuvImage.allocate(YuvPixelFormat.i420, 4, 0), throwsArgumentError);
      expect(() => YuvImage.allocate(YuvPixelFormat.bgra8888, -1, 4), throwsArgumentError);
    });
  });

  group('YuvImage.fromRgbaBytes', () {
    test('rejects a buffer that is not exactly width * height * 4 bytes', () {
      expect(() => YuvImage.fromRgbaBytes(Uint8List(4 * 4 * 4 - 1), width: 4, height: 4, format: YuvPixelFormat.i420), throwsArgumentError);
      expect(() => YuvImage.fromRgbaBytes(Uint8List(4 * 4 * 4 + 1), width: 4, height: 4, format: YuvPixelFormat.i420), throwsArgumentError);
    });

    test('rejects invalid dimensions', () {
      expect(() => YuvImage.fromRgbaBytes(Uint8List(0), width: 0, height: 4, format: YuvPixelFormat.i420), throwsArgumentError);
    });

    group('conversion against the native backend', () {
      test('produces an image of the requested format and geometry', () {
        final image = YuvImage.fromRgbaBytes(Uint8List(4 * 3 * 4), width: 4, height: 3, format: YuvPixelFormat.bgra8888);
        expect(image.format, YuvPixelFormat.bgra8888);
        expect(image.width, 4);
        expect(image.height, 3);
      });

      test('a BGRA target reorders RGBA into BGRA order', () {
        // R=10, G=20, B=30, A=40 for the single pixel.
        final rgba = Uint8List.fromList([10, 20, 30, 40]);
        final image = YuvImage.fromRgbaBytes(rgba, width: 1, height: 1, format: YuvPixelFormat.bgra8888);

        expect(image.yPlane.bytes, [30, 20, 10, 40]);
      });
    }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
  });
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
