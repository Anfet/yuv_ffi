import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Characterization tests for the state/geometry/accessor contract the three
/// `YuvImageImpl` backends share (YUV-28).
///
/// These were written against the pre-unification implementations and must keep
/// passing unchanged afterwards: they are the evidence that moving state into a
/// shared owner preserved behavior rather than redefining it. They deliberately
/// exercise only the parts of the contract that need no backend call, so the
/// same file is meaningful on the VM and in a browser.
void main() {
  group('plane accessor contract', () {
    test('BGRA exposes exactly one plane, with u and v null', () {
      final image = YuvImage.bgra(4, 4);
      expect(image.planes, hasLength(1));
      // ignore: deprecated_member_use_from_same_package
      expect(image.y, same(image.yPlane));
      // ignore: deprecated_member_use_from_same_package
      expect(image.u, isNull);
      // ignore: deprecated_member_use_from_same_package
      expect(image.v, isNull);
    });

    test('NV21 exposes two planes, with v null', () {
      final image = YuvImage.nv12(4, 4);
      expect(image.planes, hasLength(2));
      // ignore: deprecated_member_use_from_same_package
      expect(image.u, same(image.uPlane));
      // ignore: deprecated_member_use_from_same_package
      expect(image.v, isNull);
    });

    test('I420 exposes three planes', () {
      final image = YuvImage.i420(4, 4);
      expect(image.planes, hasLength(3));
      // ignore: deprecated_member_use_from_same_package
      expect(image.u, same(image.uPlane));
      // ignore: deprecated_member_use_from_same_package
      expect(image.v, same(image.vPlane));
    });

    test('planes is an unmodifiable view, so callers cannot resize the state', () {
      final image = YuvImage.i420(4, 4);
      expect(() => image.planes.removeLast(), throwsUnsupportedError);
    });

    test('a nullable accessor beyond the format plane count returns null rather than a sentinel', () {
      // The empty/unavailable-state contract: `u`/`v` are the only accessors
      // that report absence, and they report it as `null`. There is no
      // zero-length sentinel plane in the contract -- every format-required
      // plane accessor (`yPlane`, and `uPlane`/`vPlane` for the formats that
      // have them) always returns a real, fully allocated plane.
      final bgra = YuvImage.bgra(2, 2);
      // ignore: deprecated_member_use_from_same_package
      expect(bgra.u, isNull);
      // ignore: deprecated_member_use_from_same_package
      expect(bgra.v, isNull);
      expect(bgra.yPlane.bytes, hasLength(2 * 2 * 4));
    });
  });

  group('geometry contract', () {
    test('size mirrors width and height', () {
      final image = YuvImage.i420(6, 4);
      expect(image.size.width, 6.0);
      expect(image.size.height, 4.0);
    });

    test('odd dimensions keep the trailing half chroma row and column', () {
      final image = YuvImage.i420(3, 3);
      expect(image.uPlane.height, 2);
      expect(image.uPlane.rowStride, 2);
      expect(image.vPlane.height, 2);
    });

    test('NV21 chroma is allocated as interleaved pairs', () {
      final image = YuvImage.nv12(4, 4);
      expect(image.uPlane.pixelStride, 2);
      expect(image.uPlane.rowStride, 4);
    });

    test('BGRA luma is four bytes per sample regardless of the requested stride', () {
      // ignore: deprecated_member_use_from_same_package
      final image = YuvImage(YuvFileFormat.bgra8888, 3, 2);
      expect(image.yPlane.pixelStride, 4);
      expect(image.yPlane.rowStride, 12);
    });

    test('a non-positive dimension is rejected before any allocation', () {
      expect(() => YuvImage.i420(0, 4), throwsArgumentError);
      expect(() => YuvImage.i420(4, -1), throwsArgumentError);
    });

    test('a caller-supplied plane list of the wrong length is rejected', () {
      expect(() => YuvImage.i420(4, 4, planes: [YuvPlane(4, 4)]), throwsArgumentError);
    });
  });

  group('copy contract', () {
    test('copy is deep: mutating the source leaves the copy alone', () {
      final source = YuvImage.i420(4, 4);
      source.yPlane.setPixel(0, 0, 200);
      final clone = source.copy();
      source.yPlane.setPixel(0, 0, 10);
      expect(clone.yPlane.getPixel(0, 0), 200);
    });

    test('a blank copy preserves padded I420, NV12, and BGRA layouts while zeroing bytes', () {
      final images = <YuvImage>[
        YuvImage.i420(4, 4, planes: [YuvPlane(4, 10, 2), YuvPlane(2, 8, 3), YuvPlane(2, 8, 3)]),
        YuvImage.nv12(4, 4, planes: [YuvPlane(4, 8, 1), YuvPlane(2, 8, 3)]),
        YuvImage.bgra(2, 2, planes: [YuvPlane(2, 15, 5)]),
      ];

      for (final image in images) {
        image.yPlane.setPixel(0, 0, 77);
        // ignore: deprecated_member_use_from_same_package
        final blank = image.copy(blank: true);

        expect(
          blank.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride)),
          orderedEquals(image.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride))),
        );
        expect(blank.planes.every((plane) => plane.bytes.every((byte) => byte == 0)), isTrue);
      }
    });

    test('copy preserves format, geometry and plane strides', () {
      final source = YuvImage.nv12(6, 4);
      final clone = source.copy();
      expect(clone.format, source.format);
      expect(clone.width, source.width);
      expect(clone.height, source.height);
      expect(clone.uPlane.pixelStride, source.uPlane.pixelStride);
    });

    test('a copy carries its own revision counter, independent of the source', () {
      final source = YuvImage.i420(4, 4);
      final clone = source.copy();
      final cloneRevisionBefore = clone.revision;
      source.markDirty();
      expect(clone.revision, cloneRevisionBefore);
    });
  });

  group('getBytes contract', () {
    test('concatenates every plane in format order', () {
      final image = YuvImage.i420(4, 4);
      final expected = image.planes.fold<int>(0, (sum, p) => sum + p.bytes.length);
      // ignore: deprecated_member_use_from_same_package
      expect(image.getBytes(), hasLength(expected));
    });

    test('is a snapshot, not a view onto the live planes', () {
      final image = YuvImage.bgra(2, 2);
      // ignore: deprecated_member_use_from_same_package
      final bytes = image.getBytes();
      image.yPlane.setPixel(0, 0, 255);
      expect(bytes[0], 0);
    });
  });

  group('revision contract', () {
    test('two freshly constructed images report the same starting revision', () {
      expect(YuvImage.i420(4, 4).revision, YuvImage.i420(4, 4).revision);
    });

    test('markDirty advances the revision by exactly one', () {
      final image = YuvImage.i420(4, 4);
      final before = image.revision;
      image.markDirty();
      expect(image.revision, before + 1);
    });
  });
}
