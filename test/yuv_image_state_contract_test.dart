@Tags(['contract'])
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Characterization tests for the state/geometry/accessor contract the three
/// `YuvImageImpl` backends share.
///
/// They define behavior shared by all backends. They deliberately
/// exercise only the parts of the contract that need no backend call, so the
/// same file is meaningful on the VM and in a browser.
void main() {
  group('plane accessor contract', () {
    test('BGRA exposes exactly one plane', () {
      final image = YuvImage.bgra(4, 4);
      expect(image.planes, hasLength(1));
      expect(image.yPlane, same(image.planes.single));
    });

    test('NV12 exposes two planes', () {
      final image = YuvImage.nv12(4, 4);
      expect(image.planes, hasLength(2));
      expect(image.uPlane, same(image.planes[1]));
    });

    test('I420 exposes three planes', () {
      final image = YuvImage.i420(4, 4);
      expect(image.planes, hasLength(3));
      expect(image.uPlane, same(image.planes[1]));
      expect(image.vPlane, same(image.planes[2]));
    });

    test('planes is an unmodifiable view, so callers cannot resize the state', () {
      final image = YuvImage.i420(4, 4);
      expect(() => image.planes.removeLast(), throwsUnsupportedError);
    });

    test('BGRA luma plane has complete packed storage', () {
      final bgra = YuvImage.bgra(2, 2);
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
      final image = YuvImage(YuvPixelFormat.bgra8888, 3, 2);
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
        final blank = YuvImage.allocate(image.format, image.width, image.height);

        expect(
          blank.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride)),
          orderedEquals(image.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride))),
        );
        expect(blank.planes.every((plane) => plane.bytes.every((byte) => byte == 0)), isTrue);
      }
    });

    test('named factories migrate padded I420, NV12, and BGRA blank copies', () {
      final sources = <YuvImage>[
        YuvImage.i420(4, 4, planes: [YuvPlane(4, 10, 2), YuvPlane(2, 8, 3), YuvPlane(2, 8, 3)]),
        YuvImage.nv12(4, 4, planes: [YuvPlane(4, 8, 1), YuvPlane(2, 8, 3)]),
        YuvImage.bgra(2, 2, planes: [YuvPlane(2, 15, 5)]),
      ];

      for (final source in sources) {
        for (final plane in source.planes) {
          plane.bytes.fillRange(0, plane.bytes.length, 0x7F);
        }

        final blank = _blankWithSourceLayout(source);
        source.yPlane.setPixel(0, 0, 0x11);

        expect(blank.format, source.format);
        expect(blank.width, source.width);
        expect(blank.height, source.height);
        expect(
          blank.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride)),
          orderedEquals(source.planes.map((plane) => (height: plane.height, rowStride: plane.rowStride, pixelStride: plane.pixelStride))),
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
      expect(image.toBytes(), hasLength(expected));
    });

    test('is a snapshot, not a view onto the live planes', () {
      final image = YuvImage.bgra(2, 2);
      // ignore: deprecated_member_use_from_same_package
      final bytes = image.toBytes();
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

YuvImage _blankWithSourceLayout(YuvImage source) {
  final planes = [for (final plane in source.planes) YuvPlane(plane.height, plane.rowStride, plane.pixelStride)];

  return switch (source.format) {
    YuvPixelFormat.i420 => YuvImage.i420(source.width, source.height, planes: planes),
    YuvPixelFormat.nv12 => YuvImage.nv12(source.width, source.height, planes: planes),
    YuvPixelFormat.bgra8888 => YuvImage.bgra(source.width, source.height, planes: planes),
  };
}
