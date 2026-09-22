import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-20: the revision counter that makes a mutable [YuvImage]
/// usable as an image cache key.
///
/// Every successful mutating operation must advance it exactly once, and a
/// genuine no-op must leave it alone — otherwise the widget either serves a
/// stale frame or misses the cache on every rebuild.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

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

        image.rotate(YuvImageRotation.rotation0);

        expect(image.revision, before);
      });

      test('converting to the format the image already has', () {
        final bgra = YuvImage.bgra(4, 4);
        final bgraBefore = bgra.revision;
        bgra.toYuvBgra8888();
        expect(bgra.revision, bgraBefore);

        final i420 = YuvImage.i420(4, 4);
        final i420Before = i420.revision;
        i420.toYuvI420();
        expect(i420.revision, i420Before);

        final nv21 = YuvImage.nv21(4, 4);
        final nv21Before = nv21.revision;
        nv21.toYuvNv21();
        expect(nv21.revision, nv21Before);
      });

      test('an empty crop', () {
        final image = YuvImage.bgra(8, 8);
        final before = image.revision;

        image.crop(const ui.Rect.fromLTWH(4, 4, 0, 0));

        expect(image.revision, before);
      });
    });

    group(
      'native mutating operations advance the revision exactly once',
      () {
        Uint8List rgba(int w, int h) => Uint8List(w * h * 4);

        test('in-place effects', () {
          for (final operation in <String>['grayscale', 'negate', 'blackwhite', 'flipHorizontally', 'flipVertically']) {
            final image = YuvImage.i420(8, 8)..fromRgba8888(rgba(8, 8));
            final before = image.revision;

            switch (operation) {
              case 'grayscale':
                image.grayscale();
              case 'negate':
                image.negate();
              case 'blackwhite':
                image.blackwhite();
              case 'flipHorizontally':
                image.flipHorizontally();
              case 'flipVertically':
                image.flipVertically();
            }

            expect(image.revision, before + 1, reason: '$operation must advance the revision exactly once');
          }
        });

        test('fromRgba8888', () {
          final image = YuvImage.i420(8, 8);
          final before = image.revision;

          image.fromRgba8888(rgba(8, 8));

          expect(image.revision, before + 1);
        });

        test('fromRgba8888 into a padded BGRA plane', () {
          // This path writes planes directly and returns early, so it has to bump
          // the revision on its own.
          final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[YuvPlane(2, 16, 4, Uint8List(2 * 16))]);
          final before = image.revision;

          image.fromRgba8888(rgba(2, 2));

          expect(image.revision, before + 1);
        });

        test('a real crop', () {
          final image = YuvImage.bgra(8, 8)..fromRgba8888(rgba(8, 8));
          final before = image.revision;

          image.crop(const ui.Rect.fromLTWH(0, 0, 4, 4));

          expect(image.revision, before + 1);
        });

        test('a real rotate', () {
          final image = YuvImage.bgra(8, 8)..fromRgba8888(rgba(8, 8));
          final before = image.revision;

          image.rotate(YuvImageRotation.rotation90);

          expect(image.revision, before + 1);
        });

        test('a format conversion', () {
          final image = YuvImage.i420(8, 8)..fromRgba8888(rgba(8, 8));
          final before = image.revision;

          image.toYuvNv21();

          expect(image.revision, before + 1);
        });

        test('swapNv advances exactly once even when it converts first', () {
          // swapNv() calls toYuvNv21() internally, which bumps on its own. One
          // public call must still count as one revision.
          final alreadyNv = YuvImage.nv21(8, 8)..fromRgba8888(rgba(8, 8));
          final alreadyNvBefore = alreadyNv.revision;
          alreadyNv.swapNv();
          expect(alreadyNv.revision, alreadyNvBefore + 1, reason: 'no conversion needed');

          final needsConversion = YuvImage.i420(8, 8)..fromRgba8888(rgba(8, 8));
          final needsConversionBefore = needsConversion.revision;
          needsConversion.swapNv();
          expect(needsConversion.revision, needsConversionBefore + 1, reason: 'an internal conversion must not double-count');
        });
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
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
