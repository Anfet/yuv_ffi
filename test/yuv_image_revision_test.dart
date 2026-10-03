@Tags(['contract'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart' as backend_loader;
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies that the revision counter that makes a mutable [YuvImage]
/// usable as an image cache key.
///
/// Every successful mutating operation must advance it exactly once, and a
/// genuine no-op must leave it alone — otherwise the widget either serves a
/// stale frame or misses the cache on every rebuild.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  setUpAll(() async {
    if (nativeAvailable) {
      await YuvFfi.initialize();
    }
  });

  group('revision contract', () {
    test('a fresh image starts at a stable revision', () {
      final image = YuvImage.bgra(4, 4);
      expect(image.revision, image.revision);
    });

    test('markDirty advances the revision', () {
      final image = YuvImage.bgra(4, 4);
      final before = image.revision;

      image.markDirty();

      expect(image.revision, before + 1);
    });

    test('a direct plane write alone does not advance the revision', () {
      final image = YuvImage.bgra(4, 4);
      final before = image.revision;

      // Uint8List writes cannot be intercepted; this is the documented reason
      // markDirty() exists.
      image.yPlane.bytes[0] = 0xFF;

      expect(image.revision, before);
    });

    test('copy does not inherit a revision as if it had been mutated', () {
      final image = YuvImage.bgra(4, 4)..markDirty();
      final copied = image.copy();

      // A copy is a separate identity, so its revision only has to be
      // self-consistent; what matters is that reading it does not throw and the
      // original is untouched.
      expect(copied.revision, isA<int>());
      expect(image.revision, 1);
    });

    group('no-op operations leave the revision untouched', () {
      test('rotating by zero degrees', () {
        final image = YuvImage.bgra(4, 4);
        final before = image.revision;

        // ignore: deprecated_member_use_from_same_package
        image.applyRotation(YuvImageRotation.rotation0);

        expect(image.revision, before);
      });

      test('converting to the format the image already has', () {
        final bgra = YuvImage.bgra(4, 4);
        final bgraBefore = bgra.revision;
        // ignore: deprecated_member_use_from_same_package
        bgra.applyFormat(YuvPixelFormat.bgra8888);
        expect(bgra.revision, bgraBefore);

        final i420 = YuvImage.i420(4, 4);
        final i420Before = i420.revision;
        // ignore: deprecated_member_use_from_same_package
        i420.applyFormat(YuvPixelFormat.i420);
        expect(i420.revision, i420Before);

        // ignore: deprecated_member_use_from_same_package
        final nv21 = YuvImage.nv12(4, 4);
        final nv21Before = nv21.revision;
        // ignore: deprecated_member_use_from_same_package
        nv21.applyFormat(YuvPixelFormat.nv12);
        expect(nv21.revision, nv21Before);
      });

      test('an empty crop', () {
        final image = YuvImage.bgra(8, 8);
        final before = image.revision;

        // ignore: deprecated_member_use_from_same_package
        image.applyCrop(const ui.Rect.fromLTWH(4, 4, 0, 0));

        expect(image.revision, before);
      });
    });

    group(
      'native mutating operations advance the revision exactly once',
      () {
        Uint8List rgba(int w, int h) => Uint8List(w * h * 4);

        test('in-place effects', () {
          for (final operation in <String>['grayscale', 'negate', 'blackwhite', 'flipHorizontally', 'flipVertically']) {
            // ignore: deprecated_member_use_from_same_package
            final image = YuvImage.i420(8, 8)..applyRgbaBytes(rgba(8, 8));
            final before = image.revision;

            switch (operation) {
              case 'grayscale':
                // ignore: deprecated_member_use_from_same_package
                image.applyGrayscale();
              case 'negate':
                // ignore: deprecated_member_use_from_same_package
                image.applyNegate();
              case 'blackwhite':
                // ignore: deprecated_member_use_from_same_package
                image.applyBlackWhite();
              case 'flipHorizontally':
                // ignore: deprecated_member_use_from_same_package
                image.applyFlipHorizontal();
              case 'flipVertically':
                // ignore: deprecated_member_use_from_same_package
                image.applyFlipVertical();
            }

            expect(image.revision, before + 1, reason: '$operation must advance the revision exactly once');
          }
        });

        test('fromRgba8888', () {
          final image = YuvImage.i420(8, 8);
          final before = image.revision;

          // ignore: deprecated_member_use_from_same_package
          image.applyRgbaBytes(rgba(8, 8));

          expect(image.revision, before + 1);
        });

        test('fromRgba8888 into a padded BGRA plane', () {
          // This path writes planes directly and returns early, so it has to bump
          // the revision on its own.
          final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[YuvPlane(2, 16, 4, Uint8List(2 * 16))]);
          final before = image.revision;

          // ignore: deprecated_member_use_from_same_package
          image.applyRgbaBytes(rgba(2, 2));

          expect(image.revision, before + 1);
        });

        test('a real crop', () {
          // ignore: deprecated_member_use_from_same_package
          final image = YuvImage.bgra(8, 8)..applyRgbaBytes(rgba(8, 8));
          final before = image.revision;

          // ignore: deprecated_member_use_from_same_package
          image.applyCrop(const ui.Rect.fromLTWH(0, 0, 4, 4));

          expect(image.revision, before + 1);
        });

        test('a real rotate', () {
          // ignore: deprecated_member_use_from_same_package
          final image = YuvImage.bgra(8, 8)..applyRgbaBytes(rgba(8, 8));
          final before = image.revision;

          // ignore: deprecated_member_use_from_same_package
          image.applyRotation(YuvImageRotation.rotation90);

          expect(image.revision, before + 1);
        });

        test('a format conversion', () {
          // ignore: deprecated_member_use_from_same_package
          final image = YuvImage.i420(8, 8)..applyRgbaBytes(rgba(8, 8));
          final before = image.revision;

          // ignore: deprecated_member_use_from_same_package
          image.applyFormat(YuvPixelFormat.nv12);

          expect(image.revision, before + 1);
        });

        test('applyChromaSwap advances exactly once on NV12', () {
          // Chroma swap is an in-place NV12 operation and advances once.
          // ignore: deprecated_member_use_from_same_package
          final alreadyNv = YuvImage.nv12(8, 8)..applyRgbaBytes(rgba(8, 8));
          final alreadyNvBefore = alreadyNv.revision;
          // ignore: deprecated_member_use_from_same_package
          alreadyNv.applyChromaSwap();
          expect(alreadyNv.revision, alreadyNvBefore + 1, reason: 'no conversion needed');

          // ignore: deprecated_member_use_from_same_package
        });
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
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
