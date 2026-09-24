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

  YuvPlane canaryPlane(int height, int rowStride, int pixelStride) => filledPlane(height, rowStride, pixelStride, 0xA5);

  void expectPaddingUntouched(YuvPlane plane, {required int logicalWidth, required int sampleBytes}) {
    for (int row = 0; row < plane.height; row++) {
      final logicalOffsets = <int>{};
      for (int column = 0; column < logicalWidth; column++) {
        final start = column * plane.pixelStride;
        for (int byte = 0; byte < sampleBytes; byte++) {
          logicalOffsets.add(start + byte);
        }
      }
      for (int offset = 0; offset < plane.rowStride; offset++) {
        if (!logicalOffsets.contains(offset)) {
          expect(plane.bytes[row * plane.rowStride + offset], 0xA5, reason: 'padding byte $offset in row $row was modified');
        }
      }
    }
  }

  group('native stride and odd-size safety', () {
    test('fromRgba8888 reads tight RGBA into a padded Y plane', () {
      const width = 4;
      const height = 4;
      const padding = 8;

      // A padded destination: the Y row is longer than the image width.
      final image = YuvImage.i420(
        width,
        height,
        planes: [filledPlane(height, width + padding, 1, 0), filledPlane(2, 2, 1, 0), filledPlane(2, 2, 1, 0)],
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
      // ignore: deprecated_member_use_from_same_package
      expect(() => image.fromRgba8888(rgba), returnsNormally);

      // White input must produce a uniform high luma across the active width.
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(image.yPlane.getPixel(x, y), greaterThan(200), reason: 'luma at ($x, $y) was not written from the tight RGBA row');
        }
      }
    });

    test('fromRgba8888 preserves row and pixel padding in every format', () {
      const width = 3;
      const height = 5;
      final chromaWidth = (width + 1) ~/ 2;
      final chromaHeight = (height + 1) ~/ 2;
      final rgba = Uint8List(width * height * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = (20 + i) & 0xFF;
        rgba[i + 1] = (90 + i) & 0xFF;
        rgba[i + 2] = (170 + i) & 0xFF;
        rgba[i + 3] = 255;
      }

      // ignore: deprecated_member_use_from_same_package
      final baselineBgra = YuvImage.bgra(width, height)..fromRgba8888(rgba);
      // ignore: deprecated_member_use_from_same_package
      final paddedBgra = YuvImage(YuvFileFormat.bgra8888, width, height, planes: [canaryPlane(height, width * 4 + 7, 4)])..fromRgba8888(rgba);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          final expected = row * baselineBgra.yPlane.rowStride + column * 4;
          final actual = row * paddedBgra.yPlane.rowStride + column * 4;
          expect(paddedBgra.yPlane.bytes.sublist(actual, actual + 4), orderedEquals(baselineBgra.yPlane.bytes.sublist(expected, expected + 4)));
        }
      }
      expectPaddingUntouched(paddedBgra.yPlane, logicalWidth: width, sampleBytes: 4);

      // ignore: deprecated_member_use_from_same_package
      final baselineI420 = YuvImage.i420(width, height)..fromRgba8888(rgba);
      final paddedI420 = YuvImage.i420(
        width,
        height,
        planes: [
          canaryPlane(height, width * 2 + 3, 2),
          canaryPlane(chromaHeight, chromaWidth * 2 + 2, 2),
          canaryPlane(chromaHeight, chromaWidth * 2 + 2, 2),
        ],
        // ignore: deprecated_member_use_from_same_package
      )..fromRgba8888(rgba);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          expect(paddedI420.yPlane.getPixel(column, row), baselineI420.yPlane.getPixel(column, row));
        }
      }
      for (int row = 0; row < chromaHeight; row++) {
        for (int column = 0; column < chromaWidth; column++) {
          expect(paddedI420.uPlane.getPixel(column, row), baselineI420.uPlane.getPixel(column, row));
          expect(paddedI420.vPlane.getPixel(column, row), baselineI420.vPlane.getPixel(column, row));
        }
      }
      expectPaddingUntouched(paddedI420.yPlane, logicalWidth: width, sampleBytes: 1);
      expectPaddingUntouched(paddedI420.uPlane, logicalWidth: chromaWidth, sampleBytes: 1);
      expectPaddingUntouched(paddedI420.vPlane, logicalWidth: chromaWidth, sampleBytes: 1);

      // ignore: deprecated_member_use_from_same_package
      final baselineNv = YuvImage.nv21(width, height)..fromRgba8888(rgba);
      // ignore: deprecated_member_use_from_same_package
      final paddedNv = YuvImage.nv21(
        width,
        height,
        planes: [canaryPlane(height, width * 2 + 3, 2), canaryPlane(chromaHeight, chromaWidth * 2 + 3, 2)],
        // ignore: deprecated_member_use_from_same_package
      )..fromRgba8888(rgba);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          expect(paddedNv.yPlane.getPixel(column, row), baselineNv.yPlane.getPixel(column, row));
        }
      }
      for (int row = 0; row < chromaHeight; row++) {
        for (int column = 0; column < chromaWidth; column++) {
          final actual = row * paddedNv.uPlane.rowStride + column * 2;
          final expected = row * baselineNv.uPlane.rowStride + column * 2;
          expect(paddedNv.uPlane.bytes.sublist(actual, actual + 2), orderedEquals(baselineNv.uPlane.bytes.sublist(expected, expected + 2)));
        }
      }
      expectPaddingUntouched(paddedNv.yPlane, logicalWidth: width, sampleBytes: 1);
      expectPaddingUntouched(paddedNv.uPlane, logicalWidth: chromaWidth, sampleBytes: 2);
    });

    test('I420 -> NV21 does not overwrite past a narrower destination Y row', () {
      const width = 4;
      const height = 4;

      // Source Y row is much wider than the destination's.
      final src = YuvImage.i420(
        width,
        height,
        planes: [filledPlane(height, width + 16, 1, 0x11), filledPlane(2, 2, 1, 0x22), filledPlane(2, 2, 1, 0x33)],
      );

      // A whole-buffer memcpy of the source would run past this destination.
      // ignore: deprecated_member_use_from_same_package
      expect(() => src.toYuvNv21(), returnsNormally);
      expect(src.format, YuvPixelFormat.nv12);
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

      // ignore: deprecated_member_use_from_same_package
      final src = YuvImage.nv21(width, height, planes: [filledPlane(height, width + 16, 1, 0x44), filledPlane(2, 4, 2, 0x55)]);

      // ignore: deprecated_member_use_from_same_package
      expect(() => src.toYuvI420(), returnsNormally);
      expect(src.format, YuvPixelFormat.i420);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          expect(src.yPlane.getPixel(x, y), 0x44);
        }
      }
    });

    test('I420 and NV conversions copy logical luma with custom pixel stride', () {
      const width = 5;
      const height = 3;
      final expected = List<int>.generate(width * height, (index) => 20 + index);

      YuvPlane stridedLuma() {
        final plane = canaryPlane(height, width * 3 + 4, 3);
        for (int row = 0; row < height; row++) {
          for (int column = 0; column < width; column++) {
            plane.setPixel(column, row, expected[row * width + column]);
          }
        }
        return plane;
      }

      // ignore: deprecated_member_use_from_same_package
      final i420 = YuvImage.i420(width, height, planes: [stridedLuma(), filledPlane(2, 3, 1, 100), filledPlane(2, 3, 1, 150)])..toYuvNv21();
      expect([
        for (int row = 0; row < height; row++)
          for (int column = 0; column < width; column++) i420.yPlane.getPixel(column, row),
      ], orderedEquals(expected));

      // ignore: deprecated_member_use_from_same_package
      final nv = YuvImage.nv21(width, height, planes: [stridedLuma(), filledPlane(2, 6, 2, 128)])..toYuvI420();
      expect([
        for (int row = 0; row < height; row++)
          for (int column = 0; column < width; column++) nv.yPlane.getPixel(column, row),
      ], orderedEquals(expected));
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

      // ignore: deprecated_member_use_from_same_package
      final image = YuvImage.nv21(width, height, planes: [filledPlane(height, width, 1, 0x77), chroma]);

      // ignore: deprecated_member_use_from_same_package
      image.swapNv();

      for (int row = 0; row < 2; row++) {
        // Each pair is reversed within the active area.
        for (int i = 0; i < activeChromaBytes; i += 2) {
          expect(image.uPlane.bytes[row * chromaRowStride + i], 10 + row * 10 + i + 1);
          expect(image.uPlane.bytes[row * chromaRowStride + i + 1], 10 + row * 10 + i);
        }
        // Since YUV-50 swapNv publishes through the ABI v1 transport, which
        // writes only active samples into the receiver's existing layout, so
        // the source padding survives verbatim instead of being replaced by a
        // freshly zeroed allocation. Either way no active data may leak into
        // the padding region, which is what the canary below checks.
        expect(paddingTail(image.uPlane, row, activeChromaBytes), everyElement(0xEE), reason: 'swapNv overwrote row $row padding');
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

        // ignore: deprecated_member_use_from_same_package
        final i420 = YuvImage.i420(width, height)..fromRgba8888(rgba);
        expect(i420.uPlane.bytes.any((b) => b != 0), isTrue, reason: 'I420 ${width}x$height left the U plane entirely zero');
        expect(i420.uPlane.height, (height + 1) ~/ 2);

        // ignore: deprecated_member_use_from_same_package
        final nv21 = YuvImage.nv21(width, height)..fromRgba8888(rgba);
        expect(nv21.uPlane.bytes.any((b) => b != 0), isTrue, reason: 'NV21 ${width}x$height left the chroma plane entirely zero');
        expect(nv21.uPlane.height, (height + 1) ~/ 2);
      }
    });

    test('every odd-edge chroma sample is written in UV order', () {
      for (final size in const <({int width, int height})>[(width: 1, height: 1), (width: 3, height: 5), (width: 127, height: 255)]) {
        final rgba = Uint8List(size.width * size.height * 4);
        for (int i = 0; i < rgba.length; i += 4) {
          rgba[i] = 255;
          rgba[i + 3] = 255;
        }
        final chromaWidth = (size.width + 1) ~/ 2;
        final chromaHeight = (size.height + 1) ~/ 2;
        final i420 = YuvImage.i420(
          size.width,
          size.height,
          planes: [
            canaryPlane(size.height, size.width + 3, 1),
            canaryPlane(chromaHeight, chromaWidth + 2, 1),
            canaryPlane(chromaHeight, chromaWidth + 2, 1),
          ],
          // ignore: deprecated_member_use_from_same_package
        )..fromRgba8888(rgba);
        // ignore: deprecated_member_use_from_same_package
        final nv = YuvImage.nv21(
          size.width,
          size.height,
          planes: [canaryPlane(size.height, size.width + 3, 1), canaryPlane(chromaHeight, chromaWidth * 2 + 3, 2)],
          // ignore: deprecated_member_use_from_same_package
        )..fromRgba8888(rgba);

        final expectedU = i420.uPlane.getPixel(0, 0);
        final expectedV = i420.vPlane.getPixel(0, 0);
        expect(expectedU, isNot(expectedV), reason: 'fixture must distinguish U from V');
        for (int row = 0; row < chromaHeight; row++) {
          for (int column = 0; column < chromaWidth; column++) {
            expect(i420.uPlane.getPixel(column, row), expectedU, reason: 'I420 U at ($column, $row) for $size');
            expect(i420.vPlane.getPixel(column, row), expectedV, reason: 'I420 V at ($column, $row) for $size');
            final offset = row * nv.uPlane.rowStride + column * 2;
            expect(nv.uPlane.bytes[offset], expectedU, reason: 'NV U at ($column, $row) for $size');
            expect(nv.uPlane.bytes[offset + 1], expectedV, reason: 'NV V at ($column, $row) for $size');
          }
        }
        expectPaddingUntouched(i420.yPlane, logicalWidth: size.width, sampleBytes: 1);
        expectPaddingUntouched(i420.uPlane, logicalWidth: chromaWidth, sampleBytes: 1);
        expectPaddingUntouched(i420.vPlane, logicalWidth: chromaWidth, sampleBytes: 1);
        expectPaddingUntouched(nv.yPlane, logicalWidth: size.width, sampleBytes: 1);
        expectPaddingUntouched(nv.uPlane, logicalWidth: chromaWidth, sampleBytes: 2);
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

        // ignore: deprecated_member_use_from_same_package
        final image = YuvImage.i420(width, height)..fromRgba8888(rgba);
        // ignore: deprecated_member_use_from_same_package
        expect(() => image.toYuvNv21(), returnsNormally, reason: 'I420 -> NV21 failed at ${width}x$height');
        // ignore: deprecated_member_use_from_same_package
        expect(() => image.toYuvI420(), returnsNormally, reason: 'NV21 -> I420 failed at ${width}x$height');
        // ignore: deprecated_member_use_from_same_package
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

      // ignore: deprecated_member_use_from_same_package
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
