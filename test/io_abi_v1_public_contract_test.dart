import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-50: the public IO operations run on ABI v1 and keep the
/// transactional contract of `doc/api-abi-0.3-design.md` sections 11 and 13.
///
/// The reference matrix already pins what each operation *computes*; what this
/// suite pins is what the public Dart object does around the native call --
/// that a success publishes atomically and advances the revision once, that a
/// non-zero status publishes nothing at all, and that a receiver's declared
/// padding survives an operation instead of being repacked.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  YuvPlane plane(int height, int rowStride, int pixelStride, int fill) =>
      YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride)..fillRange(0, height * rowStride, fill));

  group('a non-zero native status leaves the receiver untouched', () {
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    /// Every in-place operation, so a new one cannot be added without a
    /// decision about its failure behaviour.
    final operations = <String, void Function(YuvImage)>{
      'blackwhite': (image) => image.blackwhite(),
      'grayscale': (image) => image.grayscale(),
      'negate': (image) => image.negate(),
      'gaussianBlur': (image) => image.gaussianBlur(radius: 1),
      'boxBlur': (image) => image.boxBlur(radius: 1),
      'meanBlur': (image) => image.meanBlur(radius: 1),
      'flipHorizontally': (image) => image.flipHorizontally(),
      'flipVertically': (image) => image.flipVertically(),
      'rotate': (image) => image.rotate(YuvImageRotation.rotation90),
      'crop': (image) => image.crop(const ui.Rect.fromLTRB(0, 0, 4, 4)),
      'toYuvI420': (image) => image.toYuvI420(),
    };

    for (final entry in operations.entries) {
      test('${entry.key} publishes nothing when native reports INTERNAL_ERROR', () {
        final image = YuvImage.nv21(8, 8, planes: [plane(8, 8, 1, 0x30), plane(4, 8, 2, 0x50)]);
        final bytesBefore = image.getBytes();
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        // A controlled non-zero status: the whole staging/dispatch path runs
        // for real and only the kernel's return value is substituted, which is
        // what makes this a test of the publish step rather than of a mock.
        YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;

        expect(() => entry.value(image), throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', yuvStatusInternalError)));

        expect(image.getBytes(), bytesBefore, reason: 'bytes changed after a failed ${entry.key}');
        expect(image.format, YuvFileFormat.nv21, reason: 'format changed after a failed ${entry.key}');
        expect(image.width, 8, reason: 'width changed after a failed ${entry.key}');
        expect(image.height, 8, reason: 'height changed after a failed ${entry.key}');
        expect((image as YuvRevisionAware).internalRevision, revisionBefore, reason: 'revision advanced on a failed ${entry.key}');
      });
    }
  });

  group('a successful operation advances the revision exactly once', () {
    test('an in-place effect bumps it by one', () {
      final image = YuvImage.i420(8, 8) as YuvRevisionAware;
      final before = image.internalRevision;

      (image as YuvImage).negate();

      expect(image.internalRevision, before + 1);
    }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');

    test('swapNv bumps it by one despite converting first', () {
      // The conversion inside swapNv is itself a mutating operation, so this
      // is the case where a naive implementation advances the counter twice.
      final image = YuvImage.i420(8, 8) as YuvRevisionAware;
      final before = image.internalRevision;

      (image as YuvImage).swapNv();

      expect(image.internalRevision, before + 1);
      expect((image as YuvImage).format, YuvFileFormat.nv21);
    }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
  });

  group('a receiver keeps its declared layout', () {
    test(
      'a padded BGRA plane keeps its strides and padding through an effect',
      () {
        const width = 8;
        const height = 8;
        const rowStride = width * 4 + 12;
        final padded = plane(height, rowStride, 4, 0x20);
        for (int row = 0; row < height; row++) {
          padded.bytes.fillRange(row * rowStride + width * 4, (row + 1) * rowStride, 0xEE);
        }

        final image = YuvImage(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: [padded])..negate();

        expect(image.yPlane.rowStride, rowStride, reason: 'the row stride was repacked');
        for (int row = 0; row < height; row++) {
          expect(
            image.yPlane.bytes.sublist(row * rowStride + width * 4, (row + 1) * rowStride),
            everyElement(0xEE),
            reason: 'row $row padding was modified',
          );
        }
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'a padded NV chroma plane keeps its padding through fromRgba8888',
      () {
        const width = 4;
        const height = 4;
        const chromaRowStride = 4 + 6;
        final chroma = plane(2, chromaRowStride, 2, 0);
        for (int row = 0; row < 2; row++) {
          chroma.bytes.fillRange(row * chromaRowStride + 4, (row + 1) * chromaRowStride, 0xEE);
        }

        final image = YuvImage.nv21(width, height, planes: [plane(height, width, 1, 0), chroma]);
        image.fromRgba8888(Uint8List(width * height * 4)..fillRange(0, width * height * 4, 0x80));

        expect(image.uPlane.rowStride, chromaRowStride);
        for (int row = 0; row < 2; row++) {
          expect(
            image.uPlane.bytes.sublist(row * chromaRowStride + 4, (row + 1) * chromaRowStride),
            everyElement(0xEE),
            reason: 'row $row chroma padding was modified',
          );
        }
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('odd 4:2:0 geometry', () {
    test(
      'an odd-sized frame survives a round trip through every format',
      () {
        // ceil-sized chroma is where a floor-based loop silently drops the last
        // row or column.
        final image = YuvImage.i420(5, 3)..fromRgba8888(Uint8List(5 * 3 * 4)..fillRange(0, 5 * 3 * 4, 0x90));

        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3);

        image.toYuvNv21();
        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3 * 2);

        image.toYuvI420();
        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3);
        expect(image.width, 5);
        expect(image.height, 3);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test('an odd-origin crop keeps visible-pixel semantics', () {
      final image = YuvImage.i420(8, 8)..fromRgba8888(Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0x70));

      image.crop(const ui.Rect.fromLTRB(1, 1, 6, 4));

      expect(image.width, 5);
      expect(image.height, 3);
      expect(image.uPlane.height, 2, reason: 'ceil(3 / 2) chroma rows');
      expect(image.uPlane.rowStride, 3, reason: 'ceil(5 / 2) chroma columns');
    }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
  });

  group('conversions produce an independent result', () {
    test(
      'toBgra8888 returns a fresh buffer, not a view onto the planes',
      () {
        final image = YuvImage.bgra(4, 4)..fromRgba8888(Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0x60));

        final bytes = image.toBgra8888();
        bytes[0] = bytes[0] ^ 0xFF;

        expect(image.yPlane.bytes[0], isNot(bytes[0]), reason: 'toBgra8888 handed out the plane buffer itself');
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test('converting to the format the image already has is a no-op', () {
      final image = YuvImage.i420(4, 4) as YuvRevisionAware;
      final before = image.internalRevision;

      expect((image as YuvImage).toYuvI420(), same(image));
      expect(image.internalRevision, before, reason: 'a no-op conversion advanced the revision');
    });
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
