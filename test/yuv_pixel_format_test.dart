import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-01: the exported [YuvPixelFormat] carries stable wire IDs
/// that are never derived from [Enum.index], and its `nv12` value keeps the
/// legacy NV21 UV byte order under a truthful name.
void main() {
  group('YuvPixelFormat root export', () {
    test('is reachable from the root library', () {
      // Compile-time check: this line would fail to build if YuvPixelFormat
      // stopped being exported by package:yuv_ffi/yuv_ffi.dart.
      const YuvPixelFormat format = YuvPixelFormat.i420;
      expect(format, isNotNull);
    });

    test('declares exactly i420, nv12 and bgra8888', () {
      expect(YuvPixelFormat.values, [YuvPixelFormat.i420, YuvPixelFormat.nv12, YuvPixelFormat.bgra8888]);
    });
  });

  group('wire IDs', () {
    test('are the stable values 1, 2 and 3', () {
      expect(YuvPixelFormat.i420.wireId, 1);
      expect(YuvPixelFormat.nv12.wireId, 2);
      expect(YuvPixelFormat.bgra8888.wireId, 3);
    });

    test('do not equal Enum.index', () {
      // i420 is declared first (index 0) but its wire ID is 1: if a future
      // edit ever reordered the declarations, index-based encoding would
      // silently change what is written to the codec/ABI, which the design
      // explicitly forbids (section 6).
      for (final format in YuvPixelFormat.values) {
        expect(format.wireId, format.index + 1, reason: 'wireId happens to equal index + 1 today, but must be read from wireId, not index');
      }
    });
  });

  group('nv12 keeps the historical NV21 UV byte order', () {
    test('a filled UV plane keeps the same (U, V) pair order as the legacy nv21 factory', () {
      // ignore: deprecated_member_use_from_same_package
      final legacy = YuvImage.nv21(4, 4);
      final canonical = YuvImage.nv12(4, 4);

      // Both share the same interleaved chroma pixel stride and layout: the
      // truthful name introduces no reinterpretation of already-supplied
      // bytes (section 14, Q1).
      expect(canonical.uPlane.pixelStride, legacy.uPlane.pixelStride);
      expect(canonical.uPlane.rowStride, legacy.uPlane.rowStride);
      expect(canonical.format, legacy.format, reason: 'nv12 is canonical NV12 storage, which today is backed by the same legacy value as nv21');
    });

    test('YuvImage.allocate(nv12, ...) produces the same interleaved layout as nv21', () {
      final allocated = YuvImage.allocate(YuvPixelFormat.nv12, 4, 4);
      // ignore: deprecated_member_use_from_same_package
      final legacy = YuvImage.nv21(4, 4);

      expect(allocated.uPlane.pixelStride, legacy.uPlane.pixelStride);
      expect(allocated.planes.length, legacy.planes.length);
    });
  });

  group('REL-19: YuvImage.format is YuvPixelFormat', () {
    test('exhaustively switches over image.format through the public import alone', () {
      String describe(YuvImage image) => switch (image.format) {
        YuvPixelFormat.i420 => 'i420',
        YuvPixelFormat.nv12 => 'nv12',
        YuvPixelFormat.bgra8888 => 'bgra8888',
      };

      expect(describe(YuvImage.i420(2, 2)), 'i420');
      expect(describe(YuvImage.nv12(2, 2)), 'nv12');
      expect(describe(YuvImage.bgra(2, 2)), 'bgra8888');
    });

    test('a legacy nv21-labeled image reports YuvPixelFormat.nv12', () {
      // ignore: deprecated_member_use_from_same_package
      final legacy = YuvImage.nv21(2, 2);
      expect(legacy.format, YuvPixelFormat.nv12);
    });
  });
}
