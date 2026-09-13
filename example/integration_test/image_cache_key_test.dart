import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-20: the image cache key must be driven by the
/// revision of the **real** Web backend, not by a test double.
///
/// An earlier version of this file asserted against a fake that implemented
/// `YuvRevisionAware` itself and called `markDirty()` itself. That proved the
/// fixture worked and nothing about `YuvImageImpl`, which is the class that
/// actually has to bump its revision from inside every mutating method — the
/// test would have stayed green if the Web backend dropped the seam entirely.
///
/// Every case below therefore drives a real `YuvImage` built by the package
/// factory and backed by the WASM module. The mutator matrix mirrors
/// `test/yuv_image_revision_test.dart`, so the VM and Web contracts can be
/// compared line for line.
///
/// The real image exposes no conversion counter, so a cache hit is proven
/// against Flutter's own `ImageCache`: a provider built fresh from an untouched
/// image must be found by `containsKey`, and one built after a mutation must
/// not be.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Uint8List rgba(int width, int height) {
    final bytes = Uint8List(width * height * 4);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 37 + 11) & 0xFF;
    }
    return bytes;
  }

  /// A real, WASM-backed image with content, in the requested format.
  YuvImage realImage(YuvFileFormat format, int width, int height) {
    final image = switch (format) {
      YuvFileFormat.bgra8888 => YuvImage.bgra(width, height),
      YuvFileFormat.i420 => YuvImage.i420(width, height),
      YuvFileFormat.nv21 => YuvImage.nv21(width, height),
    };
    // fromRgba8888 is itself a tracked mutation, so the image arrives in a
    // known state without the test touching plane bytes behind the seam's back.
    image.fromRgba8888(rgba(width, height));
    return image;
  }

  group('the real Web backend reports every one of its own mutations', () {
    testWidgets('the backend implements the revision seam at all', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      for (final format in YuvFileFormat.values) {
        expect(
          YuvRevision.tracksOwnMutations(realImage(format, 4, 4)),
          isTrue,
          reason: '${format.name} must report its own mutations, or a revision-based key is unsafe',
        );
      }
    });

    testWidgets('fromRgba8888 advances the revision exactly once', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      for (final format in YuvFileFormat.values) {
        final image = realImage(format, 8, 8);
        final before = image.revision;

        image.fromRgba8888(rgba(8, 8));

        expect(image.revision, before + 1, reason: '${format.name} fromRgba8888');
      }
    });

    testWidgets('fromRgba8888 into a padded BGRA plane advances it too', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      // This branch writes planes directly and returns early, so it has to bump
      // the revision itself rather than falling through to the shared path.
      final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[YuvPlane(2, 16, 4, Uint8List(2 * 16))]);
      final before = image.revision;

      image.fromRgba8888(rgba(2, 2));

      expect(image.revision, before + 1);
    });

    testWidgets('in-place effects and flips advance it exactly once', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      const operations = <String>['grayscale', 'negate', 'blackwhite', 'flipHorizontally', 'flipVertically'];
      for (final format in YuvFileFormat.values) {
        for (final operation in operations) {
          final image = realImage(format, 8, 8);
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

          expect(image.revision, before + 1, reason: '${format.name} $operation must advance the revision exactly once');
        }
      }
    });

    testWidgets('a real crop and a real rotate advance it exactly once', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      for (final format in YuvFileFormat.values) {
        final cropped = realImage(format, 8, 8);
        final beforeCrop = cropped.revision;
        cropped.crop(const ui.Rect.fromLTWH(0, 0, 4, 4));
        expect(cropped.revision, beforeCrop + 1, reason: '${format.name} crop');

        final rotated = realImage(format, 8, 8);
        final beforeRotate = rotated.revision;
        rotated.rotate(YuvImageRotation.rotation90);
        expect(rotated.revision, beforeRotate + 1, reason: '${format.name} rotate');
      }
    });

    testWidgets('a format conversion advances it exactly once', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final toNv = realImage(YuvFileFormat.i420, 8, 8);
      final beforeNv = toNv.revision;
      toNv.toYuvNv21();
      expect(toNv.revision, beforeNv + 1, reason: 'i420 -> nv21');

      final toI420 = realImage(YuvFileFormat.nv21, 8, 8);
      final beforeI420 = toI420.revision;
      toI420.toYuvI420();
      expect(toI420.revision, beforeI420 + 1, reason: 'nv21 -> i420');

      final toBgra = realImage(YuvFileFormat.i420, 8, 8);
      final beforeBgra = toBgra.revision;
      toBgra.toYuvBgra8888();
      expect(toBgra.revision, beforeBgra + 1, reason: 'i420 -> bgra8888');
    });

    testWidgets('swapNv advances exactly once even when it converts first', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      // swapNv() calls toYuvNv21() internally, which bumps on its own. One
      // public call must still count as exactly one revision.
      final alreadyNv = realImage(YuvFileFormat.nv21, 8, 8);
      final alreadyNvBefore = alreadyNv.revision;
      alreadyNv.swapNv();
      expect(alreadyNv.revision, alreadyNvBefore + 1, reason: 'no conversion needed');

      final needsConversion = realImage(YuvFileFormat.i420, 8, 8);
      final needsConversionBefore = needsConversion.revision;
      needsConversion.swapNv();
      expect(needsConversion.revision, needsConversionBefore + 1, reason: 'an internal conversion must not double-count');
    });

    testWidgets('a successful load advances it once and a failed load leaves it alone', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final source = realImage(YuvFileFormat.i420, 8, 8);
      final chunks = <List<int>>[];
      await source.save(_CollectingSink(chunks));
      final payload = <int>[for (final chunk in chunks) ...chunk];

      final target = YuvImage.i420(2, 2);
      final beforeSuccess = target.revision;
      await target.load(Stream<List<int>>.value(payload));
      expect(target.revision, beforeSuccess + 1, reason: 'a successful load is one new frame');

      final rejected = YuvImage.i420(2, 2);
      final beforeFailure = rejected.revision;
      await expectLater(
        rejected.load(Stream<List<int>>.value(payload.sublist(0, payload.length ~/ 2))),
        throwsFormatException,
      );
      expect(rejected.revision, beforeFailure, reason: 'a rejected payload must not look like a new frame');
    });
  });

  group('genuine no-ops leave the revision untouched', () {
    testWidgets('rotate by zero', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 8, 8);
      final before = image.revision;

      image.rotate(YuvImageRotation.rotation0);

      expect(image.revision, before, reason: 'rotating by zero changes nothing, so the cache must still hit');
    });

    testWidgets('an empty crop', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 8, 8);
      final before = image.revision;

      image.crop(ui.Rect.zero);

      expect(image.revision, before);
    });

    testWidgets('converting to the format the image already has', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final bgra = realImage(YuvFileFormat.bgra8888, 8, 8);
      final bgraBefore = bgra.revision;
      bgra.toYuvBgra8888();
      expect(bgra.revision, bgraBefore);

      final i420 = realImage(YuvFileFormat.i420, 8, 8);
      final i420Before = i420.revision;
      i420.toYuvI420();
      expect(i420.revision, i420Before);

      final nv21 = realImage(YuvFileFormat.nv21, 8, 8);
      final nv21Before = nv21.revision;
      nv21.toYuvNv21();
      expect(nv21.revision, nv21Before);
    });
  });

  group('the image cache follows the real revision', () {
    testWidgets('an untouched real image is served from the cache', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 8, 8);

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
      await tester.pumpAndSettle();

      // A provider built now is a separate object from the one the widget used,
      // so finding it proves the key matched rather than the instance.
      expect(
        PaintingBinding.instance.imageCache.containsKey(YuvImageProvider(image)),
        isTrue,
        reason: 'an untouched frame must be reachable under an equal key',
      );

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image, boxFit: BoxFit.contain)));
      await tester.pumpAndSettle();

      expect(
        PaintingBinding.instance.imageCache.containsKey(YuvImageProvider(image)),
        isTrue,
        reason: 'rebuilding around an unchanged frame must keep hitting the same entry',
      );
    });

    testWidgets('a real in-place mutation invalidates the cached frame', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 8, 8);

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image)));
      await tester.pumpAndSettle();

      final keyBefore = YuvImageProvider(image);
      expect(PaintingBinding.instance.imageCache.containsKey(keyBefore), isTrue);

      // A genuine backend operation, bumping the revision from inside
      // YuvImageImpl rather than from the test.
      image.negate();

      final keyAfter = YuvImageProvider(image);
      expect(keyAfter, isNot(equals(keyBefore)), reason: 'a real mutation must produce a different key');
      expect(
        PaintingBinding.instance.imageCache.containsKey(keyAfter),
        isFalse,
        reason: 'a mutated frame must not be served from the previous entry',
      );

      await tester.pumpWidget(MaterialApp(home: YuvImageWidget(image: image, boxFit: BoxFit.contain)));
      await tester.pumpAndSettle();

      expect(
        PaintingBinding.instance.imageCache.containsKey(keyAfter),
        isTrue,
        reason: 'the rebuild must have cached the new frame under the new key',
      );
    });

    testWidgets('a direct plane write needs markDirty to invalidate the key', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 4, 4);
      final before = YuvImageProvider(image);

      // Writing into plane bytes cannot be intercepted, so on its own it must
      // not change the key. This is the documented cost of mutable planes.
      image.yPlane.bytes[0] = image.yPlane.bytes[0] ^ 0xFF;
      expect(YuvImageProvider(image), equals(before), reason: 'a silent write must not change the key by itself');

      image.markDirty();
      expect(YuvImageProvider(image), isNot(equals(before)), reason: 'markDirty must invalidate the previous key');
    });

    testWidgets('the cached key keeps its hashCode after a later mutation', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final image = realImage(YuvFileFormat.bgra8888, 4, 4);
      final key = YuvImageProvider(image);
      final hashWhenCached = key.hashCode;

      image.negate();

      // Reading the live revision in hashCode would strand an entry already in
      // the cache, because the map could no longer find it.
      expect(key.hashCode, hashWhenCached);
    });

    testWidgets('two distinct real images never share a key', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      final a = realImage(YuvFileFormat.bgra8888, 4, 4);
      final b = realImage(YuvFileFormat.bgra8888, 4, 4);

      expect(YuvImageProvider(a), isNot(equals(YuvImageProvider(b))));
    });

    testWidgets('a foreign legacy image always misses', (tester) async {
      expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');
      await YuvFfi.ensureInitialized();

      // A class written before the revision seam existed: it mutates without
      // reporting anything, so an unchanged revision is not evidence that the
      // frame is untouched and must never be treated as a cache hit.
      final foreign = _ForeignImage(4, 4);

      expect(YuvRevision.tracksOwnMutations(foreign), isFalse);
      expect(
        YuvImageProvider(foreign),
        isNot(equals(YuvImageProvider(foreign))),
        reason: 'a foreign image that cannot prove its frame is unchanged must always miss',
      );
    });
  });
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}

/// A foreign `implements YuvImage` that predates the revision seam.
///
/// Only the members the cache path touches are implemented; everything else
/// forwards to `noSuchMethod`, which keeps the fixture honest about what it
/// stands for.
class _ForeignImage implements YuvImage {
  _ForeignImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(width * height * 4));

  final YuvPlane _plane;

  @override
  final int width;

  @override
  final int height;

  @override
  YuvFileFormat get format => YuvFileFormat.bgra8888;

  @override
  List<YuvPlane> get planes => <YuvPlane>[_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get y => _plane;

  @override
  YuvPlane? get u => null;

  @override
  YuvPlane? get v => null;

  @override
  Uint8List toBgra8888() => _plane.bytes;

  @override
  Uint8List getBytes() => _plane.bytes;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
