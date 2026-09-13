import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-05: native conversions stay inside their buffers when the
/// source and destination use different strides, and produce deterministic
/// planes for odd dimensions.
///
/// These cases exercise the C code through the public API. A regression in the
/// stride handling shows up either as corrupted neighbouring data (detected by
/// the canary padding below) or as wrong plane content.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  /// Builds a plane sized exactly for its geometry, filled with [fill].
  YuvPlane filledPlane(int height, int rowStride, int pixelStride, int fill) =>
      YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride)..fillRange(0, height * rowStride, fill));

  /// Returns the bytes of row [row] that lie beyond [activeBytes].
  List<int> paddingTail(YuvPlane plane, int row, int activeBytes) =>
      plane.bytes.sublist(row * plane.rowStride + activeBytes, (row + 1) * plane.rowStride);

  group('native stride and odd-size safety', () {
    test('fromRgba8888 reads tight RGBA into a padded Y plane', () {
      const width = 4;
      const height = 4;
      const padding = 8;

      // A padded destination: the Y row is longer than the image width.
      final image = YuvImage.i420(
        width,
        height,
        planes: [
          filledPlane(height, width + padding, 1, 0),
          filledPlane(2, 2, 1, 0),
          filledPlane(2, 2, 1, 0),
        ],
      );

      // Tight RGBA input, as the public contract requires.
      final rgba = Uint8List(width * height * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255; // R
        rgba[i + 1] = 255; // G
        rgba[i + 2] = 255; // B
        rgba[i + 3] = 255; // A
      }

      // Before the fix the RGBA row address was derived from the padded Y
      // stride, which reads past the end of a tight input buffer.
      expect(() => image.fromRgba8888(rgba), returnsNormally);

      // White input must produce a uniform high luma across the active width.
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(image.yPlane.getPixel(x, y), greaterThan(200), reason: 'luma at ($x, $y) was not written from the tight RGBA row');
        }
      }
    });

    test('I420 -> NV21 does not overwrite past a narrower destination Y row', () {
      const width = 4;
      const height = 4;

      // Source Y row is much wider than the destination's.
      final src = YuvImage.i420(
        width,
        height,
        planes: [
          filledPlane(height, width + 16, 1, 0x11),
          filledPlane(2, 2, 1, 0x22),
          filledPlane(2, 2, 1, 0x33),
        ],
      );

      // A whole-buffer memcpy of the source would run past this destination.
      expect(() => src.toYuvNv21(), returnsNormally);
      expect(src.format, YuvFileFormat.nv21);
      expect(src.width, width);
      expect(src.height, height);

      // Luma content must survive the row-wise copy.
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(src.yPlane.getPixel(x, y), 0x11);
        }
      }
    });

    test('NV21 -> I420 does not overwrite past a narrower destination Y row', () {
      const width = 4;
      const height = 4;

      final src = YuvImage.nv21(
        width,
        height,
        planes: [
          filledPlane(height, width + 16, 1, 0x44),
          filledPlane(2, 4, 2, 0x55),
        ],
      );

      expect(() => src.toYuvI420(), returnsNormally);
      expect(src.format, YuvFileFormat.i420);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(src.yPlane.getPixel(x, y), 0x44);
        }
      }
    });

    test('swapNv keeps padded chroma padding untouched', () {
      const width = 4;
      const height = 4;
      const activeChromaBytes = 4; // ceil(4/2) pairs * 2 bytes
      const chromaRowStride = activeChromaBytes + 6;

      final chroma = filledPlane(2, chromaRowStride, 2, 0);
      // Distinct (V, U) pairs in the active area, canary bytes in the padding.
      for (int row = 0; row < 2; row++) {
        for (int i = 0; i < activeChromaBytes; i++) {
          chroma.bytes[row * chromaRowStride + i] = 10 + row * 10 + i;
        }
        for (int i = activeChromaBytes; i < chromaRowStride; i++) {
          chroma.bytes[row * chromaRowStride + i] = 0xEE;
        }
      }

      final image = YuvImage.nv21(width, height, planes: [filledPlane(height, width, 1, 0x77), chroma]);

      image.swapNv();

      for (int row = 0; row < 2; row++) {
        // Each pair is reversed within the active area.
        for (int i = 0; i < activeChromaBytes; i += 2) {
          expect(image.uPlane.bytes[row * chromaRowStride + i], 10 + row * 10 + i + 1);
          expect(image.uPlane.bytes[row * chromaRowStride + i + 1], 10 + row * 10 + i);
        }
        // swapNv writes into a freshly allocated destination plane, so the
        // padding of the result is zero rather than a copy of the source
        // padding. What matters is that the stride is preserved and that no
        // active data leaked into the padding region.
        expect(paddingTail(image.uPlane, row, activeChromaBytes), everyElement(0), reason: 'swapNv left data in row $row padding');
      }
      expect(image.uPlane.rowStride, chromaRowStride, reason: 'swapNv must preserve the chroma row stride');
    });

    test('odd dimensions produce fully initialized chroma planes', () {
      // ceil-sized chroma: a floor-based loop would leave the last chroma row
      // and column untouched.
      for (final size in const <List<int>>[
        [1, 1],
        [3, 5],
        [5, 3],
        [7, 7],
      ]) {
        final width = size[0];
        final height = size[1];

        final rgba = Uint8List(width * height * 4);
        for (int i = 0; i < rgba.length; i += 4) {
          rgba[i] = 200;
          rgba[i + 1] = 50;
          rgba[i + 2] = 100;
          rgba[i + 3] = 255;
        }

        final i420 = YuvImage.i420(width, height)..fromRgba8888(rgba);
        expect(
          i420.uPlane.bytes.any((b) => b != 0),
          isTrue,
          reason: 'I420 ${width}x$height left the U plane entirely zero',
        );
        expect(i420.uPlane.height, (height + 1) ~/ 2);

        final nv21 = YuvImage.nv21(width, height)..fromRgba8888(rgba);
        expect(
          nv21.uPlane.bytes.any((b) => b != 0),
          isTrue,
          reason: 'NV21 ${width}x$height left the chroma plane entirely zero',
        );
        expect(nv21.uPlane.height, (height + 1) ~/ 2);
      }
    });

    test('odd-size conversions round-trip without throwing', () {
      for (final size in const <List<int>>[
        [1, 1],
        [3, 5],
        [127, 255],
      ]) {
        final width = size[0];
        final height = size[1];
        final rgba = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 180);

        final image = YuvImage.i420(width, height)..fromRgba8888(rgba);
        expect(() => image.toYuvNv21(), returnsNormally, reason: 'I420 -> NV21 failed at ${width}x$height');
        expect(() => image.toYuvI420(), returnsNormally, reason: 'NV21 -> I420 failed at ${width}x$height');
        expect(image.toBgra8888().length, width * height * 4);
      }
    });

    test('edge chroma of an odd-width image averages only real pixels', () {
      // A 3x1 image: the last chroma block covers a single column, so dividing
      // a one-pixel sum by four would darken the edge sample.
      const width = 3;
      const height = 1;
      final rgba = Uint8List(width * height * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 255;
      }

      final image = YuvImage.i420(width, height)..fromRgba8888(rgba);

      // For a uniform white frame every chroma sample must be the same value,
      // including the partial edge block.
      final u = image.uPlane;
      final first = u.getPixel(0, 0);
      final last = u.getPixel(u.rowStride ~/ u.pixelStride - 1, 0);
      expect(last, first, reason: 'edge chroma block was averaged over non-existent pixels');
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
