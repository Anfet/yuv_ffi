import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-02: constructors copy input buffers, `planes`/`yPlane`/
/// `uPlane`/`vPlane` are live views backed by the image's own storage, and
/// `applyPlanes` is an atomic, validated, copying replacement that bumps the
/// revision exactly once and leaves the image untouched on failure.
void main() {
  group('constructors copy the caller\'s buffer (no aliasing on construct)', () {
    test('mutating the source plane after construction does not change the image', () {
      final source = YuvPlane(4, 4, 1, Uint8List(16));
      final image = YuvImage.i420(4, 4, planes: [source, YuvPlane(2, 2), YuvPlane(2, 2)]);

      source.setPixel(0, 0, 200);

      expect(image.yPlane.getPixel(0, 0), 0, reason: 'the constructor must copy the caller\'s plane, not alias it');
    });
  });

  group('live plane accessors', () {
    test('yPlane/uPlane/vPlane returned twice are the same live object', () {
      final image = YuvImage.i420(4, 4);
      expect(image.yPlane, same(image.yPlane));
      expect(image.uPlane, same(image.uPlane));
      expect(image.vPlane, same(image.vPlane));
      expect(image.planes[0], same(image.yPlane));
    });

    test('a direct write through the live plane is visible on the same reference', () {
      final image = YuvImage.i420(4, 4);
      final y = image.yPlane;

      y.setPixel(0, 0, 123);

      expect(image.yPlane.getPixel(0, 0), 123, reason: 'the plane returned by the image is backed by the same storage the write went to');
    });

    test('a direct write is visible without markDirty; markDirty only affects revision', () {
      // Section 5/REL-02: writes through a live plane are immediately visible
      // through that same storage. markDirty() exists purely so revision-keyed
      // caches (e.g. YuvImageProvider) learn about it -- it does not gate
      // whether the byte write itself is visible.
      final image = YuvImage.bgra(2, 2);
      final beforeRevision = image.revision;

      image.yPlane.bytes[0] = 0xAB;
      expect(image.yPlane.bytes[0], 0xAB);
      expect(image.revision, beforeRevision, reason: 'a silent write must not advance the revision on its own');

      image.markDirty();
      expect(image.revision, beforeRevision + 1);
    });

    test('the planes list is structurally immutable', () {
      final image = YuvImage.i420(4, 4);
      expect(() => image.planes.add(YuvPlane(1, 1)), throwsUnsupportedError);
      expect(() => image.planes.removeAt(0), throwsUnsupportedError);
    });
  });

  group('applyPlanes', () {
    test('returns this for chaining', () {
      final image = YuvImage.i420(4, 4);
      final result = image.applyPlanes(image.planes.map((p) => p.copy()));
      expect(result, same(image));
    });

    test('copies the input rather than aliasing it', () {
      final replacement = YuvPlane(4, 4, 1, Uint8List(16));
      final image = YuvImage.i420(4, 4);

      image.applyPlanes([replacement, YuvPlane(2, 2), YuvPlane(2, 2)]);
      replacement.setPixel(0, 0, 250);

      expect(image.yPlane.getPixel(0, 0), 0, reason: 'applyPlanes must copy the supplied planes, not adopt them by reference');
    });

    test('accepts gapped NV12 planes and retains their copy-in contract', () {
      final image = YuvImage.nv12(4, 4, uvPixelStride: 3);
      final replacement = [
        YuvPlane(4, 4),
        YuvPlane(2, 6, 3, Uint8List.fromList([1, 2, 0xEE, 3, 4, 0xEE, 5, 6, 0xEE, 7, 8, 0xEE])),
      ];

      image.applyPlanes(replacement);
      replacement[1].bytes[0] = 0xFF;

      expect(image.uPlane.pixelStride, 3);
      expect(image.uPlane.bytes[0], 1, reason: 'applyPlanes must not alias a gapped NV12 source plane');
    });

    test('advances the revision exactly once', () {
      final image = YuvImage.i420(4, 4);
      final before = image.revision;

      image.applyPlanes([YuvPlane(4, 4), YuvPlane(2, 2), YuvPlane(2, 2)]);

      expect(image.revision, before + 1);
    });

    test('replaces plane content atomically', () {
      final image = YuvImage.i420(2, 2);
      final newY = YuvPlane(2, 2, 1, Uint8List.fromList([1, 2, 3, 4]));

      image.applyPlanes([newY, YuvPlane(1, 1), YuvPlane(1, 1)]);

      expect(image.yPlane.bytes, [1, 2, 3, 4]);
    });

    test('a previously obtained plane reference becomes stale after replacement', () {
      final image = YuvImage.i420(4, 4);
      final staleY = image.yPlane;

      image.applyPlanes([YuvPlane(4, 4), YuvPlane(2, 2), YuvPlane(2, 2)]);
      staleY.setPixel(0, 0, 99);

      expect(image.yPlane.getPixel(0, 0), 0, reason: 'a stale reference must keep pointing at the old storage, not the new one');
      expect(image.yPlane, isNot(same(staleY)));
    });

    test('re-fetching planes after applyPlanes returns new live objects that see further writes', () {
      final image = YuvImage.i420(4, 4);
      image.applyPlanes([YuvPlane(4, 4), YuvPlane(2, 2), YuvPlane(2, 2)]);

      final freshY = image.yPlane;
      freshY.setPixel(1, 1, 77);

      expect(image.yPlane.getPixel(1, 1), 77);
      expect(image.yPlane, same(freshY));
    });

    test('rejects a plane set with the wrong count and leaves the image unchanged', () {
      final image = YuvImage.i420(4, 4);
      final beforeRevision = image.revision;
      final beforeY = image.yPlane;
      image.yPlane.setPixel(0, 0, 55);

      expect(() => image.applyPlanes([YuvPlane(4, 4)]), throwsArgumentError);

      expect(image.revision, beforeRevision, reason: 'a rejected applyPlanes must not bump the revision');
      expect(image.yPlane, same(beforeY), reason: 'a rejected applyPlanes must not replace the plane objects');
      expect(image.yPlane.getPixel(0, 0), 55, reason: 'a rejected applyPlanes must not touch existing plane bytes');
    });

    test('rejects a plane whose geometry cannot hold this image\'s dimensions', () {
      final image = YuvImage.i420(8, 8);
      final beforeRevision = image.revision;

      expect(() => image.applyPlanes([YuvPlane(4, 8), YuvPlane(4, 4), YuvPlane(4, 4)]), throwsArgumentError);

      expect(image.revision, beforeRevision);
      expect(image.yPlane.height, 8, reason: 'the image must keep its own geometry after a rejected applyPlanes');
    });

    test('does not change format or geometry', () {
      final image = YuvImage.i420(4, 6);
      image.applyPlanes([YuvPlane(6, 4), YuvPlane(3, 2), YuvPlane(3, 2)]);

      expect(image.format, YuvPixelFormat.i420);
      expect(image.width, 4);
      expect(image.height, 6);
    });
  });
}
