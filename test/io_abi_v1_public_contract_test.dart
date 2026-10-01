@Tags(['contract'])
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart' as backend_loader;
import 'package:yuv_ffi/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies that the public IO operations run on ABI v1 and keep the
/// transactional contract: successful calls publish atomically, while failed
/// calls leave the receiver unchanged.
///
/// The reference matrix already pins what each operation *computes*; what this
/// suite pins is what the public Dart object does around the native call --
/// that a success publishes atomically and advances the revision once, that a
/// non-zero status publishes nothing at all, and that a receiver's declared
/// padding survives an operation instead of being repacked.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  setUpAll(() async {
    if (nativeAvailable) {
      await YuvFfi.initialize();
    }
  });

  YuvPlane plane(int height, int rowStride, int pixelStride, int fill) =>
      YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride)..fillRange(0, height * rowStride, fill));

  group('a non-zero native status leaves the receiver untouched', () {
    tearDown(() => YuvAbiV1Runner.debugInvokeOverride = null);

    /// Every in-place operation, so a new one cannot be added without a
    /// decision about its failure behaviour.
    final operations = <String, void Function(YuvImage)>{
      // ignore: deprecated_member_use_from_same_package
      'blackwhite': (image) => image.applyBlackWhite(),
      // ignore: deprecated_member_use_from_same_package
      'grayscale': (image) => image.applyGrayscale(),
      // ignore: deprecated_member_use_from_same_package
      'negate': (image) => image.applyNegate(),
      // ignore: deprecated_member_use_from_same_package
      'gaussianBlur': (image) => image.applyGaussianBlur(radius: 1, sigma: 1),
      // ignore: deprecated_member_use_from_same_package
      'boxBlur': (image) => image.applyBoxBlur(radius: 1),
      // ignore: deprecated_member_use_from_same_package
      'meanBlur': (image) => image.applyMeanBlur(radius: 1),
      // ignore: deprecated_member_use_from_same_package
      'flipHorizontally': (image) => image.applyFlipHorizontal(),
      // ignore: deprecated_member_use_from_same_package
      'flipVertically': (image) => image.applyFlipVertical(),
      // ignore: deprecated_member_use_from_same_package
      'rotate': (image) => image.applyRotation(YuvImageRotation.rotation90),
      // ignore: deprecated_member_use_from_same_package
      'crop': (image) => image.applyCrop(const ui.Rect.fromLTRB(0, 0, 4, 4)),
      // ignore: deprecated_member_use_from_same_package
      'toYuvI420': (image) => image.applyFormat(YuvPixelFormat.i420),
      // Reaches the kernel in one call when the receiver is already NV21,
      // which is the shape this group's fixture uses. The two-call form
      // (convert, then swap) has its own test below, because only that one
      // can fail *after* a successful first call.
      // ignore: deprecated_member_use_from_same_package
      'swapNv': (image) => image.applyChromaSwap(),
    };

    for (final entry in operations.entries) {
      test('${entry.key} publishes nothing when native reports INTERNAL_ERROR', () {
        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage.nv12(8, 8, planes: [plane(8, 8, 1, 0x30), plane(4, 8, 2, 0x50)]);
        // ignore: deprecated_member_use_from_same_package
        final bytesBefore = image.toBytes();
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        // A controlled non-zero status: the whole staging/dispatch path runs
        // for real and only the kernel's return value is substituted, which is
        // what makes this a test of the publish step rather than of a mock.
        YuvAbiV1Runner.debugInvokeOverride = (src, dst, options) => yuvStatusInternalError;

        expect(() => entry.value(image), throwsA(isA<YuvNativeException>().having((e) => e.statusCode, 'statusCode', yuvStatusInternalError)));

        // ignore: deprecated_member_use_from_same_package
        expect(image.toBytes(), bytesBefore, reason: 'bytes changed after a failed ${entry.key}');
        expect(image.format, YuvPixelFormat.nv12, reason: 'format changed after a failed ${entry.key}');
        expect(image.width, 8, reason: 'width changed after a failed ${entry.key}');
        expect(image.height, 8, reason: 'height changed after a failed ${entry.key}');
        expect((image as YuvRevisionAware).internalRevision, revisionBefore, reason: 'revision advanced on a failed ${entry.key}');
      });
    }
  });

  group('applyChromaSwap rejects non-NV frames atomically', () {
    for (final format in [YuvPixelFormat.i420, YuvPixelFormat.bgra8888]) {
      test('$format keeps bytes and revision when chroma swap is unsupported', () {
        final image = format == YuvPixelFormat.i420
            ? YuvImage.i420(8, 8, planes: [plane(8, 8, 1, 0x30), plane(4, 4, 1, 0x50), plane(4, 4, 1, 0x70)])
            : YuvImage.bgra(8, 8, planes: [plane(8, 32, 4, 0x30)]);
        final bytesBefore = image.toBytes();
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        expect(() => image.applyChromaSwap(), throwsUnsupportedError);
        expect(image.toBytes(), bytesBefore);
        expect((image as YuvRevisionAware).internalRevision, revisionBefore);
      });
    }
  });

  group('a successful operation advances the revision exactly once', () {
    test('an in-place effect bumps it by one', () {
      final image = YuvImage.i420(8, 8) as YuvRevisionAware;
      final before = image.internalRevision;

      // ignore: deprecated_member_use_from_same_package
      (image as YuvImage).applyNegate();

      expect(image.internalRevision, before + 1);
    }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');

    test('applyChromaSwap bumps it by one on NV12', () {
      final image = YuvImage.nv12(8, 8) as YuvRevisionAware;
      final before = image.internalRevision;

      (image as YuvImage).applyChromaSwap();

      expect(image.internalRevision, before + 1);
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

        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage(YuvPixelFormat.bgra8888, width, height, yPixelStride: 4, planes: [padded], layout: YuvPlaneLayout.preserve)
          ..applyNegate();

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

        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage.nv12(width, height, planes: [plane(height, width, 1, 0), chroma], layout: YuvPlaneLayout.preserve);
        // ignore: deprecated_member_use_from_same_package
        image.applyRgbaBytes(Uint8List(width * height * 4)..fillRange(0, width * height * 4, 0x80));

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
        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage.i420(5, 3)..applyRgbaBytes(Uint8List(5 * 3 * 4)..fillRange(0, 5 * 3 * 4, 0x90));

        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3);

        // ignore: deprecated_member_use_from_same_package
        image.applyFormat(YuvPixelFormat.nv12);
        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3 * 2);

        // ignore: deprecated_member_use_from_same_package
        image.applyFormat(YuvPixelFormat.i420);
        expect(image.uPlane.height, 2);
        expect(image.uPlane.rowStride, 3);
        expect(image.width, 5);
        expect(image.height, 3);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test('an odd-origin crop keeps visible-pixel semantics', () {
      // ignore: deprecated_member_use_from_same_package
      final image = YuvImage.i420(8, 8)..applyRgbaBytes(Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0x70));

      // ignore: deprecated_member_use_from_same_package
      image.applyCrop(const ui.Rect.fromLTRB(1, 1, 6, 4));

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
        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage.bgra(4, 4)..applyRgbaBytes(Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 0x60));

        // ignore: deprecated_member_use_from_same_package
        final bytes = image.toBgraBytes();
        bytes[0] = bytes[0] ^ 0xFF;

        expect(image.yPlane.bytes[0], isNot(bytes[0]), reason: 'toBgra8888 handed out the plane buffer itself');
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test('converting to the format the image already has is a no-op', () {
      final image = YuvImage.i420(4, 4) as YuvRevisionAware;
      final before = image.internalRevision;

      // ignore: deprecated_member_use_from_same_package
      expect((image as YuvImage).applyFormat(YuvPixelFormat.i420), same(image));
      expect(image.internalRevision, before, reason: 'a no-op conversion advanced the revision');
    });
  });
}

bool _checkNativeAvailable() {
  try {
    backend_loader.library;
    return true;
  } catch (_) {
    return false;
  }
}
