import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Regression cases for the review findings on YUV-04 and YUV-05.
///
/// Each group pins down a path that previously reached a backend call with a
/// layout the native code cannot handle.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  YuvPlane filled(int height, int rowStride, [int pixelStride = 1]) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

  group('default constructors validate what they allocate', () {
    test('a degenerate luma pixel stride never reaches an allocated plane', () {
      // BGRA always packs four bytes per pixel, so the caller's value is
      // replaced rather than honoured; the other formats use it verbatim and
      // must reject a degenerate one.
      final bgra = YuvImage(YuvFileFormat.bgra8888, 8, 8, yPixelStride: 0);
      expect(bgra.yPlane.pixelStride, 4, reason: 'BGRA must normalize the luma stride to four bytes');
      expect(bgra.yPlane.rowStride, 8 * 4);

      for (final format in const [YuvFileFormat.i420, YuvFileFormat.nv21]) {
        expect(() => YuvImage(format, 8, 8, yPixelStride: 0), throwsArgumentError, reason: '${format.name} accepted yPixelStride 0');
        expect(() => YuvImage(format, 8, 8, yPixelStride: -1), throwsArgumentError, reason: '${format.name} accepted a negative yPixelStride');
      }
    });

    test('a degenerate chroma pixel stride never reaches an allocated plane', () {
      // Interleaved NV chroma is always a packed (U, V) pair, so a smaller
      // value is raised to two instead of producing an unusable plane.
      final nv = YuvImage.nv21(8, 8, uvPixelStride: 0);
      expect(nv.uPlane.pixelStride, 2, reason: 'NV must normalize the chroma stride to a packed pair');

      // I420 uses the caller's value directly for both chroma planes.
      expect(() => YuvImage.i420(8, 8, uvPixelStride: 0), throwsArgumentError);
      expect(() => YuvImage(YuvFileFormat.i420, 8, 8, uvPixelStride: 0), throwsArgumentError);
      expect(() => YuvImage.i420(8, 8, uvPixelStride: -2), throwsArgumentError);
    });

    test('valid default geometry still constructs', () {
      for (final format in YuvFileFormat.values) {
        expect(() => YuvImage(format, 8, 8), returnsNormally, reason: '${format.name} rejected its own default geometry');
      }
    });
  });

  group('interleaved NV chroma requires a packed pair stride', () {
    test('a chroma pixel stride other than two is rejected', () {
      // The converters address chroma as a packed (U, V) pair, and
      // nv21_from_rgba8888 silently does nothing when the stride is not two.
      expect(
        () => YuvImage.nv21(8, 8, planes: [filled(8, 8), filled(4, 12, 3)]),
        throwsArgumentError,
        reason: 'pixelStride 3 reaches native code that assumes a packed pair',
      );
      expect(() => YuvImage.nv21(8, 8, planes: [filled(8, 8), filled(4, 4, 1)]), throwsArgumentError);
    });

    test('a packed pair stride is accepted', () {
      expect(() => YuvImage.nv21(8, 8, planes: [filled(8, 8), filled(4, 8, 2)]), returnsNormally);
    });
  });

  group('I420 chroma planes must share a layout', () {
    test('mismatched U and V strides are rejected', () {
      // The native struct carries one uvRowStride and one uvPixelStride for
      // both planes, so differing geometry would walk one with the other's.
      expect(
        () => YuvImage.i420(8, 8, planes: [filled(8, 8), filled(4, 4), filled(4, 8)]),
        throwsArgumentError,
        reason: 'U and V declared different row strides',
      );
      expect(
        () => YuvImage.i420(8, 8, planes: [filled(8, 8), filled(4, 4, 1), filled(4, 8, 2)]),
        throwsArgumentError,
        reason: 'U and V declared different pixel strides',
      );
    });

    test('matching U and V planes are accepted', () {
      expect(() => YuvImage.i420(8, 8, planes: [filled(8, 8), filled(4, 4), filled(4, 4)]), returnsNormally);
    });
  });

  group('named BGRA constructor enforces an exact plane count', () {
    test('an empty plane list is rejected instead of producing a blank image', () {
      expect(() => YuvImage.bgra(8, 8, planes: const <YuvPlane>[]), throwsArgumentError);
    });

    test('extra planes are rejected instead of being ignored', () {
      expect(() => YuvImage.bgra(8, 8, planes: [filled(8, 32, 4), filled(4, 8, 2)]), throwsArgumentError);
    });

    test('exactly one plane is accepted and keeps its declared layout', () {
      // YUV-15 supersedes the earlier YUV-04 behaviour: a valid padded plane is
      // deep-copied as declared instead of being repacked tightly at
      // construction time. toBgra8888() is what produces a tight buffer.
      final image = YuvImage.bgra(8, 8, planes: [filled(8, 32 + 16, 4)]);
      expect(image.planes.length, 1);
      expect(image.yPlane.rowStride, 32 + 16);
    });

    test('omitting planes still allocates a blank image', () {
      expect(() => YuvImage.bgra(8, 8), returnsNormally);
    });
  });

  group('load() validates before mutating the image', () {
    /// Serializes an arbitrary header and plane table, bypassing save().
    Stream<List<int>> malformedPayload({
      required String format,
      required int width,
      required int height,
      required List<List<int>> planes,
    }) {
      final image = YuvImage.i420(2, 2);
      final chunks = <List<int>>[];
      final sink = _CollectingSink(chunks);
      // Reuse the real writer by saving a valid image, then patching the
      // header and plane table is brittle; instead build the payload by
      // saving an image whose geometry is already the malformed one is not
      // possible, so this test drives load() with a truncated payload.
      return () async* {
        await image.save(sink);
        final bytes = chunks.expand((c) => c).toList();
        // Truncate the payload so the plane table cannot be satisfied.
        yield bytes.sublist(0, bytes.length ~/ 2);
      }();
    }

    test('a truncated payload leaves the image unchanged', () async {
      final image = YuvImage.i420(8, 8);
      final before = (
        width: image.width,
        height: image.height,
        format: image.format,
        planeCount: image.planes.length,
        yLength: image.yPlane.bytes.length,
      );

      // YUV-07 pins this to FormatException; it was deliberately loose while
      // the reader could still surface RangeError or TypeError instead.
      await expectLater(
        image.load(malformedPayload(format: 'i420', width: 8, height: 8, planes: const [])),
        throwsFormatException,
      );

      expect(image.width, before.width, reason: 'width was mutated by a failed load');
      expect(image.height, before.height, reason: 'height was mutated by a failed load');
      expect(image.format, before.format, reason: 'format was mutated by a failed load');
      expect(image.planes.length, before.planeCount, reason: 'planes were mutated by a failed load');
      expect(image.yPlane.bytes.length, before.yLength, reason: 'plane data was mutated by a failed load');
    });

    test('a valid round-trip still loads', () async {
      final source = YuvImage.i420(8, 8);
      source.yPlane.bytes[0] = 42;

      final chunks = <List<int>>[];
      await source.save(_CollectingSink(chunks));

      final target = YuvImage.i420(2, 2);
      await target.load(Stream<List<int>>.fromIterable(chunks));

      expect(target.width, 8);
      expect(target.height, 8);
      expect(target.format, YuvFileFormat.i420);
      expect(target.yPlane.bytes[0], 42);
    });
  });

  group('padded BGRA is refused before an unsafe native effect', () {
    YuvImage paddedBgra() => YuvImage(
          YuvFileFormat.bgra8888,
          8,
          8,
          yPixelStride: 4,
          planes: [filled(8, 8 * 4 + 16, 4)],
        );

    test('blur operations reject a padded plane rather than overflowing', () {
      // These native effects allocate a tight width * height * 4 scratch buffer
      // while addressing it through the source row stride.
      expect(() => paddedBgra().gaussianBlur(radius: 1), throwsArgumentError);
      expect(() => paddedBgra().boxBlur(radius: 1), throwsArgumentError);
      expect(() => paddedBgra().meanBlur(radius: 1), throwsArgumentError);
    });

    test('a tight BGRA plane is still accepted by the same operations', () {
      expect(() => YuvImage.bgra(8, 8).gaussianBlur(radius: 1), returnsNormally);
      expect(() => YuvImage.bgra(8, 8).boxBlur(radius: 1), returnsNormally);
      expect(() => YuvImage.bgra(8, 8).meanBlur(radius: 1), returnsNormally);
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
